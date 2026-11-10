# PL Timestamping System: Implementation Plan

*Written Tuesday, Nov 10, 2026. Target: working on hardware by Wednesday noon, before the bench freeze on Thursday, Nov 12.*

## Introduction

The HIL bench runs PX4 on NuttX on the Kria KV260's Cortex-R5. It is fed by Gazebo Classic on the host PC through a Linux bridge on the APU (UDP ⇄ RPMsg). The full loop already works: PX4 holds a hover in Gazebo and is controllable from QGroundControl.

The ISIE paper (due Dec 15) rests on three stress tests:

- **RPMsg link saturation**
- **APU interference** under stress-ng load
- **Closed-loop delay margin**

All three need accurate timing of messages as they cross between the APU and the R5. Software timestamps would need the two cores to share a clock, and they would add software jitter. So the chosen method is **GPIO-edge timing**: the R5 and the APU toggle GPIOs in the PL at key points in the message path, and a PL block timestamps every edge against a single free-running counter. Both cores are then measured on one timebase at 10 ns resolution.

This document describes the architecture of that block and then gives step-by-step instructions to get it running end to end.

**Fallback:** if the block isn't producing correct timestamps by **Wednesday noon**, switch to software timestamps. Both cores read the shared system timestamp counter (IOU_SCNTRS) and log the values. This is less precise but enough to run the experiments, and the GPIO version can still be finished for the paper after the freeze.

---

## Architecture

### Overview
The design has four PL components:

- **AXI GPIO "APU":** written by the APU.
- **AXI GPIO "R5":** written by the R5.
- **ts_capture:** a custom RTL block.
- **AXI4-Stream FIFO (axi_fifo_mm_s):** buffers the timestamped events for the APU to read.

Each core sets its own GPIO. Channel 1 of each GPIO is a 4-bit output, and those 8 bits together are the inputs of `ts_capture`. `ts_capture` watches them for edges and timestamps every edge with its free-running counter. It sends each timestamped event as an AXI-Stream packet into the AXI4-Stream FIFO. A reader process on Linux drains that FIFO and writes the events to a log file.

### Clocking
Everything runs on **pl_clk0 at 100 MHz**: both HPM ports, both AXI GPIOs, the capture logic and the FIFO. Because there is one clock domain, there are no clock-domain crossings.

### Data paths
- The APU reaches its GPIO and the FIFO through **HPM0_FPD**.
- The R5 reaches its GPIO through **HPM0_LPD**, so its accesses stay on the LPD side and never cross the FPD interconnect.
- **Counter readback:** channel 2 of each AXI GPIO is a 32-bit input tied to `counter[31:0]`. Either core can read the PL timebase directly. This is used for the write-latency bound and for aligning R5 `hrt` time with PL time.

### Capture logic
- **Counter:** 44 bits at 100 MHz, which gives 10 ns resolution and wraps after about 49 hours.
- **Edge detect:** the 8 GPIO bits (4 per core) are registered and XORed with their previous value. Any nonzero result is one event.
- **Same-cycle edges** on several bits produce a single event with a multi-bit change mask, so there is no arbitration and nothing is lost.
- **Event buffer:** a 16-deep FIFO of 64-bit events absorbs events in consecutive cycles while the serializer emits 2 beats per event.
- **Overflow:** if the event FIFO is full when an event arrives, a sticky flag is set. The next event that is written carries the flag, and the flag then clears.

### Event format
Each event is 2 words, with TLAST on word 1, so each event is one 8-byte packet in the FIFO.

| Word | Bits |
|---|---|
| 0 | `ts[31:0]` |
| 1 | `ovf[31]`, reserved `[30:28]`, `mask[27:20]`, `level[19:12]`, `ts[43:32]` in `[11:0]` |

### Channel map

| Ch | Core | Instrumentation point |
|---|---|---|
| 0 | APU | HIL_SENSOR written into RPMsg |
| 1 | APU | Actuator message read from RPMsg |
| 2–3 | APU | Spare (e.g. flood generator markers) |
| 4 | R5 | `handle_message_hil_sensor` entry |
| 5 | R5 | HIL_ACTUATOR_CONTROLS sent by the mavlink stream |
| 6 | R5 | Rate-controller iteration (loop rate and jitter) |
| 7 | R5 | Sync marker, also logged with its `hrt` value in ULog |

### Derived measurements
- **APU → R5:** ch0 → ch4
- **PX4 processing:** ch4 → ch5
- **R5 → APU:** ch5 → ch1

The delay injector sits upstream of the ch0 toggle, so the measured hops exclude the injected delay. Under saturation, ordering alone can't match events once messages drop, so the MAVLink sequence number is also logged in software at ch0 and ch4.

---

## Implementation steps

### Phase 1: Capture RTL

1. Create `ts_capture.v` with these ports:
   - `clk`, `rstn`
   - `gpio_apu[3:0]`, `gpio_r5[3:0]`
   - `cnt_lo[31:0]` (output)
   - `m_axis_tdata[31:0]`, `m_axis_tvalid`, `m_axis_tready`, `m_axis_tlast`
2. Add a 44-bit free-running counter. Make its reset value a parameter so the wrap case can be tested.
3. Register `{gpio_r5, gpio_apu}` and XOR with the previous value to get `mask`. An event occurs when `mask != 0`.
4. On an event, push `{ovf, 3'b0, mask, level, ts}` (64 bits) into an `xpm_fifo_sync` of depth 16.
5. If that FIFO is full when an event arrives, set the sticky `ovf` flag. Clear it once an event carrying the flag has been pushed.
6. Write a 2-state serializer: word 0 = `ts[31:0]`, then word 1 = the upper bits with `tlast = 1`.
7. Write a testbench covering:
   - a single edge
   - same-cycle edges on several bits
   - edges in back-to-back cycles
   - `tready` held low until the FIFO fills, checking that `ovf` appears on the next event
   - counter wrap
8. Run the testbench until all cases pass.

### Phase 2: Vivado block design

1. Create the project with the KV260 board files. Add the Zynq UltraScale+ MPSoC and apply the board preset.
2. Enable **M_AXI_HPM0_FPD** and **M_AXI_HPM0_LPD**. Set pl_clk0 to 100 MHz and keep pl_resetn0.
3. Clock both HPM `aclk` pins from pl_clk0. Add a Processor System Reset driven by pl_clk0 and pl_resetn0.
4. Add **AXI GPIO "APU"**:
   - channel 1: 4 bits, all outputs
   - dual channel enabled
   - channel 2: 32 bits, all inputs
5. Add **AXI GPIO "R5"** with the same configuration.
6. Add **AXI4-Stream FIFO** (axi_fifo_mm_s):
   - AXI4-Lite data interface
   - transmit disabled, receive enabled
   - receive depth 1024
7. Add `ts_capture` as a module reference and connect it:
   - both GPIO channel-1 outputs → `gpio_apu` / `gpio_r5`
   - `cnt_lo` → both GPIO channel-2 inputs
   - `m_axis` → the FIFO's AXI-Stream input
8. Connect HPM0_FPD → SmartConnect → GPIO "APU" and the FIFO. Connect HPM0_LPD → SmartConnect → GPIO "R5".
9. Assign addresses and write them down. Expect the FPD peripherals in the 0xA000_0000 range and the R5 GPIO in the 0x8000_0000 range.
10. Validate the design, generate the bitstream and export the XSA.
11. Convert the bitstream to `.bin` with bootgen (`-arch zynqmp -process_bitstream bin`).

### Phase 3: Linux overlay and loading

1. Generate the overlay from the XSA, for example with XSCT `createdts ... -overlay`.
2. Edit the generated `pl.dtsi`:
   - Set `compatible = "generic-uio"` on the APU GPIO and FIFO nodes.
   - **Delete the R5 GPIO node**, because Linux must not touch it.
   - Keep the `clocking0` node (`xlnx,fclk`) so pl_clk0 stays enabled.
3. Compile it to `pl.dtbo`.
4. Create `/lib/firmware/xilinx/ts_bench/` containing the `.bin`, `pl.dtbo` and a `shell.json` with `{"shell_type":"XRT_FLAT","num_slots":"1"}`.
5. Load the design with `sudo xmutil unloadapp` followed by `sudo xmutil loadapp ts_bench`.
6. Check that `/sys/class/uio/` shows the two devices. If it doesn't, load `uio_pdrv_genirq` with `of_id=generic-uio` (as a module parameter or boot argument).
7. **Load order:** always load the bitstream *before* starting the R5 with remoteproc, and never reload it while the R5 is running. An R5 access to an unloaded or isolated PL hangs the bus.

### Phase 4: APU software and PL-side validation

1. Write a small C helper (`tp_apu.c`):
   - `mmap` the APU GPIO through its UIO device.
   - `tp_toggle(ch)`: update a shadow register and write GPIO_DATA (0x0). Protect the shadow with a mutex if more than one thread toggles.
   - `tp_counter()`: read GPIO2_DATA (0x8).
2. Write the reader (`ts_reader.c`):
   - `mmap` the FIFO.
   - At startup, reset the receive FIFO (write 0xA5 to RDFR) and clear ISR.
   - Loop: read RDFO; while it is nonzero, read RLR (expect 8 bytes), then read RDFD twice; append a binary record to the log file.
   - Poll at 100 Hz or faster.
   - Check the register offsets against PG080.
3. **Test: toggle loop.** Toggle ch0 N times at a known period. Check that exactly N events arrive, that the deltas match the period, and that `ovf` never appears.
4. **Test: clock frequency.** Compare the counter against `CLOCK_MONOTONIC` over 60 s and record the real pl_clk0 frequency for the paper. It is often not exactly 100.000 MHz.
5. **Test: write-latency bound.** Read `tp_counter()`, toggle, then compare the event timestamp with the value read. The difference is an upper bound on the APU's write latency.

### Phase 5: R5 side

1. In the board's MPU init, add a region over the R5 GPIO address range as **Device / strongly-ordered, non-cacheable**. Without this, the write buffer delays toggles unpredictably.
2. Add `tp_toggle(ch)` to the board's source, with a shadow register updated inside `enter_critical_section()`. Several PX4 tasks share one data register, so a plain read-modify-write would race. Declare it in a board header.
3. Add an NSH test command that toggles ch4–7 in a loop. Verify the events with `ts_reader`.
4. Repeat the write-latency bound test from the R5, reading GPIO2_DATA.
5. Add the PX4 instrumentation points:
   - ch4 at the entry of `MavlinkReceiver::handle_message_hil_sensor`
   - ch5 in the HIL_ACTUATOR_CONTROLS stream's `send()`
   - ch6 in the rate controller's `Run()`
   - ch7 once at the start of each run, logging `hrt_absolute_time()` to ULog at the same moment

### Phase 6: Bridge instrumentation

1. Add the toggles at the RPMsg boundary of the bridge:
   - ch0 when a HIL_SENSOR frame is written to the RPMsg tty
   - ch1 when an actuator frame is read from it
2. If the bridge is socat or stock mavlink-router, replace it with a small C bridge (RPMsg tty ⇄ UDP) containing a minimal MAVLink v2 parser for frame boundaries and message IDs. The same bridge will host the delay injector and the flood generator.
3. Log the MAVLink sequence number next to each ch0 toggle.

### Phase 7: End-to-end check

1. Load the bitstream, start the R5, start the bridge and `ts_reader`, then fly the hover.
2. Check that:
   - the counts on channels 0, 1, 4 and 5 are consistent with the HIL message rates
   - the hop deltas (ch0→4, ch4→5, ch5→1) are plausible and stable
   - no event carries `ovf`
   - the ch7 marker aligns the PL timeline with ULog
3. Write a short script that turns the binary log into per-hop latency CSVs. Every experiment will reuse it.
4. Record the bitstream, overlay and firmware versions for the freeze.

---

## Schedule

| When | Work |
|---|---|
| Tue 9:00–10:30 | Phase 2, steps 1–6 (block design without the RTL) |
| Tue 10:30–12:00 | Phase 1 (RTL and testbench) |
| Tue 12:00–13:00 | Phase 2, steps 7–11; start the build and write the overlay while it runs |
| Tue 13:00–15:00 | Phase 3 and Phase 4, steps 1–2 |
| Tue 15:00–17:00 | Phase 4 tests |
| Wed morning | Phases 5 and 6 |
| **Wed noon** | **Decision point:** keep the GPIO route, or switch to the IOU_SCNTRS fallback |
| Wed afternoon | Phase 7, scripted flight, experiment hooks |
| Thu | Dry run of each experiment, then freeze |
