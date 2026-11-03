# KV260 RPU — PX4 Implementation Results

Findings and recorded values behind `PX4_impl_steps.md` (same step numbers). Starting point: the NuttX port on `NuttX/nuttx` branch `kv260-rpu` (commits `05db9de0b8`, `2e12be19a5`), which passes `NuttX/Documentation/board_bringup_steps.md` through step 8.

Sources:
- upstream PX4 `PX4/PX4-Autopilot`, `upstream/main` `bfd0984db6` (2026-10-26)
- its NuttX fork at `platforms/nuttx/NuttX/nuttx`, branch `px4_firmware_nuttx-12.12.0+`, commit `036f5946f8` (`nuttx-12.12.0-80`); apps `4319b404bc`

Items marked **verify** aren't confirmed yet.

| Step | Result | Date | Commit |
|---|---|---|---|
| 0 Trees, baselines | done: PX4 fast-forwarded, fork and apps on new `kv260-rpu` branches, `raspberrypi_pico_default` links | 2026-10-26 | |
| 1 Port chip and board | trial in a scratch copy of the fork: all 5 configs build, QEMU `sleep 10` 10.01 s, ostest passes | 2026-10-23 | |
| 2 Board: ostest, `up_udelay`, RPMsg | done: ostest passes; `up_udelay` timed on TTC2 counter 1 (replaces the loop calibration); RPMsg echo stress test passes | 2026-10-27 | fork `622ec678a7` |
| 3 Board: `uart_rpmsg_raw` console | done: NSH on `/dev/ttyRPMSG0` (picocom), help/free/ps/ostest pass, stop/restart works | 2026-10-27 | fork `622ec678a7` |
| 4 DDR layout | done: image runs from `rproc0` DDR (vectors and resource table in TCM), heap 32 MiB; ostest passes in QEMU and on the board; RPMsg echo stress test and stop/restart pass with caches on | 2026-10-27 | fork `cc859db296` |
| 5 PX4 chip layer | 5.0: TTC match mode set; `qemu-ddr` ostest passes, board check pending. 5.1: Platform file written. 5.2: chip mapping, ARMv7-R head object linked. 5.3: chip layer files. 5.4: hrt.c written, compiled in step 6 | 2026-10-30 | fork uncommitted |
| 6 PX4 board | 6.1: board files written, defconfig normalized (`olddefconfig`); fork Kconfig selects `ARCH_HAVE_RESET`. 6.2: builds and links: ddr 1.59 MB (4.7%), tcm 272 B, heap 30.5 MiB; LOAD at 0x0 and 0x3c000000; `.resource_table` in TCM; `_vector_start` at 0x0; v7-R, VFPv3-D16, VFP args. Fixes: `-Wno-cast-align` on `arch_hrt` (as other HRTs); PX4 builds and links NuttX `libopenamp.a` when `CONFIG_OPENAMP` (`nuttx_drivers` depends on it). Fix after 7.1: late init's `AppBringUp` thread took PID 3, so `cpuload_initialize_once()` (assumes PIDs 0-3) tracked a NULL tcb: `load_mon` "low on stack! (0 bytes left)" with no name, `top` stopped after 3 rows. Late init stays, because rptun must start before NSH opens the console; fixed instead in `cpuload.cpp`: `cpuload_initialize_once()` tracks the existing threads with `nxsched_foreach()`, whatever their PIDs. After many remoteproc stop/start cycles, no image brought up `/dev/ttyRPMSG0` (no "creating channel rpmsg-tty"), not even the fork's `kv260-rpu:ddr`; rebooting Linux fixed it, so reboot the board when the channel doesn't appear. A NuttX config change needs the NuttX `*.o`/`lib*.a` deleted in the fork and apps trees and in `build/.../NuttX`: NuttX doesn't rebuild on `config.h` changes | 2026-11-02 | fork uncommitted |
| 7 PX4 boot | done. 7.1: after a fresh Linux boot, the PX4 image boots: UART1 shows the `[boot]` lines (rptun started, app init, /tmp mounted, px4 init done), NSH on `/dev/ttyRPMSG0` with the rcS output. With the cpuload fix: no `load_mon` warning, `top` lists all 15 tasks (PID 3 `AppBringUp` has exited), 98% idle. 7.2: `ver all`, `dmesg`, `free` as expected; `uorb top`: 71 topics, `sensors_status_imu` 100 Hz (sensors' fallback timer), the rest about 2 Hz, no sensor topics; `work_queue status`: all queues present, `vehicle_acceleration`, `rc_update` and `parameters` at 0 Hz (triggered by topics nothing publishes yet). 7.3: `hrt_test` and `tests hrt` pass; uptime matches Linux `/proc/uptime` over 2+ min (no measurable drift). 7.4: `reboot` halts (`board_reset()`); after stop/start `/dev/ttyRPMSG0` is back and `MAV_SYS_ID` is 1 (tmpfs); 6 more stop/start cycles all reconnect, so the earlier bad state's trigger is unknown. Step 7 done | 2026-11-02 | fork uncommitted |
| 8 HITL over MAVLink | 8.1: second RPMsg tty: Linux has `/dev/ttyRPMSG0` (NSH) and `/dev/ttyRPMSG1`; NSH `echo hello > /dev/ttyRPMSG1` arrives on Linux `cat /dev/ttyRPMSG1`. 8.2: `SYS_AUTOSTART` 1001, `SYS_HITL` 1, `SYS_DM_BACKEND` 1; MAVLink frames flow on `/dev/ttyRPMSG1` once Linux sends a byte. Fixed `uart_rpmsg_raw`: TX never restarted when the first Linux message bound the endpoint, so a console buffer filled by rcS hung NSH and MAVLink sent nothing; it now sends the backlog on that message and drains it across payloads. 8.3: image builds (ddr 1,587,928 B, 4.73 %), passes the 6.2 checks; ROMFS has `rc.board_mavlink` and airframe 1001. 8.4: self-contained Gazebo Classic 11.10.2 image (`Simulation/gazebo-classic`); HITL plugins built, serial output checked through a PTY; GUI shows the iris on WSL (software rendering) and on native Ubuntu (GPU). 8.5: socat bridge carries MAVLink continuously from `/dev/ttyRPMSG1` to the container PTY. 8.6: Gazebo HITL connected, HIL data both ways without loss, attitude converged, `Preflight check: OK`. 8.7: flies from QGroundControl: takeoff, position hold and landing work, hover very stable. 8.8: during hover 61 % idle, control chain at about 250 Hz, control latency 0.77 ms avg, no late or overrun counters, MAVLink ping 2.16 ms mean (`HITL_test_bench_results.md`) | 2026-11-03 | PX4 and fork uncommitted |

---

## Background: why the 12.12 fork

- PX4 builds only against its own NuttX fork. PX4 `main` moved from `px4_firmware_nuttx-10.3.0+` to `px4_firmware_nuttx-12.12.0+` on 2026-09-03 (`bbcd20abe3`, "feat(git): upgrade NuttX to 12.12.0").
- Steps 0–1 were first done on the 10.3 fork (appendix). That checkout was 3157 commits behind PX4 `main`. The 12.12 branch doesn't contain the 10.3 branch (13707 commits ahead, 168 behind), so the 10.3 commits can't be rebased; the port is redone from the port tree.
- The port tree is upstream master after `nuttx-12.13.0`, so the 12.12 fork is about one release behind it (the 10.3 fork was about 17,000 commits behind).
- The fork supports Make and CMake. PX4 builds NuttX with Make (`platforms/nuttx/NuttX/CMakeLists.txt`: `Make.defs.in`, `make pass1dep`), so Make is what is tested.
- OpenAMP and libmetal are pinned commits (`openamp/Makefile`: `OPENAMP_COMMIT c468328487`, `LIBMETAL_COMMIT a4bce35075`), downloaded on the first RPMsg build.
- The fork has no ZynqMP chip. PX4 `main` still has no Cortex-R support: no Platform file, no chip mapping, no chip layer.

---

## Step 0: Trees and baselines (2026-10-26)

- PX4 `kv260-rpu` fast-forwarded from `446895fdc0` to `origin/main` `bfd0984db6`, no conflicts (the branch had no PX4 commits). `git submodule update --init --recursive` ran without errors.
- Fork `nuttx`: the old `kv260-rpu` renamed `kv260-rpu-10.3` (head `22a68db6e6`); new `kv260-rpu` at `036f5946f8`. `036f5946f8` is the merged version of `8626377ce3` (the commit the step 1 trial used): same tree.
- Fork `apps`: the old `kv260-rpu` renamed `kv260-rpu-10.3` (no own commits); new `kv260-rpu` at `4319b404bc`.
- `Tools/simulation/jmavsim/jMAVSim` is left over from the removed jMAVSim submodule (`a23449cbe5`) and shows as untracked.
- `build/` directories created when the repo was at `~/PX4-Autopilot` don't regenerate (`CMakeCache.txt` points to the old path); delete them before building. `build/raspberrypi_pico_default` was deleted; `build/px4_sitl_default` still has the old path.
- **PX4 baseline:** `make raspberrypi_pico_default` links with arm-none-eabi-gcc 13.2.1: `flash: 1185800 B (56.54 % of 2 MB)`, `sram: 21332 B (7.89 % of 264 KB)` (10.3: 1120288 B and 17400 B).
- PX4 configures and builds NuttX inside the fork's source tree, so after a PX4 build `configure.sh` stops with "Already configured!". Plain `make distclean` then fails with `rm: invalid option -- 'T'`: PX4 boards set `ARCHSCRIPT = -T<path>` (a linker flag) and the clean rule deletes `$(ARCHSCRIPT).tmp`. `make distclean ARCHSCRIPT=` works (it only skips that one `.tmp` file). After it, the PX4 build directory reconfigures NuttX on its next build.

## Step 1: Differences (12.12 fork vs port tree)

From a trial (2026-10-23) on `8626377ce3` (same tree as `036f5946f8`): the fork commit and its apps extracted to a scratch directory, the port's chip and board copied in unchanged, then built until every config links.

**Already in 12.12 (no change):**

- `armv7-r`: the `addrenv.h` fix, the `mpcore.h` `#ifndef` guards, `SCTLR_M` in `__start`, idle stack alignment.
- `mpu_initialize()` and `struct mpu_region_s`: the port's `zynqmp_rpu_boot.c` is used unchanged.
- `g_current_regs`, `sched_getcpu()`, spinlocks, `up_putc`: `zynqmp_rpu_irq.c` and `zynqmp_rpu_lowputc.c` compile unchanged.
- `include/nuttx/rpmsg/` and `drivers/rpmsg/`: `zynqmp_rpu_rpmsg_echo.c` compiles unchanged.
- The Bring-Up Options menu depends only on `DEBUG_FEATURES`: `SUPPRESS_UART_CONFIG` is kept without `EXPERIMENTAL`. Every option of the 5 port defconfigs is kept by `configure.sh`.
- Linker scripts go through the C preprocessor: the `//` comment in `tcm-lockstep.ld` is fine.
- The rest of the `armv7-r` differences are the SMP start-up code (`CONFIG_SMP_NCPUS`, `__cpuN_start`), unused on one core.

**Needed:**

| Item | Fix |
|---|---|
| `ARMV7R_LOCKSTEP_REGINIT`, `ARMV7R_ZERO_UNUSED_RAM` missing | port `0f4cc1ac76`: `arm_fpuconfig.S`, `Kconfig` and the RAM-zeroing hunk apply; the `__start` block doesn't (the SMP block next to it differs) and goes in by hand at the top of `__start` |
| `undefined reference to mpu_initialize`: `armv7-r/Make.defs` and `CMakeLists.txt` build `arm_mpu.c` only with `BUILD_PROTECTED` | cherry-pick upstream `afdc7675c8` (both files) |
| `nuttx/debug.h: No such file` (`zynqmp_rpu_irq.c`, `zynqmp_rpu_serial.c`) | `<debug.h>` |
| `get_resource`: incompatible pointer type | returns `struct rptun_rsc_s *` |
| `struct rptun_rsc_s` differs: the port tree has `offset[3]` and a trailing `carveout` (removed upstream in `7ba6425933`), the fork `offset[2]` and no `carveout` | none: the table sets `num = 1`, fills only `offset[0]` (the vdev) and never names `carveout`; only the size changes (`0xd0`). Linux finds the vdev (step 2.3, 2026-10-27) |
| `implicit declaration of UP_DSB` | `#include <arch/barriers.h>` (12.12 defines `UP_DSB()` in `arch/arm/include/armv7-r/barriers.h`) |
| `undefined reference to board_app_initialize` (`boards/boardctl.c:368`) | `src/zynqmp_rpu_appinit.c`, as on 10.3 |
| `BOARD_LATE_INITIALIZE` defaults to `n`: bring-up never runs, so rptun and the resource table aren't linked (`.resource_table` came out `NOBITS`, 4 bytes) | `CONFIG_BOARD_LATE_INITIALIZE=y` in every defconfig |
| `uart_rpmsg_raw` missing (it's upstream, in 12.13) | cherry-pick `65207ae1c5` (10 files, applies cleanly), then `0a6a2e5e04` for its `uart_rpmsg_raw.c` hunk (removes the `RPMSG_UART_RAW_CONSOLE` guard around the console registration; the port tree and 12.13 have it). Its `uart_rpmsg.c` hunk doesn't apply: the fork never had that guard |

**Trial builds** (arm-none-eabi-gcc 13.2.1):

| Config | text / data / bss | Notes |
|---|---|---|
| `qemu` | 195336 / 872 / 8344 | one LOAD `0x0`–`0x31f08`. QEMU: prompt after 0.6 s, `sleep 10` 10.01 s, ostest exits with status 0 |
| `shared` (with RPMsg) | 146940 / 976 / 7888 | `.resource_table` `PROGBITS`, `0xd0` bytes at `0x23d28`; rptun and echo linked; one LOAD |
| `rpmsg` | 150288 / 1000 / 5336 | `uart_rpmsg_raw_init`, `rpmsg_serialrawinit` linked; one LOAD |

- The image is about 22 % larger than on 10.3 (`qemu`: 195 KiB vs 159 KiB). All configs still fit the 256 KiB TCM.
- Remaining warnings, same as the port: `zynqmp_rpu_error_handler` and `g_console_config` (with `SUPPRESS_UART_CONFIG`) defined but not used.
- QEMU can be driven from a script if it answers NSH's `ESC[6n` with `ESC[1;1R`.

**Fork commits (2026-10-26)**, `kv260-rpu` on `036f5946f8`: A `1254f9640f` (upstream `afdc7675c8`), B `9ae5033e82` (port `0f4cc1ac76`), C `be4f9d14fc` (upstream `65207ae1c5`), D `5469db3337` (upstream `0a6a2e5e04`, raw hunk only), E `974a27ab24` (chip), F `489d8f515d` (board).

**1.5 builds** (arm-none-eabi-gcc 13.2.1, `make -j20`): every option of each defconfig is kept in `.config`; one LOAD segment each, inside the TCM.

| Config | text / data / bss | LOAD | `.resource_table` | Linked |
|---|---|---|---|---|
| `nsh` | 195436 / 884 / 8348 | `0x0`–`0x31f88` | `NOBITS`, 4 B | `board_app_initialize`, `board_late_initialize` |
| `calib` | 48324 / 660 / 5196 | `0x0`–`0xd3a8` | `NOBITS`, 4 B | `board_late_initialize` (no `BOARDCTL`) |
| `shared` | 146940 / 988 / 7888 | `0x0`–`0x260b0` | `PROGBITS`, `0xd0` at `0x23d28` | `board_late_initialize`, `rptun_initialize`, `g_zynqmp_rpu_rsc_table` (no `BOARDCTL`) |
| `rpmsg` | 150300 / 1012 / 5336 | `0x0`–`0x263f8` | `PROGBITS`, `0xd0` at `0x24a48` | `board_app_initialize`, rptun, `uart_rpmsg_raw_init`, `rpmsg_serialrawinit` |
| `qemu` | 195444 / 884 / 8348 | `0x0`–`0x31f88` | `NOBITS`, 4 B | `board_app_initialize`, `board_late_initialize` |

- Warnings: only `zynqmp_rpu_error_handler` and `g_console_config` (as in the trial). No new errors.
- Within a few bytes of the trial (`qemu` +108 B text, `shared`/`rpmsg` +12 B data).
- 1.1 check (`qemu` image): `__start` at `0x40` begins with `mov r0`–`r12, #0`, then `cpsid if` into FIQ (r8–r12, sp, lr zeroed), IRQ, ABT, UND, SYS (sp, lr zeroed each).
- **1.6 QEMU** (`kv260-rpu:qemu`, `run-qemu.sh`, run by hand from a terminal): `sleep 10` takes 10 s (host clock), `ostest` exits with status 0. Quit QEMU with Ctrl-A X.

## Step 2: Board checks

- **2.1** (2026-10-26): `shared` (146940 / 988 / 7888, one LOAD `0x0`–`0x260b0`, `.resource_table` `PROGBITS` `0xd0`) loaded through remoteproc; ostest on UART1 exits with status 0.
- Bring-up step 7.1 says `.resource_table` is `0x108`; on 12.12 it's `0xd0` (`struct rptun_rsc_s` lost `offset[2]` and `carveout`, step 1).
- **2.2 calibration** (2026-10-26): m = 34.537 ns per loop (R² = 1.0000, b = −2.5 ms from the 1 ms tick resolution) → 28954.31 loops per ms → recommended `CONFIG_BOARD_LOOPSPERMSEC=28955`. The port tree and the 10.3 fork gave 31750 (31.496 ns per loop).
  - Same `calib_udelay` source, same compiler (gcc 13.2.1), same flags: `calib_udelay_test` has identical instructions in both images. Only the address differs: inner loop head at `0x6844` (8-byte aligned + 4) on 12.12, `0x6c10` (8-byte aligned) in a port-tree build.
  - Likely cause: the R5 fetches 64 bits at a time, so a loop entered mid-doubleword costs about 1.5 cycles more per pass. Not confirmed on the board: the port-tree `calib` (loop aligned) wasn't run.
  - `up_udelay`'s loop is placed independently: `0x2954` (+4) in 12.12 `shared`, `0x2a68` (aligned) in the port tree's `rpmsg`. A value measured with `calib_udelay` can be wrong for `up_udelay` in the same image, and it changes whenever code moves (DDR, PX4).
  - `-falign-loops=8` doesn't help: GCC ignores loop and function alignment at `-Os` (image unchanged with the flag); `-O2` generates a different loop.
  - **Decision:** `up_udelay` / `up_ndelay` timed on TTC2 counter 1 (free-running, 100 MHz), no calibration. The PX4 HRT (step 5.3) shares that counter: one timebase, TTC3 stays free, no DT change for it.
- **2.2 timebase `up_udelay`** (2026-10-27), fork commits G `1eb390ceaa` (chip) and H `622ec678a7` (remove `calib`), pushed:
  - `zynqmp_rpu_timebase.c` / `.h`: Kconfig `ZYNQMP_RPU_TIMEBASE_TTC` (default 2) / `_COUNTER` (default 1); `#error` on TTC2 counter 0 (the tick); `zynqmp_rpu_timebase_init()` called from `arm_boot()` right after `zynqmp_rpu_lowsetup()`. The strong `up_udelay` / `up_ndelay` replace `delay.c`'s weak versions (linked because `arm_boot()` pulls in the same object); `udelay_coarse` is no longer linked, `shared` text −160 B. `configs/calib` removed.
  - Test (temporary `KV260_RPU_UDELAY_TEST` in `zynqmp_rpu_bringup()`, against `CLOCK_MONOTONIC`, 10 ms tick, starting on a tick edge):

    | Case | QEMU (133 MHz) | Board (100 MHz) |
    |---|---|---|
    | 1 × 1 000 000 µs | 1 000 000 µs | 1 000 000 µs |
    | 1000 × 1000 µs | 1 000 000 µs | 1 000 000 µs |
    | 1 000 000 × 1 µs | 1 540 000 µs | 1 520 000 µs |

  - Overhead on the board: about 0.52 µs per call (`up_udelay(1)` takes about 1.52 µs): the function call, the first register read, and finishing on the first poll after the deadline. Each TTC read crosses the LPD bus to a Device register. Delays are never shorter than asked; for PX4's 1–100 µs driver delays this is at most +52 %, at 10 µs +5 %.
  - The tick and the timebase count the same LPD clock, so this checks the code and the conversion, not the clock rate (confirmed in bring-up by ostest timing and `sleep 10`).
- The 12.12 OpenAMP (`c468328487`) is newer than 10.3's 2022.04. Its behaviour as a remote of the Linux 6.6 `zynqmp_r5_remoteproc` (vdev status wait, NS announce) is checked by bring-up step 7.
- **2.3** (2026-10-27): link up with the `0xd0` table and the 12.12 OpenAMP (`rpmsg-raw` channel created); echo stress test passes.

## Step 4: DDR layout

- DT (already in `system-user.dtsi`): `rproc0` at `0x3c000000`, 32 MiB, `no-map`, listed first in `r5f_0`'s `memory-region`. Its comment plans "PX4 code/data, R5 MPU: normal, cacheable".
- Remoteproc loads each LOAD segment into one carveout (bring-up results, step 5). So the vectors (TCM, the R5 boots at `0x0`) and the rest (DDR) must be separate segments, each inside one carveout.
- Reset entry from TCM to DDR: the vector table jumps through absolute addresses (`ldr pc, .Lresethandler` in the 12.12 fork's `arm_vectortab.S`, checked), so `__start` can be in DDR.
- The resource table stays in TCM (never cached), so Linux's vdev status writes need no cache maintenance.
- MPU: higher region numbers take priority where regions overlap, so the shared window must be programmed after the DDR region (**verify** in the Cortex-R5 TRM).

---

## Step 5: PX4 chip layer and toolchain

- CPU flags come only from `platforms/nuttx/cmake/Platform/Generic-<compiler>-<CONFIG_BOARD_ARCHITECTURE>.cmake`. These exist only for `cortex-m0plus`, `m3`, `m4`, `m7`, `rv64gc` and `esp32`.
  - They also apply to the NuttX build: `NuttX/Make.defs.in` uses `CMAKE_C_FLAGS`, not NuttX's `ARCHCPUFLAGS`.
  - CMake includes it `OPTIONAL` (`CMakeCInformation.cmake`), so a missing file silently means no `-mcpu`.
  - The planned flags give the same `readelf -A` attributes as the fork's `ddr` objects (v7-R, ARM and Thumb-2, VFPv3-D16, VFP register arguments).
- The fork's armv7-r `Toolchain.defs` uses `-mcpu=cortex-r5 -mfpu=vfpv3-d16 -mfloat-abi=hard` (`softfp` with `ARM_FPU_ABI_SOFT`; checked on 12.12). The R5F FPU is double precision.
- `px4_os_determine_build_chip()` (`px4_impl_os.cmake:137–186`) maps `CONFIG_ARCH_CHIP_*` to a manufacturer and chip, and stops with `FATAL_ERROR` when none matches.
- Required chip libraries: `arch_hrt`, `arch_board_reset`, `arch_board_critmon`, `arch_version`. The others (`io_pins`, `adc`, `tone_alarm`, `led_pwm`, `spi`) are built only if something links them.
- `micro_hal.h` must define `PX4_NUMBER_I2C_BUSES` 1–6 even with no I2C (`#error` at `board_common.h:76`).
- **HRT:**
  - Needs a free-running counter and one compare interrupt used as a one-shot deadline; the ISR calls `hrt_call_invoke()`, then `hrt_call_reschedule()`.
  - The other HRT implementations count in µs (1 MHz). The TTC prescaler divides only by powers of two, so 100 MHz can't make 1 MHz: the KV260 HRT converts counts / 100 in software.
  - The 32-bit TTC wraps after about 43 s at 100 MHz, so the reschedule interval stays far below that.
  - `nxp/s32k3xx/hrt/hrt.c` (32-bit counter extended in software, 521 lines) is the closest template.
- **TTC choice:** TTC0 is the fan (Linux). TTC2 counter 0 is the NuttX tick, TTC2 counter 1 the shared timebase for `up_udelay` and the HRT (step 2.2; TTC2 is disabled in the DT). TTC1 and TTC3 stay free.
- `up_systemreset()` isn't implemented for armv7-r (also on 12.12). On the KV260, reset is a remoteproc stop/start from Linux, so `board_reset()` can only stop the core (**verify** what PX4 expects on `reboot`).
- Keep Cortex-M-only code disabled: `CONFIG_BOARD_CRASHDUMP` and the `hardfault_log` command read NVIC registers; `srgbled` uses DWT/NVIC; `ARMV7M_*` options.

## Step 6: PX4 board

- Template: `boards/aifoundry/erbium` (added upstream 2026-10-12): NuttX, no peripherals, params and dataman on tmpfs (`BOARD_ROOT_PATH="/tmp"`), chip layer with only `board_critmon`, `board_reset`, `hrt`, `version`. Replaces the Pico.
- A custom board doesn't build the fork's board `src/`, so the PX4 board provides `zynqmp_rpu_board_initialize()`, `rpmsg_serialrawinit()` and the rptun start.
- `rcS` loads params (line 203) before `rc.board_defaults` (276): mount `/tmp` in `board_app_initialize()`.
- Mandatory files:
  - `default.px4board`, `firmware.prototype`
  - `nuttx-config/{Kconfig, include/board.h, nsh/defconfig, scripts/script.ld}`
  - `src/{CMakeLists.txt (drivers_board), board_config.h, init.c}`
- `board_config.h` must define `RC_SERIAL_PORT` or `CONFIG_BOARD_SERIAL_RC` (`#error` at `board_common.h:271`).
- `nuttx-config` must be inside the board directory (`platforms/nuttx/CMakeLists.txt:59–65`).
- The option names below were collected on the 10.3 fork. On 12.12, `DISABLE_POLL` and `SIG_SIGWORK` weren't found in `sched/Kconfig`, `fs/Kconfig` or `apps/nshlib/Kconfig`: Erbium's defconfig gives the 12.12 names (e.g. `ETC_CROMFS`, `ETC_ROMFS`, `ETC_ROMFSSECTSIZE` instead of `NSH_*ROMFS*`); use it instead of the list below.
- **NuttX options PX4 enforces:**
  - `CONFIG_NSH_DISABLE_ECHO/SET/SLEEP/SOURCE` off (`FATAL_ERROR`)
  - `TASK_NAME_SIZE` and `STACK_COLORATION` (`print_load.cpp`)
  - `SCHED_INSTRUMENTATION` (logger, cpuload)
  - `DISABLE_POLL` off
  - `DISABLE_MOUNTPOINT` off
- **Set in almost every PX4 defconfig:**
  - Board/link: `ARCH_BOARD_CUSTOM*`, `HAVE_CXX`, `HAVE_CXXINITIALIZE`, `RAW_BINARY`, `DEBUG_SYMBOLS`.
  - Serial/stdio: `SERIAL_TERMIOS` (mavlink needs `tcsetattr`), `FDCLONE_STDIO`, `STACK_COLORATION`, `USEC_PER_TICK=1000`.
  - NSH startup: `INIT_ENTRYPOINT="nsh_main"`, `SYSTEM_NSH`, `BUILTIN`, `NSH_BUILTIN_APPS`, `NSH_ARCHINIT`, `NSH_ROMFSETC`, `NSH_CROMFSETC`, `FS_CROMFS`, `FS_ROMFS`, `NSH_VARS`, `NSH_LINELEN=128`, `NSH_MAXARGUMENTS=15`, `NSH_NESTDEPTH=8`, `NSH_ROMFSSECTSIZE=128`.
  - Work queues and instrumentation: `SCHED_HPWORK` (priority 249), `SCHED_LPWORK`, `SCHED_INSTRUMENTATION` + `_SWITCH` + `_EXTERNAL`.
  - Signals: `SIG_DEFAULT`, `SIG_SIGALRM/USR1/USR2_ACTION`, `SIG_SIGWORK=4`.
  - Allocation/misc: `PREALLOC_TIMERS=50`, `PTHREAD_STACK_MIN=512`, `GRAN`, `GRAN_INTR`, `BOARDCTL_RESET`, `BOARD_RESET_ON_ASSERT=2`, `TASK_NAME_SIZE=24`, `LIBC_MAX_EXITFUNS=1`.
  - Also common: `FS_PROCFS` + `FS_PROCFS_REGISTER`, `FS_BINFS`, `PIPES`, `PRIORITY_INHERITANCE` + `SEM_PREALLOCHOLDERS`, `LIBC_FLOATINGPOINT`, `SCHED_WAITPID`.
- **Startup chain:**
  1. `nsh_main` → `NSH_ARCHINIT` → `board_app_initialize()` → `px4_platform_init()` (hrt, cpuload, procfs/binfs, work queues, params, uORB, log)
  2. NSH mounts CROMFS on `/etc` and runs `rcS`
  3. `rcS` runs `param select $PARAM_FILE`, `rc.board_defaults`, the airframe, sensors or SIH, `rc.board_mavlink`, `rc.board_extras`, the logger
- **Params without storage:**
  - No PX4 board runs without flash or SD. `CONFIG_BOARD_PARAM_FILE` on tmpfs (`/tmp/params`, `fs/tmpfs` exists in the 12.12 fork) gives volatile params; the first `param import` fails harmlessly.
  - Persistent options for later: NuttX `rpmsgfs` (Linux-side server **verify**), or a PX4 `PARAM_REMOTE`-style bridge (exists only for QuRT/POSIX).
- **Memory:** a minimal flight-capable PX4 is about 1–1.5 MB of code and at least 256 KB of RAM (inferred from the reference boards' linker scripts, **verify** with the link). No PX4 board runs code from RAM, but NuttX supports it (`BOOT_RUNFROMSDRAM`).

## Step 8: HITL and MAVLink

- HITL: airframe 1001 (`rc_quad_x.hil`, listed only with `PWM_OUT_SIM`) sets `SYS_HITL 1`; `rcS` then runs `sensors start -h`, `commander start -h`, `pwm_out_sim start -m hil`. Sensor data comes in as `HIL_SENSOR`/`HIL_GPS`; `mavlink` sends `HIL_ACTUATOR_CONTROLS` at 200 Hz, only on links above 5000 B/s (`set_hil_enabled()`).
- Simulator: PX4 supports HITL only with Gazebo Classic (serial link, `iris_hitl.sdf` `serialDevice`). `gz` talks to PX4 through `gz_bridge`, not MAVLink, so it has no HITL. Gazebo Classic isn't packaged for Ubuntu 24.04.
- No lockstep in HITL: the loop runs in real time over RPMsg, Linux and TCP, so link latency adds to control delay.
- `mavlink` needs `tcgetattr`/`tcsetattr` to succeed, otherwise it closes the port (`mavlink_main.cpp:609–633`). `uart_rpmsg_raw` registers a serial upper half and selects `ARCH_HAVE_SERIAL_TERMIOS`. Its rate is baud / 20 unless `-r` is given.
- Several `uart_rpmsg_raw` instances all use the endpoint name `"rpmsg-tty"`. Linux should create one channel and `/dev/ttyRPMSGn` per announced address (**verify**).
- Logging with no storage: `SDLOG_BACKEND=2` streams the log over MAVLink.
- **8.4 Gazebo container** (2026-11-03):
  - Mounting the PX4 tree failed: PX4-Autopilot is a submodule, its `.git` file points to the workspace's `.git/modules`, so `src/lib/version` stops with "is not a directory". HITL uses nothing from the PX4 SITL build, so the image builds `sitl_gazebo-classic` alone instead and mounts no workspace folder.
  - At the pinned commits (`sitl_gazebo-classic` `f835e07`, `mavlink` `2e2b6af`), `gazebo_camera_manager_plugin` doesn't compile: `VIDEO_STREAM_STATUS` gained `vfov`. The image builds only `models_gen` and the plugins `iris_hitl` / `hitl_iris.world` load (mavlink interface, motor model, multirotor base, IMU, GPS, magnetometer, barometer, groundtruth).
  - Headless check with a socat PTY pair standing in for the KV260: `gzserver` with `hitl_iris.world` opens `/tmp/ttyKV260` and sends MAVLink v2 (274 KB, 6153 `0xfd` markers in about 10 s).
  - GUI: the D3D12 GPU path doesn't render in the 22.04 container; `SOFTWARE_GL=1` (llvmpipe) shows the iris.
  - `run.sh` detects WSL or native Ubuntu. On native Ubuntu, plain `./run.sh` (X11, GPU through `/dev/dri`) shows the iris in `hitl_iris.world`. Plain `gazebo` opens the empty default world: the vehicle and its HITL plugin come only from the world file.
  - The plugin opens the serial device once, at load: if `/tmp/ttyKV260` is missing it prints `Serial port closed!` for every message and never retries.
- **8.5** (2026-11-03): the bridge carries PX4's MAVLink continuously from `/dev/ttyRPMSG1` to `/tmp/ttyKV260` in the container (native Ubuntu PC, board on a direct link); `mavlink status`: tx 2131.7 B/s, txerr 0.
  - The PetaLinux image has no `socat` (`CONFIG_socat` not set); installed with `dnf` for now.
  - The container's `/tmp` is not the host's: the PTY socat must run in the container. With it on the host, `printf '\0' > /tmp/ttyKV260` in the container created a 1-byte regular file (`od` printed `00`; `tcgetattr`: Inappropriate ioctl for device), and the host's PTY filled with nobody reading it (one burst, then nothing).
  - `txerr` 0 at full tx shows the R5 side drains: a stall there would fill the 4096-byte TX buffer in about 2 s.
  - Reading the PTY by hand needs raw mode set on the read (`socat -u OPEN:/tmp/ttyKV260,raw,echo=0 STDOUT | od …`); Gazebo's Boost serial port sets it itself.
- **8.6** (2026-11-03): Gazebo `Opened serial device /tmp/ttyKV260`; HIL data flows both ways.
  - `mavlink status`: rx 18.6 kB/s, loss 0 %, 10975 messages with 0 lost (`HIL_SENSOR` 276 Hz, `HIL_GPS`, heartbeat 1 Hz); tx 17.4 kB/s (2.1 kB/s before HIL started), `txerr` 0.
  - `listener vehicle_attitude` on the ground: roll 0.3°, pitch −0.3°, yaw 26.1°, `quat_reset_counter` 2. `commander status`: disarmed, Hold, no failsafe; `commander check`: `Preflight check: OK`.
  - Gazebo's first message is enough after a fresh PX4 start; no byte from Linux is needed first.
  - `listener` was missing (not in Erbium's board config either): added `CONFIG_SYSTEMCMDS_TOPIC_LISTENER` (PX4 `03c155bbaac`), ddr 1,617,000 B (4.82 %, +29 KB), heap 30.5 MiB. PX4 `main` has `sensor_gnss` / `vehicle_gnss`, no `sensor_gps`.
- **8.7** (2026-11-03): QGroundControl on the native Ubuntu PC connects through Gazebo on UDP 14550 by itself (no link settings). Takeoff, position hold and landing work; the hover is very stable.
- **8.8** (2026-11-03): measurements during hover (`top`, `work_queue status`, `perf`, `mavlink status`) are in `HITL_test_bench_results.md`.

---

## Appendix: first attempt on the 10.3 fork (2026-10-23)

Kept on the fork's `kv260-rpu-10.3` branch: `40cbf36139` (armv7-r), `e1bf775bc3` (chip), `1cca55e10c` (board), `22a68db6e6` (RPMsg link, chip side; not tested on the board). PX4 was at `446895fdc0`, the fork at `201d8b01f1`, apps at `e37940d85`. Steps 1.1–1.8 passed: QEMU ostest and `sleep 10`, ostest on the board (`shared` without RPMsg), calibration 31750.

### Background: the 10.3 fork

- PX4 builds only against its own NuttX fork. The submodule (`.gitmodules`) tracks `px4_firmware_nuttx-10.3.0+`.
- The fork is about 17,000 commits behind the port's tree (`git describe`: `nuttx-8.2-10681` vs `nuttx-8.2-27944`).
- The fork has `armv7-r`, `ARCH_CORTEXR5` and TMS570 (the chip the port came from). The TMS570 files differ by only 2–68 lines per file between the two trees.
- The fork uses Make only: no CMake files.
- Its OpenAMP is v2022.04.0, downloaded with `curl` on the first build (`openamp/open-amp.defs`), against 2025.10.0 in the port's tree.
- The fork has no ZynqMP chip. PX4 has no Cortex-R support: no Platform file, no chip mapping, no chip layer.

---

### Step 0: Trees and baselines (2026-10-23)

- All submodules were already initialized at the commits PX4 records. Branch `kv260-rpu` created at PX4 `446895fdc0`, fork nuttx `201d8b01f1`, fork apps `e37940d85`.
- **PX4 baseline:** `make raspberrypi_pico_default` links with arm-none-eabi-gcc 13.2.1: `flash: 1120288 B (53.42 % of 2 MB)`, `sram: 17400 B (6.44 % of 264 KB)`. About 1.1 MB of code: fits the 32 MiB `rproc0`, about 4× the TCM.
- **TMS570 doesn't build in the fork**:

| Problem | Affects KV260 |
|---|---|
| The defconfig uses the buildroot toolchain (`armeb-nuttx-eabi-gcc`); with `ARMV7R_TOOLCHAIN_GNU_EABI` and the chip's forced `ENDIAN_BIG` it wants `armeb-none-eabi-gcc`. `make CROSSDEV=arm-none-eabi-` gets past it. | no (little-endian, GNU EABI) |
| `tms570/Make.defs` lists `tms570_spi.c`, which isn't in the fork | no |
| `armv7-r/arm_syscall.c:36` includes `addrenv.h`, which doesn't exist. Upstream removed the include in `de1ad746d8`. | **yes** (step 1.1) |
| `armv7-r/arm_gicv2.c` is always compiled and fails without a GIC (`CHIP_MPCORE_VBASE` undeclared) | no (the chip defines it) |

- So the baseline is a compile check: `arm_head.o` and `arm_vectors.o` build with `arm-none-eabi`; `arm_syscall.o` fails on `addrenv.h`.
- The build warnings show the fork's `uart_ops_s` `receive` takes `unsigned int *`, like the port tree. The fork's own TMS570 (`tms570_serial.c:150`) is out of date. The port's serial driver needs no change.

---

### Step 1: Backport differences (fork vs port tree)

**armv7-r common code**

- `mpcore.h` defines `MPCORE_ICC_OFFSET`/`MPCORE_ICD_OFFSET` without `#ifndef`. That is checked in the fork, and it is the most dangerous item. The port's `chip.h` overrides them (GICD at +0, GICC at +0x1000). Without the guards the fork's values (0x2000, 0x1000) win with only a "redefined" warning, and the GIC is mis-addressed.
- `arm_mpu.c` is built only under `CONFIG_BUILD_PROTECTED` (`armv7-r/Make.defs:48`, checked).
- The fork has no `mpu_initialize()`/`struct mpu_region_s`. `mpu.h` has `mpu_allocregion()`, `mpu_log2regionceil()`, `mpu_set_drbar/drsr/dracr()`, `mpu_control()`.
  - Its `mpu_priv_noncache()` sets TEX(4) and Shareable. Don't use it: shareable breaks LDREX/STREX on the R5.
- The fork's `__start` clears `SCTLR_M` and never sets it; the port's sets it under `#ifndef CONFIG_SMP` (upstream `eb0e05be0d`, "armv7-r: add armv7-r smp support"). The fork already sets `SCTLR_BR` (`CPU_BACKGROUND_REGION` hard-coded to 1 in `arm_head.S`), so setting `SCTLR_M` gives the port's state: MPU on, no regions, privileged code on the default memory map.
  - Without it, the MPU stays off. With the MPU off, ARMv7-R treats all data accesses as Strongly-ordered (**verify** in the ARMv7-R ARM): unaligned accesses fault (GCC emits them for cortex-r5, e.g. `memcpy`), exclusives take the shareable path, and accesses are slow.
  - The port's hardware tests always ran with the MPU on, including `shared` before RPMsg (no `ARM_MPU`). Step 1.7 removes `ARM_MPU`, so without `SCTLR_M` it would run in an untested mode.
- The port's `__start` aligns the idle stack (`bic sp, sp, #7`); the fork's doesn't. `IDLE_STACK_TOP` is `_ebss + CONFIG_IDLETHREAD_STACKSIZE`.
- The fork's `__start` has the same order as the port: `ldr sp`, cache invalidate, SCTLR, `bl arm_data_initialize` (unless `ARMV7R_MEMINIT`), `b arm_boot`. The RAM zeroing goes between the last two; nothing is on the stack yet, so zeroing the idle stack is safe.
- `ARMV7R_LOCKSTEP_REGINIT` and `ARMV7R_ZERO_UNUSED_RAM` don't exist. The fork's exception entries also switch to SYS mode, so banked SPs stay unused, as in the port.
- `arm_internal.h` knows only `LWL_CONSOLE` and `CONSOLE_SYSLOG` for undefining `USE_SERIALDRIVER`.

**Chip and kernel APIs**

| Port uses | Fork |
|---|---|
| `<nuttx/debug.h>` | `<debug.h>` |
| `arm_color_intstack()` in irq.c | static in `common/arm_initialize.c`, already called |
| `g_current_regs` from common code | each chip defines `g_current_regs[1]` and clears it in `up_irqinitialize()` (as fork TMS570 does) |
| `sched_getcpu()` | only with `CONFIG_SMP` |
| `spinlock_t` + `SP_UNLOCKED` | empty struct and no `SP_UNLOCKED` without `CONFIG_SPINLOCK`: use `up_irq_save()` |
| `void up_putc(int)` | `int up_putc(int)`, which also sends `'\r'` before `'\n'` |
| `UP_DSB()` | `ARM_DSB()` (`armv7-r/barriers.h`) |
| `BOARD_LATE_INITIALIZE` default `y` | default `n` (`sched/Kconfig:1238`, checked): without it `board_late_initialize()`, and with it procfs and rptun, never runs |
| `up_udelay` in `sched/clock` | `arch/arm/src/common/arm_udelay.c`, different loop; recalibrated in 1.8: same value, 31750 |

Unchanged: `irq_attach`, `up_timer_initialize`/`nxsched_process_timer`, `nx_mount`, `work_queue`, `kmm_zalloc`, `drivers_initialize()`, the GIC init names. The fork's GIC init also targets all SPIs at CPU0, level-sensitive.

**Kconfig and toolchain** (checked):

- Every `CONFIG_*` in the five port defconfigs exists in the fork's nuttx or apps Kconfig, or in the chip/board Kconfig being copied. Existing isn't enough: `SUPPRESS_UART_CONFIG` is dropped unless `EXPERIMENTAL` is set (see step 1 results). So do the chip's selects (`ARCH_HAVE_DPFPU`, `ARCH_DCACHE`, `ARCH_ICACHE`, `ARCH_HAVE_MPU`, `ARCH_HAVE_LOWVECTORS`, `ARMV7R_HAVE_GICv2`).
- The fork's armv7-r toolchain defaults to `ARMV7R_TOOLCHAIN_GNU_EABI` and gives `-mcpu=cortex-r5 -mfpu=vfpv3-d16 -mfloat-abi=hard`, so the defconfigs need no toolchain option.

**Board files:**

- `zynqmp_rpu_autoleds.c`, `_buttons.c`, `_userleds.c` are TMS570 leftovers that the board Makefile never builds. They are the only users of `zynqmp_rpu_gio.h`, which doesn't exist.
- Missing in the fork, apart from generated headers: `<nuttx/debug.h>` (1.2) and `<nuttx/rpmsg/rpmsg.h>` (step 2).
- `scripts/Make.defs` and `src/Makefile` follow the fork's layout (compared with the fork's `launchxl-tms57004`). The fork's TMS570 sets `ARCHCPUFLAGS` in its board `Make.defs`; the KV260 board takes them from `Toolchain.defs`.
- `tcm-lockstep.ld` defines every symbol the fork's `arm_head.S` uses (`_sbss`, `_ebss`, `_eronly`, `_sdata`, `_edata`).
- The port's board directory has build outputs (`src/libboard.a`, `src/*.o`, `src/Make.dep`, `scripts/tcm-lockstep.ld.tmp`). Don't copy them.
- `run-qemu.sh` loads `./nuttx`, so it runs from the fork's `nuttx` directory.

#### Step 1 results (2026-10-23)

Fork `kv260-rpu` commits:

| Commit | Content |
|---|---|
| `40cbf36139` | armv7-r: `addrenv.h`, `mpcore.h` guards, `SCTLR_M`, idle stack alignment, `arm_mpu.c` under `ARM_MPU`, `ARMV7R_LOCKSTEP_REGINIT`, `ARMV7R_ZERO_UNUSED_RAM` |
| `e1bf775bc3` | chip `zynqmp-rpu`, adapted as listed above |
| `1cca55e10c` | board `kv260-rpu`: `qemu`, `nsh`, `calib`, `shared` |

- **1.1 checks:** `arm_syscall.o`, `arm_head.o` (options off and on), `arm_vectors.o` and `arm_mpu.o` (with `ARM_MPU`, without `BUILD_PROTECTED`) build in the TMS570 config. `arm_fpuconfig.S` doesn't build there (TMS570 has no FPU, so no `-mfpu`); assembled directly with `-mcpu=cortex-r5 -mfpu=vfpv3-d16 -mfloat-abi=hard` it builds.
- **RPMsg left out of the board until steps 2–3:** the `rpmsg` config, `zynqmp_rpu_rpmsg_echo.c` (and its Makefile block, Kconfig entry, prototype), `rpmsg_serialrawinit()` and the rptun start in `zynqmp_rpu_bringup.c`, and `RPTUN`, `ARM_MPU`, `ARM_MPU_NREGIONS`, `KV260_RPU_RPMSG_ECHO` in `shared`. `scripts/tcm-lockstep.ld` keeps its (empty) `.resource_table` section.
- **Differences found while building (not in the lists above):**

| Problem | Fix |
|---|---|
| `SUPPRESS_UART_CONFIG` dropped from `calib`, `shared`, `rpmsg`: the fork's "Bring-Up Options" menu depends on `EXPERIMENTAL && DEBUG_FEATURES` (upstream `8a265e274d` removed `EXPERIMENTAL`) | `CONFIG_EXPERIMENTAL=y` in those defconfigs |
| `tcm-lockstep.ld:86: syntax error`: the fork passes the script to `ld` without the C preprocessor, so the `//` comment stays | comment removed |
| `undefined reference to board_app_initialize` (`boards/boardctl.c:334`): with `BOARDCTL` (selected for NSH) the fork always calls it | new `src/zynqmp_rpu_appinit.c` under `CONFIG_BOARDCTL`, calls `zynqmp_rpu_bringup()` unless `BOARD_LATE_INITIALIZE` |

- Remaining warning: `zynqmp_rpu_irq.c:55: 'zynqmp_rpu_error_handler' defined but not used`, same as the port.
- **1.5 `kv260-rpu:qemu`:** text 159644 B, data 184 B, bss 5252 B; one LOAD segment `0x0`–`0x284d8`.
- **1.6 QEMU:** NSH prompt after 0.7 s, `sleep 10` takes 10 s, `ostest` passes. NSH sends `ESC[6n` (cursor query) and waits for the answer, so drive it from a terminal, not a pipe.
- **1.7 board, `kv260-rpu:shared`:** text 103080 B, data 88 B, bss 4664 B; one LOAD segment `0x0`–`0x1a538`. `.resource_table` is present with size 0 until step 2. Loaded with bring-up 5.2: ostest on UART1 passes. First hardware run of the fork's armv7-r boot (`SCTLR_M` set, no MPU regions, lockstep register init, RAM zeroing).
- **1.8 board, `kv260-rpu:calib`:** m = 31.49624060 ns/iter, b = −3639097.74 ns, R² = 1.0000, 31749.82 iterations/ms. Recommended `CONFIG_BOARD_LOOPSPERMSEC=31750`, the same as the port tree, so the `shared` and `nsh` defconfigs keep 31750.

---

### Step 2: RPMsg in the fork

- No `include/nuttx/rpmsg/`, no `drivers/rpmsg/`, no `CONFIG_RPMSG`. The API is in `include/nuttx/rptun/openamp.h`, implemented in `drivers/rptun/rptun.c`. `RPTUN` depends on `OPENAMP`, which goes in the defconfig.
- `struct rptun_ops_s` has the same fields. `get_resource` returns `struct rptun_rsc_s *` (port tree: `struct resource_table *`).
- `struct rptun_rsc_s` has `offset[2]` (port tree `[3]`) and no `carveout`. The port's table sets only `offset[0]` and `num = 1`, so it is source-compatible.
- `rpmsg_register_callback()` and `rpmsg_get_cpuname()` have the same signatures.
- Remote role: `rptun_dev_start()` calls `rpmsg_init_vdev()`. The buffer-size patch acts only with `VIRTIO_RPMSG_F_BUFSZ`, which the port doesn't set.
- Not checked until OpenAMP is downloaded: behaviour of 2022.04 as a remote of the Linux 6.6 `zynqmp_r5_remoteproc` (vdev status wait, NS announce).

### Step 3: `uart_rpmsg_raw` in the fork

- Absent in the fork (driver and header). Port tree: 378 + 57 lines.
- The fork's `uart_rpmsg.c` adds a NuttX header and the endpoint name `"rpmsg-tty"` + devname, so it doesn't work with Linux `rpmsg_tty` (see bring-up results, step 8).
- Same in the fork: the `uart_ops_s` DMA fields, `uart_dmaxfer_s`, `uart_xmitchars_dma`/`_done`, `uart_recvchars_dma`/`_done`, `SERIAL_RXDMA`/`TXDMA`/`REMOVABLE`, `nxmutex_*`.
- Different: `uart_buffer_s` has `sem_t sem` (no `lock` mutex) and `int16_t` head/tail; a 4096-byte buffer fits.
- `rpmsg_release_tx_buffer()` is used nowhere in the fork, so it is probably missing in OpenAMP 2022.04 (**verify**). `rpmsg_get_tx_payload_buffer` and `rpmsg_send_nocopy` exist.
