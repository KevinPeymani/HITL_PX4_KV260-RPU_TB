#!/bin/bash
# build_sd.sh - Build PetaLinux, package the WIC image and flash it to an SD card (KV260)
#
#   build:   petalinux-build                -> images/linux/{Image,system.dtb,...}
#   package: petalinux-package --wic        -> images/linux/petalinux-sdimage.wic
#   flash:   wipe the SD card and write the WIC image onto it
#
#   Steps are picked with flags and always run in the order above. flash can
#   optionally target an SD card plugged into a remote computer (--remote):
#   the image is streamed over SSH and written there.
#
# Run as your normal user (petalinux-build/-package refuse to run as root);
# flash uses sudo for the disk operations (on the remote computer when
# --remote is used; the SSH password is reused for sudo there).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"
PROJECT_DIR="$REPO_DIR/PetaLinux/xilinx-kv260-starterkit-2024.2"
IMAGES_DIR="$PROJECT_DIR/images/linux"
WIC_IMAGE="$IMAGES_DIR/petalinux-sdimage.wic"
PETALINUX_SETTINGS="${PETALINUX_SETTINGS:-/opt/pkg/petalinux/settings.sh}"
BOOTFILES="ramdisk.cpio.gz.u-boot boot.scr Image system.dtb"
SSH_OPTS=(-o StrictHostKeyChecking=accept-new -o ConnectTimeout=10)

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
RED='\033[0;31m'; YELLOW='\033[1;33m'; GREEN='\033[0;32m'; NC='\033[0m'
info()  { echo -e "${GREEN}[INFO]${NC}  $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
die()   { echo -e "${RED}[ERROR]${NC} $*" >&2; exit 1; }

# Single-quote a string for a POSIX shell
sq() { local s=${1//\'/\'\\\'\'}; printf "'%s'" "$s"; }

# Run a shell command on the flash target (this machine, or REMOTE over SSH)
on_target() {
    if [[ -n "$REMOTE" ]]; then
        sshpass -e ssh -n "${SSH_OPTS[@]}" "$REMOTE" "sh -c $(sq "$1")"
    else
        sh -c "$1"
    fi
}

# Run a shell command as root on the flash target. Its stdin is passed on
# to the command. Remotely, the password is sent as the first line of the
# stream and handed to sudo through a temporary SUDO_ASKPASS helper, so it
# works without a TTY and without relying on sudo's credential cache (which
# is keyed to the parent PID over non-interactive SSH).
on_target_root() {
    if [[ -n "$REMOTE" ]]; then
        local wrapper
        # shellcheck disable=SC2016  # expanded on the remote side
        wrapper='IFS= read -r SUDO_PW
export SUDO_PW
a=$(mktemp "${HOME:-/tmp}/.sudo-askpass.XXXXXX") || exit 1
trap "rm -f \"$a\"" EXIT
cat >"$a" <<"EOF"
#!/bin/sh
printf "%s\n" "$SUDO_PW"
EOF
chmod 700 "$a"
SUDO_ASKPASS=$a sudo -A -p "" sh -c '"$(sq "$1")"' || { rc=$?; echo "remote sudo command failed (exit $rc)" >&2; exit $rc; }'
        { printf '%s\n' "$SSHPASS"; cat; } \
            | sshpass -e ssh -C "${SSH_OPTS[@]}" "$REMOTE" "sh -c $(sq "$wrapper")"
    else
        sudo sh -c "$1"
    fi
}

target_name() { [[ -n "$REMOTE" ]] && echo "$REMOTE" || echo "this machine"; }

usage() {
    cat <<EOF
Usage: $0 [steps] [options]

Steps (any combination; they always run in this order):
  -b, --build               Build the PetaLinux project (petalinux-build)
  -p, --package             Package the WIC image (petalinux-package --wic)
  -f, --flash[=DEVICE]      Wipe the SD card and write the WIC image.
                            DEVICE (e.g. /dev/sdf) is prompted for if omitted.
  -a, --all                 Same as --build --package --flash

Options:
  -r, --remote[=USER@HOST]  Flash the SD card plugged into a remote computer
                            over SSH (implies --flash). USER@HOST is prompted
                            for if omitted; the password is always prompted for.
  -h, --help                Show this help

With no step given, each step is offered as a yes/no question.

Examples:
  $0 --build --package
  $0 -pf /dev/sdf                    (short flags can be grouped)
  $0 --flash=/dev/sdf --remote=kevin@192.168.1.20
  $0 --all --remote
EOF
}

# Source the PetaLinux environment unless it is already loaded
petalinux_env() {
    [[ $EUID -ne 0 ]] || die "PetaLinux tools refuse to run as root; run as your normal user."
    command -v petalinux-build >/dev/null 2>&1 && return
    [[ -f "$PETALINUX_SETTINGS" ]] || die "PetaLinux settings not found: $PETALINUX_SETTINGS"
    info "Sourcing $PETALINUX_SETTINGS ..."
    set +u
    # shellcheck disable=SC1090
    source "$PETALINUX_SETTINGS" >/dev/null
    set -u
}

# ---------------------------------------------------------------------------
# Step: build
# ---------------------------------------------------------------------------
step_build() {
    petalinux_env
    info "Build: running petalinux-build in $PROJECT_DIR ..."
    (cd "$PROJECT_DIR" && petalinux-build) || die "Petalinux build failed. Logs : $PROJECT_DIR/build/build.log"
    info "Build complete."
}

# ---------------------------------------------------------------------------
# Step: package
# ---------------------------------------------------------------------------
step_package() {
    petalinux_env

    for f in $BOOTFILES; do
        [[ -f "$IMAGES_DIR/$f" ]] || die "Missing boot file: $IMAGES_DIR/$f (run with --build first?)"
    done

    info "Package: creating WIC image ..."
    (cd "$PROJECT_DIR" && petalinux-package --wic --bootfiles "$BOOTFILES")

    [[ -f "$WIC_IMAGE" ]] || die "Packaging finished but $WIC_IMAGE was not found."
    info "Package complete: $WIC_IMAGE"
}

# ---------------------------------------------------------------------------
# Step: flash (wipe SD card and write image)
# ---------------------------------------------------------------------------
step_flash() {
    local dev="$1"
    local d; d="$(sq "$dev")"

    [[ -f "$WIC_IMAGE" ]] || die "WIC image not found: $WIC_IMAGE (run with --package first)."
    on_target "test -b $d" || die "$dev is not a block device on $(target_name)."
    [[ "$(on_target "lsblk -dno TYPE $d")" == "disk" ]] || die "$dev is a partition; pass the whole disk (e.g. /dev/sdf)."

    # Refuse disks holding system mounts
    if on_target "lsblk -nro MOUNTPOINT $d" | grep -qE '^/$|^/boot|^/home|^\[SWAP\]'; then
        die "$dev has system mountpoints on $(target_name) — refusing to touch it."
    fi

    echo ""
    on_target "lsblk -o NAME,SIZE,MODEL,TRAN,RM,MOUNTPOINT $d"
    echo ""
    warn "ALL DATA on $dev ($(target_name)) will be ERASED."
    read -r -p "Type the device path again to confirm: " confirm
    [[ "$confirm" == "$dev" ]] || die "Device paths do not match — aborting."

    if [[ -n "$REMOTE" ]]; then
        info "Checking sudo access on $REMOTE ..."
        on_target_root "true" </dev/null || die "Cannot run sudo on $REMOTE."
    fi

    info "Unmounting any mounted partitions on $dev ..."
    on_target_root "for p in \$(lsblk -nrpo NAME $d | tail -n +2); do umount \"\$p\" 2>/dev/null || true; done" </dev/null

    info "Wiping existing signatures and partition table on $dev ..."
    on_target_root "for p in \$(lsblk -nrpo NAME $d | tail -n +2); do wipefs -a \"\$p\" >/dev/null 2>&1 || true; done
wipefs -a $d
dd if=/dev/zero of=$d bs=1M count=16 conv=fsync status=none" </dev/null

    if [[ -n "$REMOTE" ]]; then
        info "Streaming $WIC_IMAGE -> $REMOTE:$dev ..."
        on_target_root "dd of=$d bs=4M iflag=fullblock conv=fsync status=progress && sync" <"$WIC_IMAGE"
    else
        info "Writing $WIC_IMAGE -> $dev ..."
        sudo dd if="$WIC_IMAGE" of="$dev" bs=4M conv=fsync status=progress
        sync
    fi

    on_target_root "partprobe $d 2>/dev/null || true" </dev/null
    sleep 1
    info "Flash complete. Partitions on $dev ($(target_name)):"
    on_target "lsblk -o NAME,SIZE,FSTYPE,LABEL $d"
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
DO_BUILD=0
DO_PACKAGE=0
DO_FLASH=0
SD_DEV=""
REMOTE=""
USE_REMOTE=0

# Ask a yes/no question; the default answer is no
ask() { local a; read -r -p "$1 [y/N]: " a; [[ "$a" == [yY]* ]]; }

opts=$(getopt -o bpf::ar::h -l build,package,flash::,all,remote::,help -n "$(basename "$0")" -- "$@") \
    || { usage; exit 1; }
eval set -- "$opts"
while true; do
    case "$1" in
        -b|--build)   DO_BUILD=1 ;;
        -p|--package) DO_PACKAGE=1 ;;
        -f|--flash)   DO_FLASH=1; SD_DEV="$2"; shift ;;
        -a|--all)     DO_BUILD=1; DO_PACKAGE=1; DO_FLASH=1 ;;
        -r|--remote)  DO_FLASH=1; USE_REMOTE=1; REMOTE="$2"; shift ;;
        -h|--help)    usage; exit 0 ;;
        --)           shift; break ;;
    esac
    shift
done

# A bare trailing argument is the SD card device (lets "-f /dev/sdf" work)
if [[ $# -gt 0 ]]; then
    [[ $DO_FLASH -eq 1 && -z "$SD_DEV" && $# -eq 1 ]] || { usage; die "Unexpected argument(s): $*"; }
    SD_DEV="$1"
fi

if (( DO_BUILD + DO_PACKAGE + DO_FLASH == 0 )); then
    ask "Build the PetaLinux project?"          && DO_BUILD=1
    ask "Package the WIC image?"                && DO_PACKAGE=1
    if ask "Flash the SD card?"; then
        DO_FLASH=1
        ask "Is the SD card on a remote computer (SSH)?" && USE_REMOTE=1
    fi
    (( DO_BUILD + DO_PACKAGE + DO_FLASH > 0 )) || die "No step selected."
fi

if [[ $USE_REMOTE -eq 1 ]]; then
    command -v sshpass >/dev/null 2>&1 || die "sshpass is not installed (sudo apt install sshpass)."
    if [[ -z "$REMOTE" ]]; then
        read -r -p "Remote computer (user@address): " REMOTE
    fi
    [[ "$REMOTE" == *@* ]] || die "Remote must be given as user@address (got '$REMOTE')."
    read -r -s -p "Password for $REMOTE: " SSHPASS
    echo ""
    export SSHPASS
    info "Connecting to $REMOTE ..."
    on_target "true" || die "Cannot connect to $REMOTE over SSH."
fi

# Pick the device up front so a long build is not followed by a prompt
if [[ $DO_FLASH -eq 1 && -z "$SD_DEV" ]]; then
    echo ""
    on_target "lsblk -d -o NAME,SIZE,MODEL,TRAN,RM"
    read -r -p "SD card device on $(target_name) (e.g. /dev/sdf): " SD_DEV
    [[ -n "$SD_DEV" ]] || die "No SD card device specified."
fi

[[ $DO_BUILD   -eq 1 ]] && step_build
[[ $DO_PACKAGE -eq 1 ]] && step_package
[[ $DO_FLASH   -eq 1 ]] && step_flash "$SD_DEV"

info "Done."
