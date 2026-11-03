#!/usr/bin/env bash
# Start the Gazebo Classic HITL container on WSL (WSLg display, D3D12 GPU).
# The image holds the PX4 plugins, models and worlds; no host folder is mounted.
#
# Usage:
#   run.sh           build the image if missing, start the container, open a shell
#   run.sh exec      open another shell in the running container
#   run.sh build     rebuild the image
#   run.sh stop      stop the container (it is removed on stop, as is exiting the first shell)
#
# Environment:
#   SOFTWARE_GL=1    render with llvmpipe instead of the GPU
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

case "${1:-}" in
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
        echo "usage: $0 [build|exec|stop]" >&2
        exit 1
        ;;
esac

if ! docker image inspect "$IMAGE" >/dev/null 2>&1; then
    build_image
fi

if [[ "${SOFTWARE_GL:-0}" == 1 ]]; then
    GL_ENV=(-e LIBGL_ALWAYS_SOFTWARE=1)
else
    GL_ENV=(-e GALLIUM_DRIVER=d3d12)
fi

# The host's XDG_RUNTIME_DIR points into /mnt/wslg, so pass the real directory.
exec docker run --rm -it --name "$CONTAINER" \
    --network host \
    -v /tmp/.X11-unix:/tmp/.X11-unix \
    -v /mnt/wslg:/mnt/wslg \
    -e DISPLAY -e WAYLAND_DISPLAY -e PULSE_SERVER \
    -e XDG_RUNTIME_DIR=/mnt/wslg/runtime-dir \
    --device /dev/dxg \
    -v /usr/lib/wsl:/usr/lib/wsl:ro \
    -e LD_LIBRARY_PATH=/usr/lib/wsl/lib \
    "${GL_ENV[@]}" \
    "$IMAGE"
