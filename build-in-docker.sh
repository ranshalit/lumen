#!/bin/sh
set -eu

usage() {
    echo "Usage: $0 <lumen-orin-nx-16gb|lumen-orin-nx-8gb|lumen-orin-nano-8gb|lumen-orin-nano-4gb>" >&2
    exit 2
}

[ "$#" -eq 1 ] || usage

variant=$1
case "$variant" in
    lumen-orin-nx-16gb|lumen-orin-nx-8gb|lumen-orin-nano-8gb|lumen-orin-nano-4gb)
        ;;
    *)
        usage
        ;;
esac

project_dir=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
image=${LUMEN_YOCTO_DOCKER_IMAGE:-artifactory.rafael.co.il/rtsis-docker-local-ww/yocto-scarthgap:v1.4.0}
downloads_cache=${LUMEN_DL_CACHE:-/media/ranshal/jetson/shared/downloads}
sstate_cache=${LUMEN_SSTATE_CACHE:-/media/ranshal/jetson/shared/sstate}

if ! command -v docker >/dev/null 2>&1; then
    echo "Docker is not installed or not on PATH." >&2
    exit 1
fi

if ! docker image inspect "$image" >/dev/null 2>&1; then
    echo "Docker image is not available locally: $image" >&2
    echo "Pull it first, for example: sudo docker pull $image" >&2
    exit 1
fi

for cache_dir in "$downloads_cache" "$sstate_cache"; do
    if [ ! -d "$cache_dir" ]; then
        echo "Yocto cache directory does not exist: $cache_dir" >&2
        echo "Override with LUMEN_DL_CACHE and LUMEN_SSTATE_CACHE if needed." >&2
        exit 1
    fi
done

host_uid=${SUDO_UID:-$(id -u)}
host_gid=${SUDO_GID:-$(id -g)}
host_user=${SUDO_USER:-$(id -un)}

echo "Starting Docker shell for $variant."
echo "Inside the container, run: kas build kas/$variant.yml"
echo "Build output stays on the host under: $project_dir/build/"

exec docker run --rm -it \
    -e "UID=$host_uid" \
    -e "GID=$host_gid" \
    -e "USERNAME=$host_user" \
    -w "$project_dir" \
    -v "$project_dir:$project_dir" \
    -v "$downloads_cache:/media/ranshal/jetson/shared/downloads" \
    -v "$sstate_cache:/media/ranshal/jetson/shared/sstate" \
    "$image" \
    bash
