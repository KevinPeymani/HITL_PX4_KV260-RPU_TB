#!/usr/bin/env bash
# Copy an R5 executable to a KV260 board, install it as the remoteproc
# firmware, then start the R5 after confirmation.
#
# Two modes:
#   local   the board is reachable from this computer: copy straight to it.
#   remote  the board hangs off another PC: copy the executable to that PC
#           (PC_DIR), then from the PC to the board. Board commands also run
#           from the PC, which needs sshpass if the board uses a password.
#
# Executables, boards and remote PCs are kept in a config file (default: next
# to this script, kv260_deploy.conf). The first BOARD and the first PC are the
# defaults; the default executable is DEFAULT_EXE. Line format:
#   EXE   <name> <path>
#   BOARD <name> <user@host> [password]     (no password: SSH key auth)
#   PC    <name> <user@host> [password]     (no password: SSH key auth)

set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
CONF=${KV260_DEPLOY_CONF:-$SCRIPT_DIR/kv260_deploy.conf}

MODE=local
DEFAULT_EXE=/home/kevin/dev/PX4-Autopilot/platforms/nuttx/NuttX/nuttx/nuttx
PC_DIR=/home/kevin/dev/HITL_PX4_KV260-RPU_TB
FW_NAME=nuttx-r5.elf
RPROC=remoteproc0

usage() {
    cat <<EOF
Usage: $(basename "$0") [options]

Deploy:
  -m, --mode local|remote    local: board connected to this computer (default)
                             remote: board connected to a remote PC
  -e, --exe NAME|PATH        executable (config name or file path; default: $DEFAULT_EXE)
  -b, --board NAME|USER@HOST board (config name or user@host; default: first BOARD)
  -p, --password PASS        board SSH/sudo password (overrides the config)
  -P, --pc NAME|USER@HOST    remote PC (implies -m remote; default: first PC)
      --pc-password PASS     remote PC SSH password (overrides the config)
      --pc-dir DIR           copy destination on the remote PC (default: $PC_DIR)
  -f, --fw-name NAME         firmware file name in /lib/firmware (default: $FW_NAME)
  -r, --rproc NAME           remoteproc instance (default: $RPROC)
  -y, --yes                  start the R5 without asking

Config ($CONF):
  --add-exe NAME PATH                add an executable
  --add-board NAME USER@HOST [PASS]  add a board
  --add-pc NAME USER@HOST [PASS]     add a remote PC
  --remove NAME                      remove an entry
  -l, --list                         list the entries
  -h, --help                         this help
EOF
}

die() { echo "error: $*" >&2; exit 1; }
info() { echo -e "\033[1;34m==>\033[0m $*"; }

# POSIX single-quote a string (remote shells may be busybox ash).
sq() { printf "'%s'" "${1//\'/\'\\\'\'}"; }

init_conf() {
    [[ -f $CONF ]] && return
    cat >"$CONF" <<'EOF'
# kv260_deploy.sh config. The first BOARD and first PC are the defaults.
# EXE   <name> <path>
# BOARD <name> <user@host> [password]
# PC    <name> <user@host> [password]
EXE   px4    /home/kevin/dev/PX4-Autopilot/platforms/nuttx/NuttX/nuttx/nuttx
BOARD kv260  petalinux@10.11.0.77 qwe
PC    eq     kevin@kevin-eq
EOF
    chmod 600 "$CONF"
}

# Print field 3.. of the first line of type $1 named $2
# (or of the first line of type $1 when $2 is empty).
conf_get() {
    awk -v t="$1" -v n="$2" '
        $1 == t && (n == "" || $2 == n) { $1 = ""; $2 = ""; sub(/^ +/, ""); print; exit }
    ' "$CONF"
}

conf_has_name() {
    awk -v n="$1" '($1 == "EXE" || $1 == "BOARD" || $1 == "PC") && $2 == n { f = 1 } END { exit !f }' "$CONF"
}

list_conf() {
    echo "Config: $CONF"
    echo "Executables:"
    echo "  (default)    $DEFAULT_EXE"
    awk '$1 == "EXE" { printf "  %-12s %s\n", $2, $3 }' "$CONF"
    local t
    for t in BOARD PC; do
        [[ $t == BOARD ]] && echo "Boards:" || echo "Remote PCs:"
        awk -v t=$t '$1 == t { printf "  %-12s %s%s%s\n", $2, $3, ($4 != "" ? "  (password set)" : ""), (++i == 1 ? "  (default)" : "") }' "$CONF"
    done
}

add_host() {  # TYPE NAME USER@HOST [PASS]
    conf_has_name "$2" && die "name '$2' already exists in $CONF"
    [[ $3 == *@* ]] || die "address must be user@host"
    printf '%-5s %s %s%s\n' "$1" "$2" "$3" "${4:+ $4}" >>"$CONF"
    echo "Added $1 '$2' -> $3"
}

# Resolve a host argument of type $1 (config name, user@host, or empty for the
# default) into HOST_ADDR and HOST_PASS.
resolve_host() {
    local type=$1 arg=$2 entry
    HOST_ADDR="" HOST_PASS=""
    if [[ -z $arg ]]; then
        entry=$(conf_get "$type" "")
        [[ -n $entry ]] || return 1
    elif entry=$(conf_get "$type" "$arg") && [[ -n $entry ]]; then
        :
    else
        [[ $arg == *@* ]] || die "unknown $type '$arg' (not in config, not user@host)"
        # Ad-hoc address that matches a configured entry: reuse its password.
        entry="$arg $(awk -v t="$type" -v a="$arg" '$1 == t && $3 == a { print $4; exit }' "$CONF")"
    fi
    read -r HOST_ADDR HOST_PASS <<<"$entry" || true
}

# ---------------------------------------------------------------- arguments

init_conf

EXE_ARG="" BOARD_ARG="" PC_ARG="" ASSUME_YES=0
PASS_ARG="" PASS_SET=0 PC_PASS_ARG="" PC_PASS_SET=0

while [[ $# -gt 0 ]]; do
    case $1 in
        -m|--mode)     MODE=${2:?missing value for $1}; shift 2 ;;
        -e|--exe)      EXE_ARG=${2:?missing value for $1}; shift 2 ;;
        -b|--board)    BOARD_ARG=${2:?missing value for $1}; shift 2 ;;
        -p|--password) PASS_ARG=${2-}; PASS_SET=1; shift 2 ;;
        -P|--pc)       PC_ARG=${2:?missing value for $1}; MODE=remote; shift 2 ;;
        --pc-password) PC_PASS_ARG=${2-}; PC_PASS_SET=1; shift 2 ;;
        --pc-dir)      PC_DIR=${2:?missing value for $1}; shift 2 ;;
        -f|--fw-name)  FW_NAME=${2:?missing value for $1}; shift 2 ;;
        -r|--rproc)    RPROC=${2:?missing value for $1}; shift 2 ;;
        -y|--yes)      ASSUME_YES=1; shift ;;
        --add-exe)
            [[ $# -ge 3 ]] || die "--add-exe NAME PATH"
            conf_has_name "$2" && die "name '$2' already exists in $CONF"
            path=$(realpath -m "$3")
            [[ -f $path ]] || echo "warning: $path does not exist (yet)" >&2
            echo "EXE   $2 $path" >>"$CONF"
            echo "Added EXE '$2' -> $path"; exit 0 ;;
        --add-board)
            [[ $# -ge 3 ]] || die "--add-board NAME USER@HOST [PASSWORD]"
            add_host BOARD "$2" "$3" "${4-}"; exit 0 ;;
        --add-pc)
            [[ $# -ge 3 ]] || die "--add-pc NAME USER@HOST [PASSWORD]"
            add_host PC "$2" "$3" "${4-}"; exit 0 ;;
        --remove)
            [[ $# -ge 2 ]] || die "--remove NAME"
            conf_has_name "$2" || die "no entry named '$2'"
            tmp=$(mktemp)
            awk -v n="$2" '!(($1 == "EXE" || $1 == "BOARD" || $1 == "PC") && $2 == n)' "$CONF" >"$tmp"
            cat "$tmp" >"$CONF"; rm -f "$tmp"
            echo "Removed '$2'"; exit 0 ;;
        -l|--list) list_conf; exit 0 ;;
        -h|--help) usage; exit 0 ;;
        *) usage >&2; die "unknown option: $1" ;;
    esac
done

[[ $MODE == local || $MODE == remote ]] || die "mode must be 'local' or 'remote'"

# Executable: a config name, else a path.
if [[ -z $EXE_ARG ]]; then
    EXE=$DEFAULT_EXE
elif EXE=$(conf_get EXE "$EXE_ARG") && [[ -n $EXE ]]; then
    :
else
    EXE=$EXE_ARG
fi
[[ -f $EXE ]] || die "executable not found: $EXE"

resolve_host BOARD "$BOARD_ARG" || die "no BOARD in $CONF (use --add-board or -b USER@HOST)"
TARGET=$HOST_ADDR PASS=$HOST_PASS
(( PASS_SET )) && PASS=$PASS_ARG
BOARD_USER=${TARGET%@*}

if [[ $MODE == remote ]]; then
    resolve_host PC "$PC_ARG" || die "no PC in $CONF (use --add-pc or -P USER@HOST)"
    PC=$HOST_ADDR PC_PASS=$HOST_PASS
    (( PC_PASS_SET )) && PC_PASS=$PC_PASS_ARG
fi

# ---------------------------------------------------------------- transport

SSH_OPTS=(-o StrictHostKeyChecking=accept-new -o ConnectTimeout=10)

# This computer's first hop: the board (local mode) or the PC (remote mode).
HOP_PASS=$PASS
[[ $MODE == remote ]] && HOP_PASS=$PC_PASS
if [[ -n $HOP_PASS ]]; then
    command -v sshpass >/dev/null || die "sshpass is required for password login (sudo apt install sshpass)"
    export SSHPASS=$HOP_PASS
    SSH=(sshpass -e ssh "${SSH_OPTS[@]}")
    SCP=(sshpass -e scp "${SSH_OPTS[@]}")
else
    SSH=(ssh "${SSH_OPTS[@]}")
    SCP=(scp "${SSH_OPTS[@]}")
fi

# Run a bash script on the remote PC. The script travels on stdin, so the
# board password never shows up in a command line.
on_pc() {
    "${SSH[@]}" "$PC" "bash -s" <<<"set -e
export SSHPASS=$(sq "$PASS")
if [ -n \"\$SSHPASS\" ]; then
    command -v sshpass >/dev/null || { echo 'sshpass is missing on $PC (sudo apt install sshpass)' >&2; exit 1; }
    B=(sshpass -e)
else
    B=()
fi
B_OPTS=(${SSH_OPTS[*]})
$1"
}

# Run a shell command on the board, feeding $2 on its stdin.
on_board() {
    local cmd=$1 input=${2-}
    if [[ $MODE == local ]]; then
        "${SSH[@]}" "$TARGET" "$cmd" <<<"$input"
    else
        on_pc "\"\${B[@]}\" ssh \"\${B_OPTS[@]}\" $(sq "$TARGET") $(sq "$cmd") <<< $(sq "$input")"
    fi
}

# Run a shell snippet on the board as root (sudo password fed on stdin).
board_root() {
    if [[ $BOARD_USER == root ]]; then
        on_board "sh -c $(sq "$1")"
    else
        on_board "sudo -S -p '' sh -c $(sq "$1")" "$PASS"
    fi
}

RP=/sys/class/remoteproc/$RPROC
TMP_REMOTE=/tmp/$FW_NAME

# ---------------------------------------------------------------- deploy

info "Executable: $EXE ($(stat -c %s "$EXE") bytes, $(date -r "$EXE" '+%F %T'))"
if [[ $MODE == remote ]]; then
    info "Remote PC:  $PC:$PC_DIR"
fi
info "Board:      $TARGET  ($RPROC, /lib/firmware/$FW_NAME)"

if [[ $MODE == local ]]; then
    info "Copying to the board..."
    "${SCP[@]}" -q "$EXE" "$TARGET:$TMP_REMOTE"
else
    PC_FILE=$PC_DIR/$(basename "$EXE")
    info "Copying to the remote PC ($PC_FILE)..."
    "${SSH[@]}" "$PC" "mkdir -p $(sq "$PC_DIR")" </dev/null
    "${SCP[@]}" -q "$EXE" "$PC:$PC_FILE"
    info "Copying from the remote PC to the board..."
    on_pc "\"\${B[@]}\" scp -q \"\${B_OPTS[@]}\" $(sq "$PC_FILE") $(sq "$TARGET:$TMP_REMOTE") </dev/null"
fi

info "Updating R5 firmware..."
board_root "
    set -e
    [ -d $RP ] || { echo 'no $RP on the board' >&2; exit 1; }
    state=\$(cat $RP/state)
    if [ \"\$state\" != offline ]; then
        echo \"    stopping $RPROC (state: \$state)\"
        echo stop > $RP/state || true
        i=0
        while [ \"\$(cat $RP/state)\" != offline ] && [ \$i -lt 20 ]; do
            sleep 0.25; i=\$((i + 1))
        done
    fi
    state=\$(cat $RP/state)
    if [ \"\$state\" != offline ]; then
        echo \"$RPROC did not stop (state: \$state), firmware not updated\" >&2
        rm -f $TMP_REMOTE
        exit 1
    fi
    echo '    R5 stopped'
    mv -f $TMP_REMOTE /lib/firmware/$FW_NAME
    sync
    echo $FW_NAME > $RP/firmware
    echo \"    firmware: \$(cat $RP/firmware), state: \$(cat $RP/state)\"
"

if (( ! ASSUME_YES )); then
    read -r -p "Start the R5 now? [Y/n] " ans
    case ${ans,,} in
        ""|y|yes) ;;
        *) info "Firmware installed, R5 left stopped. Start later with:"
           echo "    echo start | sudo tee $RP/state"
           exit 0 ;;
    esac
fi

info "Starting $RPROC..."
board_root "
    echo start > $RP/state || true
    sleep 1
    echo \"    state: \$(cat $RP/state)\"
    dmesg | grep -iE 'remoteproc|rpmsg|virtio|r5' | tail -n 8 | sed 's/^/    /'
"
