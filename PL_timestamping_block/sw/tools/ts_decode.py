#!/usr/bin/env python3
"""Decode ts_reader logs: a 32-byte header followed by raw 8-byte PL timestamp events."""

import argparse
import csv
import statistics
import struct
import sys
from typing import NamedTuple

HDR = struct.Struct("<8sIIQQ")
EV = struct.Struct("<II")
MAGIC = b"TSLOG"
TS_WRAP = 1 << 44
NUM_CH = 8


class Event(NamedTuple):
    ts: int      # ticks, unwrapped past the 44-bit counter wrap
    change: int  # ch_change bitmask
    level: int   # ch_level bitmask after the change
    ovf: int


class Log(NamedTuple):
    version: int
    clk_hz: int
    start_realtime_ns: int
    start_monotonic_ns: int
    events: list


def read_log(path):
    with open(path, "rb") as f:
        data = f.read()
    if len(data) < HDR.size:
        sys.exit(f"{path}: shorter than the log header")

    magic, version, clk_hz, rt_ns, mono_ns = HDR.unpack_from(data)
    if magic.rstrip(b"\0") != MAGIC:
        sys.exit(f"{path}: bad magic {magic!r}")
    if version != 1:
        sys.exit(f"{path}: unsupported version {version}")

    body = data[HDR.size:]
    if len(body) % EV.size:
        print(f"warning: {len(body) % EV.size} trailing bytes ignored", file=sys.stderr)
        body = body[: len(body) - len(body) % EV.size]

    events = []
    offset = 0
    prev_raw = None
    for w0, w1 in EV.iter_unpack(body):
        raw = w0 | ((w1 & 0xFFF) << 32)
        if prev_raw is not None and raw < prev_raw:
            offset += TS_WRAP
        prev_raw = raw
        events.append(Event(raw + offset, (w1 >> 20) & 0xFF, (w1 >> 12) & 0xFF, w1 >> 31))

    return Log(version, clk_hz, rt_ns, mono_ns, events)


def edges(events, ch):
    """Timestamps of every event that changed channel ch."""
    return [e.ts for e in events if e.change & (1 << ch)]


def clk_of(args, log):
    return args.clk if args.clk else log.clk_hz


def cmd_summary(args):
    log = read_log(args.log)
    ev = log.events
    clk = clk_of(args, log)
    print(f"version {log.version}  clk {clk} Hz  events {len(ev)}  ovf {sum(e.ovf for e in ev)}")
    if ev:
        span = ev[-1].ts - ev[0].ts
        print(f"span {span} ticks = {span / clk:.6f} s")
    for ch in range(NUM_CH):
        print(f"  ch{ch} {len(edges(ev, ch))}")
    return 0


def cmd_csv(args):
    log = read_log(args.log)
    clk = clk_of(args, log)
    t0 = log.events[0].ts if log.events else 0

    out = open(args.output, "w", newline="") if args.output else sys.stdout
    w = csv.writer(out)
    w.writerow(["event", "ts_ticks", "t_ns", "ch", "level", "ovf"])
    for i, e in enumerate(log.events):
        for ch in range(NUM_CH):
            if e.change & (1 << ch):
                w.writerow([i, e.ts, f"{(e.ts - t0) * 1e9 / clk:.1f}", ch, (e.level >> ch) & 1, e.ovf])
    if out is not sys.stdout:
        out.close()
    return 0


def cmd_toggle(args):
    """Checks a `ts_test toggle` run: edge count, no overflow, mean period."""
    log = read_log(args.log)
    clk = clk_of(args, log)
    ts = edges(log.events, args.ch)
    ovf = sum(e.ovf for e in log.events)
    tol_us = args.tol_us if args.tol_us is not None else args.period_us * 0.01

    print(f"ch{args.ch}: {len(ts)} edges (expected {args.n}), ovf {ovf}")
    ok = len(ts) == args.n and ovf == 0

    if len(ts) >= 2:
        d = [(b - a) * 1e6 / clk for a, b in zip(ts, ts[1:])]
        mean = statistics.fmean(d)
        sd = statistics.pstdev(d)
        print(f"period us: mean {mean:.3f}  sd {sd:.3f}  min {min(d):.3f}  max {max(d):.3f}"
              f"  (expected {args.period_us}, tol {tol_us:.3f})")
        ok = ok and abs(mean - args.period_us) <= tol_us
    else:
        ok = False

    print("PASS" if ok else "FAIL")
    return 0 if ok else 1


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--clk", type=float, help="pl_clk0 in Hz (default: header value; use `ts_test clock`)")
    sub = p.add_subparsers(dest="cmd", required=True)

    s = sub.add_parser("summary", help="event and per-channel counts")
    s.add_argument("log")
    s.set_defaults(func=cmd_summary)

    s = sub.add_parser("csv", help="one row per channel edge")
    s.add_argument("log")
    s.add_argument("-o", "--output")
    s.set_defaults(func=cmd_csv)

    s = sub.add_parser("toggle", help="check a `ts_test toggle` run")
    s.add_argument("log")
    s.add_argument("--ch", type=int, required=True)
    s.add_argument("--n", type=int, required=True)
    s.add_argument("--period-us", type=float, required=True)
    s.add_argument("--tol-us", type=float, help="allowed mean-period error (default 1%% of period)")
    s.set_defaults(func=cmd_toggle)

    args = p.parse_args()
    sys.exit(args.func(args))


if __name__ == "__main__":
    main()
