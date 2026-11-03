# KV260 RPU — PX4 Implementation Steps

Run PX4 on R5_0 (lockstep), loaded by Linux remoteproc, on PX4's own NuttX fork. Order:
1. Port the working NuttX port into PX4's NuttX fork (12.12), and check it standalone in QEMU and on the board.
2. Move it to DDR.
3. Add the PX4 board and chip layer.
4. Fly HITL (Gazebo Classic on the PC) over an RPMsg MAVLink link.

Explanations and recorded values are in `PX4_impl_results.md`; the NuttX bring-up procedure it reuses is `NuttX/Documentation/board_bringup_steps.md`.

Trees:

| Tree | Path | Branch |
|---|---|---|
| Port (source) | `NuttX/nuttx`, `NuttX/apps` | `kv260-rpu` |
| PX4 | `PX4/PX4-Autopilot` | `kv260-rpu`, fast-forwarded to `upstream/main` |
| PX4 NuttX fork (target) | `PX4/PX4-Autopilot/platforms/nuttx/NuttX/nuttx`, `apps` | new `kv260-rpu`, from the submodule commit (`px4_firmware_nuttx-12.12.0+`) |

The first attempt on the 10.3 fork is kept on the fork's `kv260-rpu-10.3` branch (commits `40cbf36139`, `e1bf775bc3`, `1cca55e10c`, `22a68db6e6`).

Standalone NuttX build in the fork (Make, as PX4 uses it):

```sh
cd ~/dev/HITL_PX4_KV260-RPU_TB/PX4/PX4-Autopilot/platforms/nuttx/NuttX/nuttx
make distclean && ./tools/configure.sh -l kv260-rpu:<config> && make -j$(nproc)
```

After a PX4 build (which configures and builds NuttX in this tree), use `make distclean ARCHSCRIPT=`.

---

## Step 0: Set up the trees

1. **Update PX4 to `upstream/main` and sync the NuttX fork and apps submodules.** In `PX4/PX4-Autopilot`, on `kv260-rpu`: `git fetch upstream`, `git merge --ff-only upstream/main`, `git submodule sync --recursive`, `git submodule update --init --recursive`. Check: the fork is at `8626377ce3` (`nuttx-12.12.0-80`), apps at `4319b404bc`.
2. **Create `kv260-rpu` branches in the fork and apps, keeping the 10.3 work.** In the fork's `nuttx`: rename the old `kv260-rpu` to `kv260-rpu-10.3`, create `kv260-rpu` at the submodule commit. In `apps`: create `kv260-rpu` at the submodule commit.
3. **Confirm an existing board, `raspberrypi_pico_default`, builds as a baseline.** Baseline PX4 build of an existing board: `make raspberrypi_pico_default`. Check: it links and prints the memory usage.

---

## Step 1: Port the chip and board into the fork

1. **Cherry-pick the armv7-r MPU, lockstep and RAM-zeroing fixes into the fork.** armv7-r common code, two commits:
   - Commit A: `git cherry-pick -x afdc7675c8` (upstream "arch/armv7-r: Include arm_mpu.c when CONFIG_ARM_MPU is enabled": `Make.defs` and `CMakeLists.txt`).
   - Commit B: `git cherry-pick -x 0f4cc1ac76`. `Kconfig`, `arm_fpuconfig.S` and the RAM-zeroing hunk apply; `arm_head.S` conflicts on the `__start` hunk. Resolve by hand:
     - the `CONFIG_ARMV7R_LOCKSTEP_REGINIT` block right after `__start:`, before `#if defined(CONFIG_SMP) && CONFIG_SMP_NCPUS > 1` (keep the fork's condition)
     - the `CONFIG_ARMV7R_ZERO_UNUSED_RAM` block between `bl arm_data_initialize` / `#endif` and `b arm_boot`
   - Check: `git diff 036f5946f8 -- arch/arm/src/armv7-r` matches `git show afdc7675c8 0f4cc1ac76` apart from where the `__start` block sits. With both options on (temporary config), `objdump -d arm_head.o` shows the `mov rN, #0` / `cpsid` sequence before the MPIDR read.
2. **Cherry-pick the `uart_rpmsg_raw` driver that Linux's `rpmsg_tty` understands.** `uart_rpmsg_raw`, two commits:
   - Commit C: `git cherry-pick -x 65207ae1c5` ("serial/uart_rpmsg: add _raw version of driver").
   - Commit D: `git cherry-pick -x 0a6a2e5e04`, keeping only the `uart_rpmsg_raw.c` hunk (if `uart_rpmsg.c` conflicts: `git checkout --ours drivers/serial/uart_rpmsg.c`). Add to the message: "uart_rpmsg.c hunk dropped: the fork never had that guard."
   - Check: `drivers/serial/uart_rpmsg_raw.c` and `include/nuttx/serial/uart_rpmsg_raw.h` are identical to the port tree's; `git diff <commit B> --stat` lists only the 10 files of `65207ae1c5`.
3. **Copy the zynqmp-rpu chip code and adapt it to the 12.12 APIs.** Copy `arch/arm/src/zynqmp-rpu/` (with `hardware/` and `CMakeLists.txt`) and `arch/arm/include/zynqmp-rpu/`, leaving out `zynqmp_rpu_irq_delete.h`. Adapt:
   - `<nuttx/debug.h>` → `<debug.h>` (`zynqmp_rpu_irq.c`, `zynqmp_rpu_serial.c`)
   - `zynqmp_rpu_rptun.c`: `get_resource` returns `struct rptun_rsc_s *`; add `#include <arch/barriers.h>` for `UP_DSB()`
   - `arch/arm/Kconfig`: add `ARCH_CHIP_ZYNQMP_RPU` to the chip choice (next to TMS570), `default "zynqmp-rpu"` under `ARCH_CHIP`, and the `source` line.
   - Commit (chip).
4. **Copy the kv260-rpu board and add `board_app_initialize()` and late init.** Copy the git-tracked files of `boards/arm/zynqmp-rpu/kv260-rpu/` without `zynqmp_rpu_autoleds.c`, `_buttons.c`, `_userleds.c`. Adapt:
   - new `src/zynqmp_rpu_appinit.c`: `board_app_initialize()`, which calls `zynqmp_rpu_bringup()` unless `BOARD_LATE_INITIALIZE`; built under `CONFIG_BOARDCTL` in `src/Makefile` and `src/CMakeLists.txt`
   - every defconfig: add `CONFIG_BOARD_LATE_INITIALIZE=y`
   - `boards/Kconfig`: the choice, the `ARCH_BOARD` default, the `source` line
   - Commit (board).
5. **Build all five configs and check segments, resource table and linked symbols.** Build `qemu`, `nsh`, `calib`, `shared` and `rpmsg` (OpenAMP and libmetal are downloaded on the first RPMsg build). Check:
   - `.config` keeps every option of each defconfig
   - one LOAD segment, inside the TCM
   - `shared`: `.resource_table` is `PROGBITS`, size `0xd0` (`sizeof(struct rptun_rsc_s)`)
   - `rpmsg`: `uart_rpmsg_raw_init` and `rpmsg_serialrawinit` are linked
   - record any error not listed in 1.1–1.4 in the results
6. **Run the `qemu` config in QEMU: `sleep 10` timing and ostest.** From the fork's `nuttx` directory (the script loads `./nuttx`), build `qemu` and run `boards/arm/zynqmp-rpu/kv260-rpu/scripts/run-qemu.sh`. Check: `sleep 10` takes 10 s, `ostest` exits with status 0.

---

## Step 2: Board checks: ostest, calibration, RPMsg link

1. **Run ostest from TCM on the board, plus remoteproc stop/restart.** Build `shared`, load with bring-up step 5.2. Check: ostest on UART1 exits with status 0; stop and restart (bring-up 5.4).
2. **Time `up_udelay` on a free-running TTC counter instead of a calibrated loop.** `up_udelay` on a hardware counter (the loop calibration depends on code layout, see the results):
   - new `zynqmp_rpu_timebase.c`: TTC2 counter 1 free-running (no prescaler, no interrupts, count up, wraps at 2³²), started by `zynqmp_rpu_timebase_init()` from `arm_boot()`; `zynqmp_rpu_timebase()` returns the 32-bit count
   - `up_udelay()` / `up_ndelay()` override the weak loop versions in `sched/clock/delay.c`: wait `usec × BOARD_TTC_CLK_FREQUENCY / 1 MHz` counts, adding up 32-bit deltas so waits past the 43 s wrap work
   - declare `zynqmp_rpu_timebase()` in a chip header the PX4 HRT can include (step 5.3)
   - remove the `calib` config; `CONFIG_BOARD_LOOPSPERMSEC` stays (required by `arch/Kconfig`, unused)
   - Check (QEMU, then board): a temporary test times `up_udelay(1000000)`, `1000 × up_udelay(1000)` and `1000000 × up_udelay(1)` against `clock_gettime`; the first two within one tick, the third gives the per-call overhead
3. **Check the RPMsg link with the echo service and stress test.** With `shared`, run bring-up step 7 (link checks, echo, stress test, stop/restart).

---

## Step 3: `uart_rpmsg_raw` console on the board

1. **Get NSH on `/dev/ttyRPMSG0` working through stop/restart.** Build `rpmsg`, load it, run bring-up step 8.3–8.7 (NSH on `/dev/ttyRPMSG0`, `help`, `free`, `ps`, stop/restart).

---

## Step 4: DDR layout

1. **Linker script keeping only vectors and resource table in TCM, rest in DDR.** New linker script `scripts/ddr-lockstep.ld`:
   - `tcm` region `0x0`, 256 KB: `.vectors` only, plus `.resource_table`.
   - `ddr` region `0x3c000000`, 32 MiB (`rproc0`): `.text`, `.init_section`, `.ARM.ex*`, `.data`, `.bss`.
2. **Add `ddr` and `qemu-ddr` configs; `BOOT_RUNFROMSDRAM` selects the DDR linker script.** New configs `kv260-rpu:ddr` (from `rpmsg`, plus `CONFIG_TESTING_OSTEST=y`) and `kv260-rpu:qemu-ddr` (from `qemu`, plus `CONFIG_ARM_MPU=y`): `CONFIG_RAM_START=0x3c000000`, `CONFIG_RAM_SIZE=33554432`, `CONFIG_BOOT_RUNFROMSDRAM=y` (instead of `BOOT_RUNFROMISRAM`). The board `Make.defs` and `CMakeLists.txt` pick `ddr-lockstep.ld` when `BOOT_RUNFROMSDRAM` is set.
3. **Map the DDR carve-out as a cacheable, executable MPU region.** `zynqmp_rpu_boot.c`: one more MPU region, `0x3c000000`, 32 MiB, Normal write-back cacheable, non-shareable, executable. Program it before the shared-window region, so the shared window (higher region number) wins where they overlap.
4. **Confirm two LOAD segments, one in TCM and one in `rproc0`.** Build. Check with `readelf -l`: two LOAD segments, one inside `0x0`–`0x3ffff`, one inside `0x3c000000`–`0x3dffffff`. Check the linker's `ddr:` and `tcm:` lines.
5. **Run from DDR in QEMU: NSH, 32 MiB heap, ostest.** QEMU: build `qemu-ddr`, run `scripts/run-qemu.sh`. Check: NSH, `free` shows about 32 MiB, `ostest` exits with status 0.
6. **Run from DDR on the board: console, heap, ostest, echo stress test.** Load `ddr` with bring-up step 5.2. Check:
   - UART1 and the NSH console work
   - `free` shows about 32 MiB
   - `ostest` exits with status 0
   - the step 2.3 echo stress test passes with the caches on
7. **Optionally recheck `up_udelay` timing when running from DDR.** Run the step 2.2 `up_udelay` test from DDR. Check: same results as from the TCM.

---

## Step 5: PX4 chip layer and toolchain

0. **Fork: turn on the TTC match mode.** `zynqmp_rpu_timebase_init()` adds `XTTCPS_CNT_CNTRL_MATCH_MASK` to its Counter_Control write: the match interrupt fires only with that bit set. Nothing changes while IER is 0. Check: `qemu-ddr` ostest passes; on the board, `ddr` ostest and the `up_udelay` test pass.
1. **Compiler settings.** `platforms/nuttx/cmake/Platform/Generic-arm-none-eabi-gcc-cortex-r5.cmake`: `-mcpu=cortex-r5 -mfpu=vfpv3-d16 -mfloat-abi=hard`, no `-mthumb`, matching the fork's armv7-r `Toolchain.defs` (`ARCH_FPU=y`, `ARM_THUMB` unset). PX4's `Make.defs` gives NuttX only `CMAKE_C_FLAGS`, so this file sets NuttX's flags too.
2. **Chip mapping.** `px4_impl_os.cmake`, `px4_os_determine_build_chip()`: `CONFIG_ARCH_CHIP_ZYNQMP_RPU` → `amd`, `zynqmp_rpu`.
   - **Link the ARMv7-R vector table.** NuttX builds `arch/arm/src/arm_vectortab.o` (`HEAD_ASRC`) next to `libarch.a`, not in it, and PX4 links head objects only for RISC-V. Add `CONFIG_ARCH_ARMV7R` cases next to the `CONFIG_ARCH_RISCV` ones: `nuttx_arch_byproducts` in `platforms/nuttx/NuttX/CMakeLists.txt`, `NUTTX_HEAD_OBJS` in `platforms/nuttx/CMakeLists.txt`. Without it the link only warns (`ENTRY(_vector_start)` not found) and the image has no vectors.
3. **Chip layer from `aifoundry/erbium/`.** `platforms/nuttx/src/px4/amd/CMakeLists.txt` (only `add_subdirectory(${PX4_CHIP})`), `amd/zynqmp_rpu/CMakeLists.txt` (`board_critmon`, `board_reset`, `hrt`, `version`):
   - `include/px4_arch/micro_hal.h`: Erbium's, with `PX4_SOC_ARCH_ID_UNUSED` (as RP2040 and ESP32), `PX4_FLASH_BASE 0x3c000000`
   - `version/`: fixed UUID; `board_mcu_version()` returns "ZynqMP RPU (Cortex-R5F)"
   - `board_critmon/`: Erbium's
   - `board_reset/`: `board_reset()` logs, disables interrupts and loops on `wfi`. The R5 can't reset itself under remoteproc; Linux restarts it with stop/start
4. **HRT on TTC2 counter 1.** `hrt/hrt.c`: the interrupt-driven HRT of `nxp/s32k3xx/` with Erbium's sorted insert; only the clock and the wake-up change:
   - time: `zynqmp_rpu_timebase()` (`zynqmp_rpu_timebase.h`, through the chip include dir) extended to 64 bits in a critical section on every read; µs = counts / (`BOARD_TTC_CLK_FREQUENCY` / 1000000)
   - wake-up: Match 1 (`XTTCPS_MATCH_0_OFFSET`, `XTTCPS_IXR_MATCH_0_MASK` in IER), IRQ 75 (`ZYNQMP_RPU_IRQ_TTC2_1`). The ISR reads ISR (clear-on-read), runs the due callouts and programs the next deadline. Callouts can run in the ISR: the armv7-r IRQ entry saves the FPU registers (Erbium's RISC-V one doesn't, hence its task)
   - the match is an equality compare: a passed value fires only after the 42.9 s wrap. Program at least `HRT_INTERVAL_MIN` (50 µs) ahead, re-read the counter after writing, and reprogram if it has passed
   - cap each deadline at `HRT_INTERVAL_MAX` (50 ms, as s32k3xx), so the ISR also keeps the wrap extension correct
   - read ISR before setting IER: match bits latch while IER is 0 (Match 1 starts at 0)
   - writes only Match 1, IER and ISR of counter 1, never Clock_Control or Counter_Control (NuttX owns them)
   - `#error` unless `CONFIG_ZYNQMP_RPU_TIMEBASE_TTC == 2` and `CONFIG_ZYNQMP_RPU_TIMEBASE_COUNTER == 1` (IRQ 75 is fixed)
5. **No chip-wide rc defaults.** No `platforms/nuttx/init/zynqmp-rpu/rc.board_arch_defaults`: it's optional (ROMFS copies it only if it exists).

Step 5 can't run alone: the step 6 build compiles it, step 7.3 checks the HRT (60 s covers one wrap).

---

## Step 6: PX4 board

1. **Create the `amd/kv260-rpu` board from Erbium, with the `ddr` NuttX config.** `boards/amd/kv260-rpu/`, from `boards/aifoundry/erbium` (NuttX, no peripherals, params in `/tmp`):
   - `default.px4board`: `CONFIG_BOARD_TOOLCHAIN="arm-none-eabi"`, `CONFIG_BOARD_ARCHITECTURE="cortex-r5"`, Erbium's options and modules without `SIMULATOR_SIH` (`PWM_OUT_SIM` stays for HITL), plus `SYSTEMCMDS_TESTS` (`tests hrt`, `hrt_test`)
   - `firmware.prototype`: `board_id` 161, `image_maxsize` 33554432
   - `init/rc.board_defaults`: only `CBRK_SUPPLY_CHK`; no `rc.board_sensors`
   - `nuttx-config/Kconfig`: empty (a custom board needs one)
   - `nuttx-config/include/board.h`: only `BOARD_UART_REFCLK_FREQUENCY` and `BOARD_TTC_CLK_FREQUENCY` (100 MHz)
   - `nuttx-config/scripts/script.ld`: `ddr-lockstep.ld` (PX4 links with `script.ld`)
   - `nuttx-config/nsh/defconfig`: Erbium's PX4 options with the fork's `ddr` chip, memory, RPTUN and RPMsg console options, `ARCH_BOARD_CUSTOM*` pointing to this `nuttx-config`, plus `BOARDCTL_RESET` (fork: `ARCH_CHIP_ZYNQMP_RPU` selects `ARCH_HAVE_RESET`); keeps Erbium's `ARCH_INTERRUPTSTACK=4096` (HRT callouts run in the ISR) and `USEC_PER_TICK=1000`; `BOARD_CRASHDUMP_CUSTOM` unset (PX4's `board_crashdump.c` is then empty). Normalize with `make amd_kv260-rpu_default olddefconfig`
   - `src/board_config.h`: as Erbium's
   - `src/init.c`: Erbium's (mounts tmpfs on `/tmp` before `px4_platform_init()`: `rcS` loads params before `rc.board_defaults`), plus the fork board's hooks: `zynqmp_rpu_board_initialize()` (empty, called from `zynqmp_rpu_boot.c`), `rpmsg_serialrawinit()` (`/dev/ttyRPMSG0` console), `board_late_initialize()` → `zynqmp_rpu_rptun_initialize()` (keep `BOARD_LATE_INITIALIZE=y`: rptun needs HPWORK and must start before NSH opens the RPMsg console), `[boot]` progress lines on the syslog UART. No `/proc` mount: `px4_platform_init()` does it
   - `src/CMakeLists.txt`: `drivers_board` library
2. **Build `amd_kv260-rpu_default` and check it links and fits in DDR.** `make amd_kv260-rpu_default 2>&1 | tee build/kv260-build.log`. Fix build errors in the chip layer or `init.c` rather than in common PX4 code; record each fix in the results. Check, with `ELF=build/amd_kv260-rpu_default/amd_kv260-rpu_default.elf`:
   - it links; the linker's `ddr:` line is well under 32 MiB, `tcm:` holds only the vectors and the resource table
   - `readelf -lW`: two LOAD segments, at `0x0` (TCM) and `0x3c000000` (`rproc0`)
   - `readelf -SW`: `.resource_table` present, in TCM
   - `nm`: `_vector_start` at `0x0`; `hrt_init`, `board_reset`, `rpmsg_serialrawinit`, `zynqmp_rpu_rptun_initialize` defined
   - `readelf -A`: Cortex-R5, VFPv3-D16, VFP argument passing
   - heap: `0x3e000000 - _ebss` leaves several MiB

---

## Step 7: PX4 boot on the board

NuttX syslog goes to UART1 (`/dev/ttyS1`), PX4 shell output to `/dev/ttyRPMSG0`. The RPMsg console holds output until Linux writes a byte: `rcS` fills the 4 KiB TX buffer and blocks until then.

0. **Prerequisites.** Add `EXE px4fw /home/kevin/dev/HITL_PX4_KV260-RPU_TB/PX4/PX4-Autopilot/build/amd_kv260-rpu_default/amd_kv260-rpu_default.elf` to `scripts/kv260_deploy.conf`. PetaLinux with `rpmsg_tty` (bring-up step 8). Terminal open on UART1.
1. **Load the PX4 ELF through remoteproc and open the RPMsg console.** `scripts/kv260_deploy.sh -e px4fw`. Check:
   - Linux: `remoteproc0/state` reads `running`, `dmesg | grep 'creating channel'` shows `rpmsg-tty`, `/dev/ttyRPMSG0` exists
   - UART1: NuttX boots with no `ERROR` or assert
   - `sudo picocom /dev/ttyRPMSG0`, Enter: `rcS` output, then `nsh>`
   - if nothing: JTAG attach (bring-up step 4), check PC and fault state
2. **Check PX4 boots cleanly.** Check:
   - `ver all`: "ZynqMP RPU", PX4 GUID `0000...` with the `KV260_RPU_R5` UUID
   - `dmesg`: no errors except the expected `param import` failure on first boot
   - `uorb status`, `work_queue status`
   - `ps` / `top`: `rptun` and `hpwork` present, idle load high, no task near its stack limit
   - `free`: about 30 MiB heap
3. **Check the HRT.** The NuttX tick and the HRT share the TTC clock, so `hrt_test` and `tests hrt` check scheduling, not the clock frequency:
   - `hrt_test start`: about 1,000,000 µs for `usleep` and `sleep`, `HRT_CALL - 1`; `tests hrt`: about 100,000 µs per 0.1 s
   - against Linux, over at least 2 minutes (about 3 counter wraps): at two points note Linux `date +%s.%N`, NSH `cat /proc/uptime` and the HRT seconds from `tests hrt`. Check: the HRT matches `/proc/uptime` within a second (the 64-bit extension survives the wraps), and both advance like Linux time to better than 0.1 % (`BOARD_TTC_CLK_FREQUENCY` is right)
4. **Parameters, `reboot` and stop/start.** `param set MAV_SYS_ID 2`, `param save`, `reboot`. Check:
   - UART1 prints `reset: halted, restart through remoteproc` (`board_reset()`), NSH stops responding
   - stop/start (bring-up 5.4): `/dev/ttyRPMSG0` goes away and comes back; reconnect, Enter
   - `param show MAV_SYS_ID` is back to 1, as expected with tmpfs params

---

## Step 8: HITL over an RPMsg MAVLink link

1. **Add a second RPMsg tty, `/dev/ttyRPMSG1`, for MAVLink.** PX4 board `src/init.c`: a second `uart_rpmsg_raw_init("linux", "RPMSG1", 4096, false)` in `rpmsg_serialrawinit()`. Check on Linux: `/dev/ttyRPMSG0` is still NSH and `/dev/ttyRPMSG1` appears (Linux numbers them in channel order). Like the console, it holds TX until Linux sends a byte; Gazebo sends first.
2. **Start MAVLink on the second tty and select the HIL airframe.** The board already has the modules HITL needs (`PWM_OUT_SIM`, `mavlink`, `navigator`, `flight_mode_manager`, `land_detector`); no logger for now (no storage).
   - `init/rc.board_mavlink`: `mavlink start -d /dev/ttyRPMSG1 -r 100000` (`set_hil_enabled()` streams `HIL_ACTUATOR_CONTROLS` only above 5000 B/s)
   - `rc.board_defaults`: `param set-default` `SYS_AUTOSTART 1001` (HIL quad X, in ROMFS with `PWM_OUT_SIM`; sets `SYS_HITL 1`, so `rcS` starts `sensors -h` and `pwm_out_sim -m hil`) and `SYS_DM_BACKEND 1` (dataman in RAM)
3. **Build the flight image, check it fits in DDR, and load it.** Build, check the linker's `ddr:` line, deploy (`scripts/kv260_deploy.sh -e px4fw -y`). Check in nsh: `mavlink status` shows the instance on `/dev/ttyRPMSG1`; `param show SYS_HITL` is 1.
4. **Gazebo Classic container (Ubuntu 22.04) on the PC.** `Tools/setup/ubuntu.sh` installs Gazebo Harmonic, which has no HITL, so the container installs Gazebo Classic 11 from Ubuntu's `gazebo` and `libgazebo-dev` packages. The PC runs native Ubuntu with the KV260 connected to it directly (WSL also works); Docker is installed on it. The image is self-contained (HITL needs only the plugins, models and worlds, not PX4 SITL); no workspace folder is mounted. Files in `HITL_PX4_KV260-RPU_TB/Simulation/gazebo-classic/`:
   - `Dockerfile`:
     - `gazebo libgazebo-dev`, the `sitl_gazebo-classic` build dependencies, `python3-jinja2 python3-numpy` (model generation), `socat`, `mesa-utils`
     - MAVLink C headers generated with `mavgen` into `/usr/local/include/mavlink`, from the `mavlink` commit PX4 pins (`src/modules/mavlink/mavlink`), dialect `common` (the firmware's)
     - `PX4-SITL_gazebo-classic` cloned at the commit PX4 pins (`Tools/simulation/gazebo-classic/sitl_gazebo-classic`) into `/opt/sitl_gazebo-classic`, built with `-DSEND_ODOMETRY_DATA=ON`, targets `models_gen` and the plugins `iris_hitl` and `hitl_iris.world` load
     - `serialDevice` in `iris_hitl.sdf` set to `/tmp/ttyKV260`
     - Gazebo paths (`/usr/share/gazebo/setup.sh`, plugins, models) set for every shell; a user with the host UID (X server and GPU access)
   - `run.sh` (`build`, `exec` for a second shell, `stop`):
     - `--network host` (TCP to the KV260, UDP 14550 to QGroundControl on the same PC)
     - host detected from the kernel release (`microsoft` → WSL, else Ubuntu); `-m`/`--host-mode wsl|ubuntu` overrides
     - Ubuntu: X11 display (`/tmp/.X11-unix`, `DISPLAY`) after `xhost +SI:localuser:$USER` (needs `x11-xserver-utils`); GPU through `/dev/dri`, with `--group-add` for the GIDs owning the render nodes
     - WSL: WSLg display (`/tmp/.X11-unix`, `/mnt/wslg`, `DISPLAY`, `WAYLAND_DISPLAY`, `XDG_RUNTIME_DIR=/mnt/wslg/runtime-dir`); GPU through `/dev/dxg` and `/usr/lib/wsl`
     - `./run.sh -s` (`--software-gl`) renders with llvmpipe; `./run.sh --help` lists the commands and options
   - Check:
     - `./run.sh build` succeeds; `./run.sh` prints the detected host; in the container `gazebo --version` is 11
     - `glxinfo -B` names the GPU driver, not `llvmpipe` (else use `-s`)
     - `gazebo worlds/hitl_iris.world` shows the iris
5. **Bridge `/dev/ttyRPMSG1` to a serial device in the container.** The HITL plugin (`mavlink_interface`, `serialEnabled 1`) only opens a serial device, once, when Gazebo loads it; start in this order: board, container socat, Gazebo (step 6). `raw,echo=0` keeps both ttys from rewriting MAVLink bytes; `nodelay` turns off Nagle on the TCP leg. `KV260_IP` is the board's address on the PC's link.
   0. **Prerequisite: `socat` on the board.** Enable `CONFIG_socat` in the PetaLinux `rootfs_config` and rebuild the image, or `sudo dnf install socat` until the next reflash.
   1. **KV260 Linux** (PX4 running, nothing else holding `/dev/ttyRPMSG1`): `sudo socat -d -d TCP-LISTEN:5760,reuseaddr,nodelay FILE:/dev/ttyRPMSG1,raw,echo=0`. It serves one connection, then exits; restart it for each session. PX4 sends nothing until Linux has sent a byte (step 1): after a fresh PX4 start, first `echo | sudo tee /dev/ttyRPMSG1 >/dev/null`.
   2. **Container, first shell** (`./run.sh`; the prompt is `px4@…:/opt/sitl_gazebo-classic`): `socat -d -d PTY,link=/tmp/ttyKV260,raw,echo=0 TCP:$KV260_IP:5760,nodelay`. It must run in the container: the container's `/tmp` is not the host's, and Gazebo opens the PTY there. Check:
      - the board's socat logs the connection
      - `ls -l /tmp/ttyKV260` in the container is a link to `/dev/pts/N`; a regular file there (for example from a redirect while the link was missing) blocks the link: stop socat, `rm /tmp/ttyKV260`, restart it
   3. **Check the bridge** in a second shell (`./run.sh exec`). socat sets the PTY raw for the read (a plain `cat` or `od` would apply the default terminal mode, where `0x04` in the MAVLink stream ends the read):
      ```sh
      socat -u OPEN:/tmp/ttyKV260,raw,echo=0 STDOUT | od -An -tx1 -v
      ```
      Check: hex scrolls continuously with regular `fd` (MAVLink v2 start byte); in nsh, `mavlink status` on `/dev/ttyRPMSG1` shows tx around 2000 B/s and `txerr` 0. Stop it with Ctrl-C, then restart both socats before step 6.
   4. **Latency baseline.** `ping -c 20 $KV260_IP` from the PC; note the round trip for step 8.
6. **Run Gazebo Classic in HITL mode.** In the container's second shell, with the step 5 socats running: `gazebo worlds/hitl_iris.world` (docs `simulation/hitl.md`). The image already points `serialDevice` to `/tmp/ttyKV260` (`baudRate` doesn't matter on a PTY). Check: Gazebo prints `Opened serial device /tmp/ttyKV260` and no `Serial port closed!` (`Error opening serial device`: the socat isn't running in this container, or `/tmp/ttyKV260` is a regular file, step 5.2). If the TCP link drops, socat exits and removes the PTY: restart the board socat, the container socat, then Gazebo. Gazebo serves QGroundControl on UDP 14550; QGroundControl on the same PC connects without changes.
7. **Fly a simulated takeoff, hover and landing from QGroundControl.** Check:
   - the vehicle connects; the attitude follows Gazebo
   - arm, take off, hold position, land
8. **Check CPU load, controller rate and timing counters during flight.** In nsh during the flight:
   - `top`: CPU load
   - `work_queue status`: `rate_ctrl` runs at the HIL gyro rate
   - `perf`: no growing late or overrun counters

---

## Debug variant

`boards/amd/kv260-rpu/debug.px4board` builds `amd_kv260-rpu_debug` (deploy `px4dbg`) into its own build folder. It is the standard PX4 board variant mechanism, and it stays on the KV260 branch.

1. **Init tracing (`CONFIG_BOARD_DEBUG_INIT`).** Top-level `Kconfig` option, off by default; `INIT_STEP("...")` in `px4_init.cpp` logs `[init] <step>` to syslog (UART1) before each call of `px4_platform_init()` and `px4_platform_configure()`. Syslog, because before `rcS` the console is on RPMsg and can block. The default build has no code from it. The debug variant turns it on.
2. **Commits.** The tracing is shared PX4 code with no upstream precedent, so it is its own commit (`Kconfig` and `px4_init.cpp` only), separate from the board commits:
   - it can go upstream alone as a small PR from `main`, where reviewers decide whether PX4 wants the option
   - if it is dropped, the board loses only the `CONFIG_BOARD_DEBUG_INIT=y` line of `debug.px4board`
   - `debug.px4board` and the `px4dbg` deploy entry are committed with the board
3. **Later content.** Debug-only options as they are needed, for example a `nuttx-config/debug/defconfig` with extra NuttX checks (assertions, stack checks). A separate NuttX config means deleting the NuttX `*.o`/`lib*.a` when switching variants, since both build in the same NuttX tree.
