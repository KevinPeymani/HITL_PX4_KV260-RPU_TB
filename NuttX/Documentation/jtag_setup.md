# KV260 JTAG Setup

How to get an xsdb session to the KV260 over the J4 micro-USB (FTDI: JTAG plus the UART COM ports). Use the same tool version, 2024.1, on every machine. After setup, continue with Step 2 of `board_bringup_steps.md`.

- **Setup A: Ubuntu only.** The board is plugged into the Ubuntu machine, which runs both hw_server and xsdb.
- **Setup B: Windows.** The board is plugged into the Windows PC, which runs both hw_server and xsdb.

Items marked **verify** haven't been checked yet.

---

## Setup A: Ubuntu only

1. Install Vivado Lab Edition 2024.1 (**verify** that it ships `xsdb`; otherwise install Vivado or Vitis 2024.1).
2. Plug J4 into the Ubuntu machine and check that the FTDI chip is visible:

```sh
lsusb | grep -i 0403
ls /dev/ttyUSB*
```

3. If the `ttyUSB*` ports appear and then vanish: `sudo apt remove brltty`.
4. Install the cable drivers (udev rules), then unplug and replug J4:

```sh
cd <install_dir>/data/xicom/cable_drivers/lin64/install_script/install_drivers
sudo ./install_drivers
```

5. Allow your user to open the serial ports, then log out and back in:

```sh
sudo usermod -aG dialout $USER
```

6. Open the UART1 console. It's the `ttyUSB*` port that shows the Linux login prompt, usually `ttyUSB1` (**verify**). Leave it logged out.

```sh
sudo apt install picocom
picocom -b 115200 /dev/ttyUSB1     # quit: Ctrl-A then Ctrl-X
```

7. Start xsdb and connect:

```sh
source <install_dir>/settings64.sh
xsdb
```

```tcl
connect
jtag targets
targets
```

8. In Step 3, copy `nuttx` to the Ubuntu machine and load it with a Linux path: `dow /home/<you>/kv260/nuttx`.

---

## Setup B: Windows

1. Plug J4 into the Windows PC. Device Manager should show the KV260's COM ports.
2. If `connect` finds no cable, rerun the cable driver installer under `C:\Xilinx\Vivado\2024.1\data\xicom\cable_drivers\nt64\` as administrator (**verify** the script name).
3. Open a serial terminal (for example PuTTY) on the UART1 COM port at 115200 8N1. Leave it logged out.
4. Close Vivado's Hardware Manager.
5. In a Windows terminal, start `C:\Xilinx\Vivado\2024.1\bin\xsdb.bat` and connect:

```tcl
connect
jtag targets
targets
```

6. In Step 3, load the ELF with a Windows path: `dow C:/kv260/nuttx`.

---

## If `connect` or `jtag targets` finds nothing

| Symptom | Check |
|---|---|
| No cable | Cable drivers / udev rules not installed, or J4 not replugged after installing them |
| Cable found, empty chain | Board not powered, or another hw_server or Vivado Hardware Manager already owns the cable |