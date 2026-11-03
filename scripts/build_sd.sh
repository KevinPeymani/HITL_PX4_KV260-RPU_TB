#!/bin/bash
# build_sd.sh - Package PetaLinux WIC image and flash it to an SD card (KV260)
#
#   Stage 1: petalinux-package --wic  -> images/linux/petalinux-sdimage.wic
#   Stage 2: wipe the SD card and write the WIC image onto it
#
#   Stage 2 can optionally run against an SD card plugged into a remote
#   computer (--remote): the image is streamed over SSH and written there.
#
# Run as your normal user (petalinux-package refuses to run as root);
# stage 2 uses sudo for the disk operations (on the remote computer when
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

# Run a shell command on the stage 2 target (this machine, or REMOTE over SSH)
on_target() {
    if [[ -n "$REMOTE" ]]; then
        sshpass -e ssh -n "${SSH_OPTS[@]}" "$REMOTE" "sh -c $(sq "$1")"
    else
        sh -c "$1"
    fi
}

# Run a shell command as root on the stage 2 target. Its stdin is passed on
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
Usage: $0 <stage> [sd_device] [options]

Stages:
  1        Package the WIC image (petalinux-package --wic)
  2        Wipe the SD card and write the WIC image   (needs sd_device)
  all      Run stage 1, then stage 2                  (needs sd_device)

Options:
  --remote[=USER@HOST]  Stage 2: write the SD card plugged into a remote
                        computer over SSH. USER@HOST is prompted for if
                        omitted; the password is always prompted for.

With no arguments, an interactive menu is shown.

Examples:
  $0 1
  $0 2 /dev/sdf
  $0 2 /dev/sdf --remote=kevin@192.168.1.20
  $0 all /dev/sdf
  $0 all --remote
EOF
}

# ---------------------------------------------------------------------------
# Stage 1: package
# ---------------------------------------------------------------------------
stage1() {
    [[ $EUID -ne 0 ]] || die "Stage 1 must not run as root (petalinux-package refuses it)."

    if ! command -v petalinux-package >/dev/null 2>&1; then
        [[ -f "$PETALINUX_SETTINGS" ]] || die "PetaLinux settings not found: $PETALINUX_SETTINGS"
        info "Sourcing $PETALINUX_SETTINGS ..."
        set +u
        # shellcheck disable=SC1090
        source "$PETALINUX_SETTINGS" >/dev/null
        set -u
    fi

    for f in $BOOTFILES; do
        [[ -f "$IMAGES_DIR/$f" ]] || die "Missing boot file: $IMAGES_DIR/$f (run petalinux-build first?)"
    done

    info "Stage 1: packaging WIC image ..."
    (cd "$PROJECT_DIR" && petalinux-package --wic --bootfiles "$BOOTFILES")

    [[ -f "$WIC_IMAGE" ]] || die "Packaging finished but $WIC_IMAGE was not found."
    info "Stage 1 complete: $WIC_IMAGE"
}

# ---------------------------------------------------------------------------
# Stage 2: wipe SD card and write image
# ---------------------------------------------------------------------------
stage2() {
    local dev="$1"
    local d; d="$(sq "$dev")"

    [[ -f "$WIC_IMAGE" ]] || die "WIC image not found: $WIC_IMAGE (run stage 1 first)."
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
    info "Stage 2 complete. Partitions on $dev ($(target_name)):"
    on_target "lsblk -o NAME,SIZE,FSTYPE,LABEL $d"
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
STAGE=""
SD_DEV=""
REMOTE=""
USE_REMOTE=0

positional=()
while [[ $# -gt 0 ]]; do
    case "$1" in
        --remote)     USE_REMOTE=1 ;;
        --remote=*)   USE_REMOTE=1; REMOTE="${1#--remote=}" ;;
        -h|--help)    usage; exit 0 ;;
        -*)           usage; die "Unknown option: $1" ;;
        *)            positional+=("$1") ;;
    esac
    shift
done
STAGE="${positional[0]:-}"
SD_DEV="${positional[1]:-}"

if [[ -z "$STAGE" ]]; then
    echo "Select an option:"
    echo "  1) Stage 1 - package WIC image"
    echo "  2) Stage 2 - wipe SD card and write image"
    echo "  3) Stage 2 - wipe SD card and write image on a remote computer (SSH)"
    echo "  4) Both    - stage 1 then stage 2"
    echo "  5) Both    - stage 1 then stage 2 on a remote computer (SSH)"
    read -r -p "Choice [1-5]: " choice
    case "$choice" in
        1) STAGE=1 ;;
        2) STAGE=2 ;;
        3) STAGE=2;   USE_REMOTE=1 ;;
        4) STAGE=all ;;
        5) STAGE=all; USE_REMOTE=1 ;;
        *) die "Invalid choice: $choice" ;;
    esac
fi

if [[ $USE_REMOTE -eq 1 ]]; then
    [[ "$STAGE" == "2" || "$STAGE" == "all" || "$STAGE" == "both" ]] \
        || die "--remote only applies to stage 2 / all."
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

if [[ "$STAGE" == "2" || "$STAGE" == "all" ]] && [[ -z "$SD_DEV" ]]; then
    echo ""
    on_target "lsblk -d -o NAME,SIZE,MODEL,TRAN,RM"
    read -r -p "SD card device on $(target_name) (e.g. /dev/sdf): " SD_DEV
    [[ -n "$SD_DEV" ]] || die "No SD card device specified."
fi

case "$STAGE" in
    1)          stage1 ;;
    2)          stage2 "$SD_DEV" ;;
    all|both)   stage1; stage2 "$SD_DEV" ;;
    *)          usage; die "Unknown stage: $STAGE" ;;
esac

info "Done."
