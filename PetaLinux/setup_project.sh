#!/usr/bin/env bash
# Point the PetaLinux project at this checkout: import the hardware description
# from hw_sdt_openamp and regenerate the configs with this location's paths.
# Run after cloning or moving the workspace, before petalinux-build.

set -eo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
PROJECT_DIR="$SCRIPT_DIR/xilinx-kv260-starterkit-2024.2"
HW_DIR="$SCRIPT_DIR/hw_sdt_openamp"
PETALINUX_SETTINGS="${PETALINUX_SETTINGS:-/opt/pkg/petalinux/settings.sh}"

[[ -f "$HW_DIR/system-top.dts" ]] || { echo "missing $HW_DIR/system-top.dts" >&2; exit 1; }

if ! command -v petalinux-config >/dev/null; then
    [[ -f "$PETALINUX_SETTINGS" ]] || { echo "PetaLinux settings not found: $PETALINUX_SETTINGS (set PETALINUX_SETTINGS)" >&2; exit 1; }
    # shellcheck source=/dev/null
    source "$PETALINUX_SETTINGS" >/dev/null
fi

cd "$PROJECT_DIR"
petalinux-config --get-hw-description "$HW_DIR" --silentconfig

echo "Hardware description: $(grep '^HARDWARE_PATH=' .petalinux/metadata | cut -d= -f2)"
