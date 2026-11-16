# PL Timestamping Block: Notes

## Phase 2: Vivado block design

- pl_clk0 achieved frequency: 99.999001 MHz (requested 100 MHz).
- Address map:

| Slave | Port | Base |
|---|---|---|
| `ts_fifo` | HPM0_FPD | `0xA000_0000` |
| `gpio_apu` | HPM0_FPD | `0xA001_0000` |
| `vcu_0` | HPM0_FPD | `0xA010_0000` |
| `gpio_r5` | HPM0_LPD | `0x8000_0000` |

- Fan PWM: TTC0 through EMIO. The R5 uses TTC2 for its tick and timebase, so there is no conflict.
- Timing after implementation: WNS 1.122 ns, WHS 0.012 ns.

## Phase 3: Linux overlay and loading

- Packaged as the PetaLinux firmware app `ts-bench` (`dfx_user_dts`), installed in `/lib/firmware/xilinx/ts-bench/`.
- `xmutil loadapp` failed with "DMA buffer alloc failed": the R5 carve-outs at `0x3C00_0000`–`0x3E10_0000` left no contiguous 900 MiB for `cma=900M`. Bootargs changed to `cma=512M`.
- After `xmutil unloadapp` (to remove the auto-loaded k26-starter-kits) and `xmutil loadapp ts-bench`, `GPIO2_DATA` at `0xA001_0008` reads the running counter: two reads 27.6 ms apart differ by 2,758,060 ticks.
- `uio_pdrv_genirq` only binds `generic-uio` nodes when it is given `of_id=generic-uio`. With that set, the FIFO shows up as `uio4` (`0xA000_0000`) and `gpio_apu` as `uio5` (`0xA001_0000`). The parameter is now a bootarg, and ts-bench is made the default dfx-mgr app.
- Manual capture test with `devmem` (writing `gpio_apu`, reading the FIFO over AXI4-Lite): every edge gave one 8-byte packet with the expected `ch_change`/`ch_level`, `ovf = 0`. Between two events, `ts[43:32]` went from `0x01F` to `0x020`, so the carry across the 32-bit boundary works.
- After the rebuild, boot alone is enough: ts-bench is the default dfx-mgr app, the bootarg is on the cmdline, `uio4`/`uio5` appear and the counter runs. Phase 3 is complete.

## Phase 4: APU software and PL-side validation

- Software: `sw/apu/` (`ts_apu`, `ts_reader`, `ts_test`) and `sw/tools/ts_decode.py`.
- The first toggle test (1000 toggles at 1000 µs) gave all 1000 edges with `ovf = 0`, but a mean period of 937.5 µs. The overlay asked for 99,999,001 Hz, and Linux rounded down to IOPLL 1500 MHz / 16 = 93.75 MHz. The overlay now asks for 100,000,000 Hz (1500 MHz / 15).
- Clock (60 s, after the fix): 99,999,060.5 Hz against `CLOCK_MONOTONIC` (−9.4 ppm), 99,999,000.3 Hz against `CLOCK_MONOTONIC_RAW`, ±0.02 ppm. The RAW value matches the 99,999,001 Hz the boot design gives the system counter, so the PL clock and the system counter likely share one reference.
- Write-latency bound, APU, ch0, 10,000 samples (counter read → edge):

| Run | min | median | p99 | max |
|---|---|---|---|---|
| normal | 410 ns | 450 ns | 500 ns | 3.78 µs |
| `SCHED_FIFO 80`, core 2 | 410 ns | 450 ns | 480 ns | 1.32 µs |

- Toggle test at 100 MHz: the first run gave 1001 edges, because `ts_open()` drove ch0 low while a previous run had left it high. `ts_open()` now keeps the current levels. The rerun gave 1000 edges, `ovf = 0`, PASS. Phase 4 is complete.
