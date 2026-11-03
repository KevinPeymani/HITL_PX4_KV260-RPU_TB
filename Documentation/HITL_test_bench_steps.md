# KV260 RPU — HITL Test Bench Steps

Measure the HITL loop of PX4 on the KV260 R5 with hardware timestamps: tap points on the APU and the R5 drive PL pins, and a PL block timestamps every edge. Measurements and recorded values are in `HITL_test_bench_results.md`.

Starting point, implemented with the earlier step files (each with its results file next to it):

| Part | Steps | Results |
|---|---|---|
| NuttX port to the R5 (bring-up, remoteproc, RPMsg, NSH console) | `NuttX/Documentation/board_bringup_steps.md` | `NuttX/Documentation/board_bringup_results.md` |
| PX4 on the R5 (NuttX fork, DDR layout, chip layer, board, HITL over RPMsg MAVLink) | `PX4/Documentation/PX4_impl_steps.md` | `PX4/Documentation/PX4_impl_results.md` |

The HITL loop of `PX4_impl_steps.md` step 8 (Gazebo Classic in `Simulation/gazebo-classic`, socat bridges, QGroundControl) flies; this plan instruments and measures it.

---

## Channel map

One pin per tap point.

| Pin | Core | Tap | Mode |
|---|---|---|---|
| A0 | APU | T1: `HIL_SENSOR` received from UDP | toggle |
| A1 | APU | T2: `HIL_SENSOR` written to RPMsg (E1: echo sent) | toggle |
| A2 | APU | T7: `HIL_ACTUATOR_CONTROLS` read from RPMsg (E1: echo received) | toggle |
| A3 | APU | T8: `HIL_ACTUATOR_CONTROLS` sent over UDP | toggle |
| A4 | APU | Run marker | level |
| R0 | R5 | T3: `HIL_SENSOR` parsed (E1: echo received) | toggle |
| R1 | R5 | T4: rate controller | high while running |
| R2 | R5 | T5: `actuator_motors` published | toggle |
| R3 | R5 | T6: `HIL_ACTUATOR_CONTROLS` sent (E1: echo sent) | toggle |
| R4 | R5 | Run marker | level |

"Toggle" means every edge is one event, so each tap costs a single store. R1 is high while the controller runs, so its rising edges give the loop period and its pulse width gives the execution time.

---

## M1: PL edge-timestamp block

1. Free-running 48-bit counter on `pl_clk0` (100 MHz = 10 ns resolution, about 32 days before it wraps).
2. Per pin: 2-FF synchronizer, then an edge detector.
3. On each edge, push a 64-bit record {timestamp, channel, edge direction} into a FIFO. If several edges arrive in the same cycle, queue them in a fixed order.
4. AXI-Lite drain interface: a status register (fill level and a sticky overflow counter) and two 32-bit data registers, where reading the second one pops the record.
5. Mirror A0, A3, R0 and R3 to PMOD pins for scope cross-checks.
6. Behavioral simulation: simultaneous edges, FIFO full/overflow, drain while capturing.
7. Vivado block design: one AXI GPIO per core, the APU's on HPM0_FPD and the R5's on HPM0_LPD. The GPIO outputs feed the capture block; its drain port goes to the APU side.

## M2: APU integration

1. Device tree overlay loaded through fpga-manager or `xmutil`. Expose the APU's AXI GPIO and the capture drain through UIO.
2. Small C tap library: `mmap`, one shadow register per pin, `toggle(pin)` = flip the shadow bit, write it, then DSB.
3. Drain daemon: low priority, pinned to a core the bridge doesn't use. Writes binary records to a file and reports overflows.

## M3: R5 integration

1. MPU region for the R5's AXI GPIO as device memory, uncached.
2. Boot-order guard: never touch the PL before the bitstream is loaded. Use a ready flag from the APU over RPMsg, or a known magic value read from the PL.
3. `TAP_TOGGLE(pin)` and `TAP_SET`/`TAP_CLR` macros. Several PX4 tasks share one AXI GPIO register, so wrap the shadow update and write in a short critical section, followed by DSB.
4. Compile-time switch to remove all taps, so you can show the instrumentation doesn't affect the loop.

## M4: PX4 tap points

1. R0 in the mavlink receiver, for `HIL_SENSOR` only.
2. R1 around the rate controller's `Run()`.
3. R2 at the `actuator_motors` publication.
4. R3 when `HIL_ACTUATOR_CONTROLS` is sent.
5. Set the `HIL_ACTUATOR_CONTROLS` stream rate at or above the sensor rate. If it's lower, commands and sensor samples aren't 1:1, and latency has to be defined as the age of the newest sensor sample when each command goes out.

## M5: APU bridge (C)

1. Single-threaded `epoll` loop over the UDP socket and the RPMsg tty. With one thread there are no races on the APU's GPIO, and latency behaves more predictably.
2. Parse MAVLink frames, and tap only on `HIL_SENSOR` and `HIL_ACTUATOR_CONTROLS`.
3. Identity log: (message ID, MAVLink sequence number, order index) for each tapped message, buffered in RAM and written out after the run.
4. Options: `SCHED_FIFO` priority and CPU pinning, on or off.

## M6: RPMsg echo app (for E1)

1. Standalone NuttX app on the R5, buildable with PX4 running or not, with R0 and R3 taps.
2. APU-side generator that sweeps message size and rate, with A1 and A2 taps.

## M7: Flight data logging

1. ULog streamed over MAVLink with a minimal topic set (position and attitude setpoints and estimates, actuator outputs, `cpuload`).
2. Only enabled for E5. Run E1–E4 with it off so it doesn't load the link you're measuring.

## M8: Scripted flight

1. pymavlink or MAVSDK script for takeoff → hover (fixed duration) → land, plus the fixed mission for E5. Runs the same way every time, without QGC.

## M9: APU load profiles

1. `stress-ng` configurations for CPU, I/O and memory bandwidth (`--vm`, `--stream`).
2. Document where PX4's code and data live (TCM vs DDR), since that determines whether memory load can reach the R5.

## M10: Run automation

1. One script per experiment: start the drain daemon, raise the run markers, warm up, run, lower the markers, stop, collect the files.
2. Run folder with a manifest: git hashes, bitstream, image, container and Gazebo versions, load profile, bridge options, PX4 parameters.
3. Randomized run order. Back up to the host after each session.

## M11: Analysis pipeline

1. Decode PL records, split into runs using the run-marker pins, and match times to messages by sequence position.
2. Automatic checks on every run: edge counts consistent across the T1…T8 chain, zero FIFO overflows, no gaps in MAVLink sequence numbers.
3. One command regenerates all figures and tables: CDFs, box plots, latency budget bars, period histograms, tracking time series.

## M12: Freeze

1. Dry run of every experiment once, end to end.
2. Tag PX4, NuttX, bridge, PL design and analysis scripts. Archive the bitstream, Linux image, R5 firmware and container.
