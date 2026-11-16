#!/usr/bin/env bash
# Runs the ts_capture testbench with Windows Vivado 2024.2 xsim from WSL.
set -euo pipefail

VIVADO_BIN='C:\Xilinx\Vivado\2024.2\bin'
WIN_TEMP=$(cmd.exe /c "echo %TEMP%" 2>/dev/null | tr -d '\r')
WIN_DIR="$WIN_TEMP\\ts_capture_sim"
WSL_DIR=$(wslpath "$WIN_DIR")
HERE=$(cd "$(dirname "$0")" && pwd)

rm -rf "$WSL_DIR"
mkdir -p "$WSL_DIR"
cp "$HERE/../rtl/ts_capture.v" "$HERE/tb_ts_capture.sv" "$WSL_DIR/"

cd "$WSL_DIR"
cmd.exe /c "cd /d $WIN_DIR && \
$VIVADO_BIN\\xvlog.bat ts_capture.v && \
$VIVADO_BIN\\xvlog.bat -sv tb_ts_capture.sv && \
$VIVADO_BIN\\xelab.bat -L xpm -debug typical tb_ts_capture -s tb && \
$VIVADO_BIN\\xsim.bat tb -R" 2>&1 | tr -d '\r' | tee sim.log

grep -q "ALL TESTS PASSED" sim.log
