# KV260 RPU — Board Bring-up Steps

Run NuttX on R5_0 (lockstep) while Linux runs on the A53s: first over JTAG, then loaded by Linux remoteproc, then with an RPMsg link and an NSH console. Explanations and recorded values are in `board_bringup_results.md`.

Configs (`boards/arm/zynqmp-rpu/kv260-rpu/configs/`):

| Config | Use |
|---|---|
| `qemu` | Xilinx QEMU |
| `shared` | ostest, output on UART1 (shared with Linux), RPMsg echo service |
| `calib` | `calib_udelay`, output on UART1 |
| `rpmsg` | NSH on the RPMsg console, syslog on UART1 |

Build any config with:

```sh
make distclean && ./tools/configure.sh -l kv260-rpu:<config> && make -j$(nproc)
```

---

## Step 0: QEMU check

Build `kv260-rpu:qemu` and run `scripts/run-qemu.sh`. Check: `sleep 10` takes 10 s, `ostest` exits with status 0.

---

## Step 1: Check the board from Linux (read-only)

1. Plug J4 into the machine that runs xsdb (`jtag_setup.md`). Open UART1 at 115200 8N1.
2. Boot Linux from the SD card. Log in over SSH; leave the serial console logged out.
3. As root, run and record:

```sh
devmem 0xff9a0000      # RPU_GLBL_CNTL: 0x50 = lockstep
devmem 0xff9a0100      # RPU_0_CFG
devmem 0xff5e023c      # RST_LPD_TOP
devmem 0xff5e0238      # RST_LPD_IOU2: stop if bit 13 (TTC2) is 1
grep -i ttc /proc/interrupts                                       # no lines
mount -t debugfs none /sys/kernel/debug                            # if not mounted
grep -Ei "lpd_lsbus|uart1|rpu" /sys/kernel/debug/clk/clk_summary   # lpd_lsbus = 100 MHz
```

---

## Step 2: Read-only xsdb session

```tcl
connect
targets                 ;# Cortex-R5 #0 "No Power": do step 2b
targets -set -nocase -filter {name =~ "*APU*"}
mrd 0xff9a0000          ;# must match step 1
mrd 0xffd80100          ;# PWR_STATE: bits 10-15 = R5_0, R5_1, TCM banks
```

Check that the SSH session still responds.

---

## Step 2b: Power up the RPU and TCM (after every Linux boot)

```tcl
targets -set -nocase -filter {name =~ "*APU*"}
mwr 0xffd80118 0xF400   ;# REQ_PWRUP_INT_EN: RPU + TCM0A/0B/1A/1B
mwr 0xffd80120 0xF400   ;# REQ_PWRUP_TRIG
mrd 0xffd80110          ;# REQ_PWRUP_STATUS: 0
mrd 0xffd80100          ;# PWR_STATE: bits 10-15 set

# Remove the RPU AXI isolation
mwr 0xff413030 [expr {[mrd -value 0xff413030] & ~0x000F0000}]
mrd 0xff413040          ;# ISO_AIBAXI_ACK: bits 16-19 = 0
```

---

## Step 3: Load and run over JTAG

1. Build `kv260-rpu:shared`. Copy `nuttx` to the xsdb machine, e.g. `scp nuttx <user>@<ubuntu-ip>:kv260/nuttx`.
2. In xsdb:

```tcl
targets -set -nocase -filter {name =~ "*APU*"}
# mwr 0xff9a0000 0x50                                     ;# only if step 1 showed split mode
mwr 0xff9a0100 0x1
# mwr 0xff5e023c [expr {[mrd -value 0xff5e023c] & ~0x10}] ;# only if dow/con fails

targets -set -nocase -filter {name =~ "*R5*#0"}
rst -processor -clear-registers
dow <elf>
con
```

> **Never** use plain `rst` or `rst -system`: they reset the whole board. Always `rst -processor -clear-registers` before `dow`.

3. Check: ostest prints on UART1 within a second and ends with `ostest_main: Exiting with status 0` after about 2 minutes. To rerun: `rst -processor -clear-registers`, `dow`, `con`.

---

## Step 4: If nothing appears, or it stops

1. After `dow`, before `con`, on Cortex-R5 #0:

```tcl
bpadd -addr &arm_dataabort
bpadd -addr &arm_prefetchabort
bpadd -addr &arm_undefinedinsn
bpadd -addr &_assert
con
```

2. On `arm_dataabort`: `bt`, `rrd r1` (DFAR), `rrd r2` (DFSR).
3. Otherwise: `stop`, `rrd pc`, `rrd cpsr`, `rrd`, `mrd 0x0 8`, then in WSL `arm-none-eabi-addr2line -f -e nuttx 0x<pc>`.
4. Match the result against the diagnosis table in `board_bringup_results.md`.

---

## Step 5: Load through Linux remoteproc

5.1. In `system-user.dtsi`, replace `tcm_a` and `tcm_b` with one 256 KB `mmio-sram` node at `0xffe00000` (`reg` size `0x40000`, power domains 15, 16, 17, 18), referenced by `sram` in `r5f_0`. Rebuild PetaLinux and boot it.

5.2. Load and start (the `firmware` file takes the bare file name):

```sh
sudo cp nuttx /lib/firmware/nuttx-r5.elf
echo nuttx-r5.elf | sudo tee /sys/class/remoteproc/remoteproc0/firmware
echo start        | sudo tee /sys/class/remoteproc/remoteproc0/state
```

5.3. Check: `cat /sys/class/remoteproc/remoteproc0/state` reads `running`, `dmesg | tail` shows no errors, ostest prints on UART1 and exits with status 0.

5.4. Stop and restart:

```sh
echo stop  | sudo tee /sys/class/remoteproc/remoteproc0/state
echo start | sudo tee /sys/class/remoteproc/remoteproc0/state
```

---

## Step 6: Calibrate `CONFIG_BOARD_LOOPSPERMSEC`

1. Build `kv260-rpu:calib`, load it with 5.2.
2. Put the measured value in the `shared`, `nsh` and `rpmsg` defconfigs.

---

## Step 7: RPMsg link and echo test

1. Build `kv260-rpu:shared`. Check: `arm-none-eabi-readelf -S nuttx` shows `.resource_table` as `PROGBITS`, size `0x108`; `readelf -l` shows one LOAD segment.
2. Load and start with 5.2. Check:

```sh
dmesg | grep -iE 'remoteproc|rpmsg|virtio'   # "rpmsg host is online", no "no resource table found."
sudo mount -t debugfs none /sys/kernel/debug 2>/dev/null
sudo cat /sys/kernel/debug/remoteproc/remoteproc0/resource_table   # vdev Status 0x7
ls /sys/bus/rpmsg/devices/      # virtio0.rpmsg_ctrl.0.0, virtio0.rpmsg_ns.53.53, virtio0.rpmsg-raw.-1.1024
dmesg | grep 'creating channel' # creating channel rpmsg-raw addr 0x400
```

3. Echo once:

```sh
sudo modprobe rpmsg_char
sudo modprobe rpmsg_ctrl
ls /dev/rpmsg*                  # rpmsg0, rpmsg_ctrl0
sudo sh -c 'exec 3<>/dev/rpmsg0; printf hello >&3; dd bs=512 count=1 <&3 2>/dev/null; echo'   # hello
```

4. Stress test (prints `ok`):

```sh
cat > ~/rpmsg_echo.py <<'EOF'
import os, random
fd = os.open("/dev/rpmsg0", os.O_RDWR)
for i in range(10000):
    msg = os.urandom(random.randint(1, 496))
    os.write(fd, msg)
    assert os.read(fd, 512) == msg, f"mismatch at {i}"
print("ok")
EOF
sudo python3 ~/rpmsg_echo.py
```

5. Stop and restart with 5.4. Check that `/dev/rpmsgN` comes back and the echo in 3 works on it.

---

## Step 8: NSH console over RPMsg

1. In the PetaLinux project, `petalinux-config -c kernel`: Device Drivers → Character devices → RPMSG tty driver (`CONFIG_RPMSG_TTY`) = M. Rebuild PetaLinux and boot it.
2. Check: `zcat /proc/config.gz | grep RPMSG_TTY` shows `=m`, and `modinfo rpmsg_tty` finds the module.
3. Build `kv260-rpu:rpmsg`. Check: one LOAD segment, and the linker's `tcm:` line leaves room for the heap (about 92 KB free at 65 % used).
4. Load and start with 5.2. After a rootfs change, copy the ELF to `/lib/firmware` again. Check:

```sh
dmesg | grep 'creating channel'   # creating channel rpmsg-tty addr 0x4xx
lsmod | grep rpmsg_tty            # loaded automatically
ls /dev/ttyRPMSG*                 # ttyRPMSG0
```

5. `sudo picocom /dev/ttyRPMSG0` (or `screen` / busybox `microcom`). Press Enter: nothing appears before Linux has sent the first byte. Check: `nsh>` prompt.
6. In nsh: `help`, `free`, `ps` (shows `rptun` and `hpwork`), `ostest` exits with status 0. UART1 shows only syslog output (`sudo dmesg -n 1` keeps kernel messages off it).
7. Stop and restart with 5.4. Check that `/dev/ttyRPMSG0` goes away on stop, comes back on start, and 5 works again.
