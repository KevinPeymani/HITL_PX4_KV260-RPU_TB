# KV260 RPU — Board Bring-up Results

Findings and recorded values behind `board_bringup_steps.md` (same step numbers). Board: KV260, PetaLinux 2024.2 (kernel 6.6.40), R5_0 in lockstep. Sources: UG1085, UG1087, the board's `system.dtb`, `linux-xlnx` tag `xilinx-v2024.2`. Items marked **verify** aren't confirmed yet.

| Step | Result | Date | Commit |
|---|---|---|---|
| 0 QEMU check (tick on TTC2) | passed | 2026-10-19 | `01f5f8a356` |
| 1–2 Board checks, xsdb | passed | 2026-10-19 | |
| 3 JTAG load, ostest | passed | 2026-10-20 | |
| 5 remoteproc load | passed | 2026-10-20 | |
| 6 Calibration | `BOARD_LOOPSPERMSEC=31750` | 2026-10-20 | `2e12be19a5` |
| 7 RPMsg link, echo | passed | 2026-10-22 | `05db9de0b8`, `2e12be19a5` |
| 8 NSH over RPMsg | passed | 2026-10-22 | `05db9de0b8`, `2e12be19a5` |

---

## Step 0: Tick on TTC2

- **TTC0 belongs to Linux:** it drives the cooling fan (`timer@ff110000` has `#pwm-cells`, used by `pwm-fan`). Reprogramming it stops the fan.
- **TTC1–3 are free:** `CONFIG_CADENCE_TTC_TIMER` isn't set (the A53s use the generic timer), and `pwm-cadence` only takes TTCs with `#pwm-cells`.
- The tick uses TTC2 (`0xff130000`, IRQ 74–76; UG1085: TTC0 68–70, TTC1 71–73, TTC3 77–79). `system-user.dtsi` sets `&ttc2 { status = "disabled"; }` so no future driver claims it.

---

## Step 1: Board checks from Linux

| Register | Value | Decoded |
|---|---|---|
| RPU_GLBL_CNTL `0xff9a0000` | `0x50` | Lockstep (SLSPLIT=0), SLCLAMP=1, TCM_COMB=1 (one 256 KB TCM) |
| RPU_0_CFG `0xff9a0100` | `0x04` | VINITHI=1, nCPUHALT=0 (reset value is `0x5`; probably set by remoteproc or PMU firmware, **verify**). Step 3 writes `0x1`. |
| RST_LPD_TOP `0xff5e023c` | `0xA93` | R5_0, R5_1 in reset; bit 4 (RPU power-island reset) set; bit 2 (AMBA) released. Bits 7, 9, 11 probably USB1 (**verify**). |
| RST_LPD_IOU2 `0xff5e0238` | `0x1038A` | TTC2 (bit 13) and UART1 (bit 2) out of reset |

- Remoteproc device: `ff9a0000.rf5ss:r5f_0`. Carve-outs (`nomap`): `rproc0` 0x3c000000 (32 MiB), `rpu0vdev0vring0` 0x3e000000 (16 KiB), `rpu0vdev0vring1` 0x3e004000 (16 KiB), `rpu0vdev0buffer` 0x3e080000 (512 KiB DMA pool).
- No TTC interrupts in `/proc/interrupts`.
- `lpd_lsbus` and `uart1_ref` = 99,999,999 Hz (IOPLL / 15), matching the 100 MHz the board header assumes.
- R5 clock rate not checked (**verify** in `clk_summary`).

---

## Step 2: xsdb

- xsdb runs on the Ubuntu machine with the J4 cable (`jtag_setup.md`, Setup A). APU-target memory reads go through the DAP's AXI-AP and don't halt Linux.
- After Linux boot, both R5 cores show **No Power**. PWR_STATE `0xffd80100` = `0x00DF008F`: R5_0, R5_1 (bits 10–11) and all TCM banks (12–15) off. Linux's `zynqmp_pm_init_finalize` probably powers down unrequested nodes (**verify**).

## Step 2b: Power-up and AXI isolation

- `0xF400` to REQ_PWRUP_INT_EN/TRIG (`0xffd80118`/`0xffd80120`) powers the RPU (bit 10) and TCM banks (12–15). Needed after every Linux boot. It bypasses the PM framework; fine for JTAG.
- The raw power-up leaves the RPU AXI isolation (AIB) on: every R5 access outside the RPU gets SLVERR. LPD_SLCR ISO_AIBAXI_REQ `0xff413030` bits 16–19 (rpum0/1, rpus0/1); ACK at `0xff413040`. Clearing REQ removes it. Remoteproc's PM wake appears to remove it: UART1 output works under remoteproc (**verify** ISO_AIBAXI_REQ).
- Freshly powered TCM has invalid ECC, and `dow` writes only the ELF sections: `ARMV7R_ZERO_UNUSED_RAM` zeroes the rest.

---

## Step 3: JTAG load and run

- **First run:** silent. A breakpoint on `arm_dataabort` showed DFAR `0xff13000c` (TTC2 Counter_Control_1, first write in `up_timer_initialize()`), DFSR `0x1808` (synchronous external abort, write, AXI SLVERR; **verify** decode against the R5 TRM). `_assert` couldn't print because UART1 was blocked too. XPPU was off (`0xff980000` bit 0 = 0). Cause: the AIB isolation (step 2b).
- **After clearing the isolation:** ostest runs on UART1 and exits with status 0 in about 2 min (about 115 s in QEMU), so TTC2 ticks at the right rate.
- `mwr 0xff9a0100 0x1`: a write, not a mask, because RPU_0_CFG reads `0x04`; masking VINITHI would leave nCPUHALT=0.
- `rst -processor` leaves the core halted; `-clear-registers` only helps the debugger and doesn't replace `ARMV7R_LOCKSTEP_REGINIT`.
- xsdb's `couldn't open ...` messages are harmless: the debug info points to WSL source paths.
- **Verify:** whether `rst -processor` releases RST_LPD_TOP bit 4. It wasn't needed on the board.

## Step 4: Diagnosis

`rrd cpsr` mode: 0x17 abort, 0x1b undefined, 0x1f SYS.

| What you see | Meaning |
|---|---|
| Data abort, DFSR `0x1808`, DFAR outside the RPU | AIB isolation still on: step 2b |
| PC in `arm_lowputc`, looping on the status register | UART1 not usable: check RST_LPD_IOU2 bit 2 |
| Abort on 0xFF13xxxx (TTC2) or 0xFF01xxxx (UART1) | TTC2 in reset, or XPPU denying the R5 |
| PC in the idle loop, no ostest progress | Tick not firing: check TTC2 and the GIC |
| `mrd 0x0` doesn't match `objdump -d nuttx` | `dow` missed TCM: check VINITHI and TCM_COMB |

---

## Step 5: Load through Linux remoteproc

- The board uses the legacy driver `zynqmp_r5_remoteproc.c` (compatible `xlnx,zynqmp-r5-remoteproc`). `xlnx_r5_remoteproc.c` doesn't bind and ignores `sram`.
- **How it maps memory:**
  - Each `sram` node becomes one carveout at its address with the high bits masked (`0xffe00000` → `0x0`). Only bases `0x0` and `0x20000` are accepted.
  - Each `memory-region` becomes a carveout at its physical address. A segment linked at `0x3c000000` would load into `rproc0`.
  - Each `PT_LOAD` segment must fit inside **one** carveout (`remoteproc_core.c:205–226`).
- The `shared` ELF is one LOAD segment from `0x0` crossing `0x20000`, so it fit in neither 128 KB `tcm_a`/`tcm_b` node. Hence the single 256 KB `sram` node (step 5.1), which also requests all four TCM power domains.
- DDR-only firmware isn't possible: the R5 boots from `0x0` (TCM) or `0xFFFF0000` (OCM), so at least the vectors must be in TCM.
- Start: `zynqmp_pm_request_wake`, TCM boot (entry `0x40`). The driver doesn't zero the TCM.
- **Result:** ostest on UART1 with no xsdb step; `state` reads `running`; stop/start reruns it.
- **Gotcha:** `echo start` reporting `No such file or directory` is `-ENOENT` from `rproc_boot()`. The kernel logs `request_firmware failed`, `Boot failed: -2`. Causes seen:
  - a full path written to `firmware`; it takes only the file name
  - `/lib/firmware/nuttx-r5.elf` missing after a rootfs replacement

---

## Step 6: Calibration

- `kv260-rpu:calib`: `calib_udelay` with float printf (`INIT_STACKSIZE=4096`).
- Measured: 31.496 ns per loop (R² = 1.0000) → 31,749.82 loops per ms → **`CONFIG_BOARD_LOOPSPERMSEC=31750`**, set in `shared`, `nsh` and `rpmsg`. `qemu` and `calib` keep 100000.
- About 17 cycles per loop if the R5 runs at 533 MHz (**verify** the clock).

---

## Step 7: RPMsg link and echo

Linux is the master, NuttX (rptun) the remote. The DT already had the vring/buffer carve-outs and the IPI mailbox (`zynqmp_ipi1`: local IPI7, remote IPI1 = RPU0); no PetaLinux change was needed.

**Linux side**
- Kernel: `RPMSG_VIRTIO=y`, `RPMSG_NS=y`, `RPMSG_CHAR=m`, `RPMSG_CTRL=m`, buffer size 512, `ZYNQMP_IPI_MBOX=y`. The user fragment sets `RPMSG_CHAR=y`/`RPMSG_CTRL=y` but the build has them as modules (**verify** why).
- Start order: Linux starts the R5 **before** setting the vdev to DRIVER_OK. rptun retries every second until it sees DRIVER_OK.
- Kicks: Linux → R5 through ATF on the `tx` mailbox; it polls until the R5 clears its ISR bit. R5 → Linux: Linux scans every vring, so the R5 writes nothing to the IPI buffers.
- `rpmsg_char` binds only to `"rpmsg-raw"` and doesn't autoload. `rpmsg_tty` binds to `"rpmsg-tty"`, autoloads and creates `/dev/ttyRPMSGn`.

**NuttX side**
- Resource table in TCM (never cached), `.resource_table`, `0x108` bytes: one vdev, id 7, features NS only, vrings at `0x3e000000`/`0x3e004000`, align `0x1000`, 256 buffers each.
- MPU region: `0x3e000000`, 1 MiB, Normal non-cacheable, non-shareable (shareable makes LDREX/STREX abort on the R5), XN. `arm_head.S` otherwise maps DDR write-back cacheable. **Verify** 16 regions in `MPUIR`.
- IPI (UG1087): RPU0 channel `0xff310000`; `TRIG 0x00`, `ISR 0x10` (W1C), `IER 0x18`, `IDR 0x1c`; IPI7 mask bit 24. Kick = DSB + write bit 24 to `TRIG`. IRQ 65 acks `ISR` and runs the rptun callback on HPWORK (it takes mutexes). Empty `panic` op, so a panic doesn't wait 5 s for a Linux ACK.
- **Gotcha:** an object in `libarch.a` is linked only when something references it, so the table section was empty until rptun's `get_resource()` used it.
- **Gotcha:** `configure.sh` without `-E` keeps the old `.config`.

**On the board**
- `rpmsg host is online`; debugfs vdev Status `0x7` (DRIVER_OK).
- Echo service (`CONFIG_KV260_RPU_RPMSG_ECHO`, endpoint `"rpmsg-raw"`): `hello` echoed; 10,000 random round trips (1–496 B) matched; works again after stop/start.
- `shared` with echo: TCM 175,680 B (67 %).

---

## Step 8: NSH over RPMsg

**Config (`kv260-rpu:rpmsg`)**
- `uart_rpmsg_raw` sends raw bytes on the fixed endpoint `"rpmsg-tty"`, which Linux `rpmsg_tty` understands. `uart_rpmsg` adds a NuttX header and doesn't work with Linux.
- `rpmsg_serialrawinit()` calls `uart_rpmsg_raw_init("linux", "RPMSG0", 4096, true)` from `drivers_initialize()`, so `/dev/console` exists before the init task opens it.
- **Console:** `NO_SERIAL_CONSOLE` is required, because `UART1_SERIAL_CONSOLE` (and `OTHER_SERIAL_CONSOLE`) select `SERIAL_CONSOLE`. The build fails with `More than one console driver selected` when that is set together with `RPMSG_UART_RAW_CONSOLE` (`drivers_initialize.c:73–78`).
- **Syslog and panics stay on UART1:** with no UART console, `zynqmp_rpu_lowputc.c` uses the first enabled `ZYNQMP_RPU_UARTn` for `up_putc`. `SYSLOG_DEFAULT` goes through `up_putc`. `SYSLOG_CONSOLE` and `CONSOLE_SYSLOG` must stay off.
- The NuttX endpoint learns Linux's address only from the first received message. Until then, output waits in the 4 KiB TX buffer, which is why the prompt appears only after Enter.

**TCM**
- The linker prints usage (`--print-memory-usage`, GCC ≥ 12). Its "Used Size" equals `_ebss`.
- With ostest: 257,808 B (98.35 %), 4,336 B heap. Too little: about 18 KiB is needed at boot (rptun 4 KiB, hpwork 2 KiB, RPMsg UART buffers 8.2 KiB, NSH 4 KiB).
- **Without ostest:** `tcm: 170016 B, 64.86%`, about 92 KB heap. ostest is about 88 KB; NSH, builtin and procfs about 82 KB. `shared` keeps ostest.
- Build warnings: `g_console_config` unused (`zynqmp_rpu_lowputc.c:115`); `zynqmp_rpu_error_handler` unused (`zynqmp_rpu_irq.c:50`).

**On the board**
- Kernel rebuilt with `RPMSG_TTY=m`.
- `nsh>` on `/dev/ttyRPMSG0`.
- `help` works; `free` shows about 92 KB heap; `ps` shows the rpmsg task. `ostest` isn't in `rpmsg`.
- Stop/start: `/dev/ttyRPMSG0` goes away and comes back.
- Kernel messages also appear on UART1 (shared with the Linux console); `dmesg -n 1` keeps them off.
