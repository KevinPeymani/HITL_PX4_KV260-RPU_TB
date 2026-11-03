#!/usr/bin/env bash
# Start the Gazebo Classic HITL container on a WSL or native Ubuntu host.
# The image holds the PX4 plugins, models and worlds; no host folder is mounted.
#
# Usage:
#   run.sh           build the image if missing, start the container, open a shell
#   run.sh exec      open another shell in the running container
#   run.sh build     rebuild the image
#   run.sh stop      stop the container (it is removed on stop, as is exiting the first shell)
#   run.sh help      show the help
#
# Environment:
#   HOST_MODE=wsl|ubuntu   override the host detection
#   SOFTWARE_GL=1          render with llvmpipe instead of the GPU
#
# In the container: gazebo worlds/hitl_iris.world

set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
IMAGE=px4-gazebo-classic:22.04
CONTAINER=px4-gz

build_image() {
    docker build \
        --build-arg USER_UID="$(id -u)" --build-arg USER_GID="$(id -g)" \
        -t "$IMAGE" "$SCRIPT_DIR"
}

detect_host() {
    if grep -qi microsoft /proc/sys/kernel/osrelease 2>/dev/null; then
        echo wsl
    else
        echo ubuntu
    fi
}

usage() {
    cat <<'EOF'
Usage: run.sh [command]

Gazebo Classic 11 container for PX4 HITL with the KV260 RPU.

Commands:
  (none)    build the image if missing, start the container px4-gz and open a shell
  exec      open another shell in the running container
  build     rebuild the image
  stop      stop the container (it is also removed when the first shell exits)
  help      show this help (also -h, --help)

Environment:
  HOST_MODE=wsl|ubuntu   override the host detection (default: from the kernel release)
  SOFTWARE_GL=1          render with llvmpipe instead of the GPU

HITL session (step 8.5-8.6):
  board:        sudo socat -d -d TCP-LISTEN:5760,reuseaddr,nodelay FILE:/dev/ttyRPMSG1,raw,echo=0
  shell 1:      ./run.sh
                socat -d -d PTY,link=/tmp/ttyKV260,raw,echo=0 TCP:<KV260_IP>:5760,nodelay
  shell 2:      ./run.sh exec
                gazebo worlds/hitl_iris.world
EOF
}

case "${1:-}" in
    help|-h|--help)
        usage
        exit 0
        ;;
    build)
        build_image
        exit 0
        ;;
    exec)
        exec docker exec -it "$CONTAINER" bash
        ;;
    stop)
        docker stop "$CONTAINER"
        exit 0
        ;;
    "")
        ;;
    *)
        usage >&2
        exit 1
        ;;
esac

HOST_MODE=${HOST_MODE:-$(detect_host)}

if [[ -z "${DISPLAY:-}" ]]; then
    echo "DISPLAY is not set: start from a desktop session (or WSLg)" >&2
    exit 1
fi

DISPLAY_ARGS=(-v /tmp/.X11-unix:/tmp/.X11-unix -e DISPLAY)
GPU_ARGS=()

case "$HOST_MODE" in
    wsl)
        # The host's XDG_RUNTIME_DIR points into /mnt/wslg, so pass the real directory.
        DISPLAY_ARGS+=(-v /mnt/wslg:/mnt/wslg -e WAYLAND_DISPLAY -e PULSE_SERVER
                       -e XDG_RUNTIME_DIR=/mnt/wslg/runtime-dir)
        if [[ "${SOFTWARE_GL:-0}" != 1 ]]; then
            GPU_ARGS=(--device /dev/dxg -v /usr/lib/wsl:/usr/lib/wsl:ro
                      -e LD_LIBRARY_PATH=/usr/lib/wsl/lib -e GALLIUM_DRIVER=d3d12)
        fi
        ;;
    ubuntu)
        # Allow X connections from this user's UID only (the container user has the same UID).
        if command -v xhost >/dev/null; then
            xhost +SI:localuser:"$(id -un)" >/dev/null
        else
            echo "xhost not found (apt install x11-xserver-utils); the X server may refuse the container" >&2
        fi
        if [[ "${SOFTWARE_GL:-0}" != 1 && -d /dev/dri ]]; then
            GPU_ARGS=(--device /dev/dri)
            # The render nodes belong to the render/video groups; give the container user those GIDs.
            for gid in $(stat -c %g /dev/dri/* 2>/dev/null | sort -u); do
                GPU_ARGS+=(--group-add "$gid")
            done
        fi
        ;;
    *)
        echo "unknown HOST_MODE: $HOST_MODE (wsl or ubuntu)" >&2
        exit 1
        ;;
esac

if [[ "${SOFTWARE_GL:-0}" == 1 ]]; then
    GPU_ARGS+=(-e LIBGL_ALWAYS_SOFTWARE=1)
fi

if ! docker image inspect "$IMAGE" >/dev/null 2>&1; then
    build_image
fi

echo "host: $HOST_MODE, GL: $([[ "${SOFTWARE_GL:-0}" == 1 ]] && echo software || echo GPU)"

exec docker run --rm -it --name "$CONTAINER" \
    --network host \
    "${DISPLAY_ARGS[@]}" \
    "${GPU_ARGS[@]}" \
    "$IMAGE"
