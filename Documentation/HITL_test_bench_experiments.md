# KV260 RPU — HITL Test Bench Experiments

**Status: draft, still to be approved.**

Experiments run on the test bench of `HITL_test_bench_steps.md` (tap points T1–T8 and pins A0–A4, R0–R4 are defined in its channel map). Measurements go in `HITL_test_bench_results.md`.

---

## E0: Measurement validation

Goes into the methodology section.

1. **Marker overhead and resolution:** 100k back-to-back toggles from each core. The minimum and spread of the deltas give the per-marker cost and the smallest interval you can resolve.
2. **Synchronizer delay:** a constant 2–3 cycles. Report it.
3. **External cross-check:** compare PMOD edges on a scope or logic analyzer against the PL timestamps for the same events.
4. **Intrusion:** compare loop period and CPU load with taps compiled in vs removed.

## E1: RPMsg link

1. One-way latency in each direction, APU→R5 (A1→R0) and R5→APU (R3→A2). The shared time base makes this possible instead of halving the round trip, which is a strong point for the paper.
2. Sweep message size up to the maximum MAVLink v2 frame (~280 B), and sweep rate from the HITL rate up to saturation.
3. Run with PX4 idle and with PX4 flying.
4. At least 100k samples per configuration. Report median, p99, p99.9 and max, plus losses and the sustainable throughput.

## E2: End-to-end loop latency

1. T1→T8 during hover, broken down:
   - APU in (A0→A1)
   - link in (A1→R0)
   - R5 processing (R0→R3, with R0→R2 as the control part)
   - link out (R3→A2)
   - APU out (A2→A3)
2. Host and Gazebo share measured separately with the host clock and UDP round-trip time.
3. Present as a stacked latency budget plus per-segment distributions.

## E3: Control loop rate and jitter

1. From R1: period histogram, standard deviation, worst-case deviation, missed deadlines, and execution time from pulse width.
2. R5 CPU load during hover from the `cpuload` topic, to quantify the spare compute.

## E4: APU under load

1. Repeat E1–E3 under each load profile (M9).
2. For each, run the bridge pinned at RT priority and at defaults.
3. Expected story: the R5 segments stay stable while the APU segments degrade. The memory-bandwidth profile tests whether that isolation holds through the shared DDR.

## E5: Flight tracking vs SITL

1. Same PX4 commit, airframe parameters, world and mission in both setups. At least 5 runs each.
2. Position and attitude RMSE and mission time from ULog. The PL isn't needed here.
