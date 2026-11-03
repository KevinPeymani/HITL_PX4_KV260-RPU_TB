# NuttX on KV260 RPU — The Six Steps

Sep 24, 2026 · @Kevin

The short version of the port. NuttX already supports the Cortex-R5 core through its `armv7-r` layer, so this is a board support port: a ZynqMP RPU chip layer plus a KV260 board layer. The step-by-step detail, register tables and checklists are in the [NuttX on Kria KV260 RPU — Porting Plan](https://claude.ai/code/artifact/8572f9d2-ae28-481e-a5ab-16c56c2998bd); the concepts behind each step are in the [Tutoring Plan](https://claude.ai/code/artifact/70b3c012-580a-4c05-8201-833111f86526).

## 1. Learn NuttX from the inside (1–2 weeks, no hardware)

Build and run the `sim` target, then an existing QEMU ARM config (e.g. `qemu-armv7a:nsh`), so you see the whole build/configure/NSH loop working before you touch anything new. Read the Porting Guide and the "OS Components" section of the NuttX docs.

Then trace one existing chip's boot end to end in the source: `__start` → `arm_boot` → `nx_start` → `up_initialize` → `board_late_initialize` → NSH. Trace the TMS570 or RM57 chip directory, since both are ARMv7-R.

You only need to understand the arch interface, not rewrite it: `up_irq_enable`/`up_irq_disable`, `up_irqinitialize`, `up_timer_initialize`, `arm_lowputc`/`up_putc`, `up_allocate_heap`, the vector table, and the linker-script symbols the startup code expects.

## 2. Collect your reference material

**Inside NuttX:** the TMS570/RM57 chip layers (structure, MPU setup, `Make.defs`, `Kconfig`); `arch/arm/src/armv7-a/arm_gicv2.c`, since the RPU's GIC is GICv2-compatible (check whether `armv7-r` already builds it or whether you need to move it into common code); and the Cadence UART driver in the arm64 `zynq_mpsoc` chip, which drives the same PS UART block you'll use.

**Outside NuttX,** three mature RPU ports give you register addresses, init order and gotchas:

- [Zephyr's `zynqmp_rpu` board](https://nrfconnectdocs.nordicsemi.com/ncs/latest/zephyr/boards/amd/zynqmp_rpu/doc/index.html): R5 DDR at 0x00400000, GIC at 0xF9000000, PS UART0 at 0xFF000000.
- [RTEMS's `xilinx-zynqmp-rpu` BSP](https://docs.rtems.org/branches/master/user/bsps/arm/xilinx-zynqmp-rpu.html), whose clock driver uses one of the TTCs as the tick source.
- [U-Boot's `zynqmp-r5` target](https://github.com/u-boot/u-boot/blob/25049ad560826f7dc1c4740883b0016014a59789/doc/board/xilinx/zynqmp-r5.rst).

The fourth reference is AMD's own Cortex-R5 standalone BSP in `embeddedsw` (`boot.S`, `xil_mpu.c`). It is the authoritative source for the MPU and cache setup your `__start` should reproduce.

## 3. Scaffold the chip and board directories

Create two chip directories and one board directory:

- `arch/arm/src/zynqmp-rpu/` and `arch/arm/include/zynqmp-rpu/` hold the chip layer: start code, memory map header, IRQ numbers, GIC glue, TTC timer, UART, `Kconfig`, `Make.defs`.
- `boards/arm/zynqmp-rpu/kv260-rpu/` holds the board layer: linker script, `board.h`, `configs/nsh/defconfig`, `src/*_bringup.c`.

Copy from TMS570/RM57 wholesale and edit. Don't write from blank files.

The linker script is where you decide between TCM and DDR placement. For bring-up, put everything in TCM (256 KiB in lockstep), because it keeps the MPU setup simple and fits NSH and `ostest`. Add a second layout that places code and data in a reserved DDR window later, when PX4 needs the space.

## 4. Bring up in QEMU before hardware

Xilinx's QEMU fork (shipped with PetaLinux) runs ZynqMP R5 code. Zephyr's [`qemu_cortex_r5`](https://nrfconnectdocs.nordicsemi.com/ncs/latest/zephyr/boards/qemu/cortex_r5/doc/index.html) config uses it and emulates the PL390 GIC, the Cadence TTC and the Zynq UART, which are exactly the three peripherals your port needs.

Climb these milestones in order:

1. `__start` runs and `arm_lowputc` prints a character.
2. `.data`, `.bss`, stacks and MPU are set up and `nx_start` is reached; polling-only `printf` works.
3. The GIC is initialized, the TTC tick is firing, and you get an NSH prompt.
4. `ostest` passes.

Each step gives an unambiguous pass/fail, and where it hangs tells you where to look: a hang at milestone 1 points at the linker script or MPU, a hang at milestone 3 at the GIC or timer.

## 5. Move to the KV260

Load the ELF from Linux through remoteproc. This path has to be set up first:

- Confirm the kernel has R5 remoteproc and RPMsg support.
- Write a device-tree overlay with a reserved-memory carve-out for the firmware and the R5 cluster node in lockstep.
- Before NuttX, prove the load path works with a trivial bare-metal image.

Loading from Linux avoids any change to BOOT.bin, so a bad firmware can't brick the board.

Pick a PS UART that Linux's device tree isn't claiming, and mark it disabled for Linux, or share one deliberately. Keep `xsdb`/JTAG as the fallback when something hangs before the console is alive.

## 6. Then the parts you actually care about

NuttX has its own OpenAMP/RPMsg integration (`rptun`), so once the board runs, a Linux↔NuttX RPMsg link needs configuration and a small amount of glue code.

Lockstep vs split mode is chosen in the device tree and reset configuration, not in NuttX.

Once `nsh` and `ostest` are solid, PX4 on the RPU comes down to adding a NuttX board to PX4. NuttX is PX4's native RTOS, so no compatibility layer is needed.

## Two habits that will save you

- Keep a bring-up log of every register you touch and why.
- Get a first PR into the NuttX repo early, even if it only adds the QEMU config. The community is active and will catch arch-layer mistakes you can't see yet.
