#!/bin/sh
# install.sh — Dummy docker app installer for Lumen device
#
# Mirrors the real app team install.sh pattern:
#   1. Check free disk space
#   2. Stop running app containers
#   3. Prune old images (prevents rootfs bloat)
#   4. Build lumen-base image from device rootfs
#   5. Deploy compose file to /opt/dragonfly/
#
# Usage: scp dummy_docker/ nexus@<device>:/tmp/ && ssh nexus@<device> "cd /tmp/dummy_docker && sudo sh install.sh"

set -e

INSTALL_DIR=/opt/dragonfly
COMPOSE_FILE="$(dirname "$0")/docker-compose.yaml"
IMAGE_NAME=lumen-base
IMAGE_TAG=latest
MIN_FREE_MB=2048

# Must run as root
if [ "$(id -u)" -ne 0 ]; then
    echo "Please run as root (sudo sh install.sh)"
    exit 1
fi

# Check free disk space
FREE_MB=$(df /var/lib/docker 2>/dev/null | awk 'NR==2 {print int($4/1024)}')
if [ -z "$FREE_MB" ]; then
    FREE_MB=$(df / | awk 'NR==2 {print int($4/1024)}')
fi
if [ "$FREE_MB" -lt "$MIN_FREE_MB" ]; then
    echo "ERROR: only ${FREE_MB}MB free, need at least ${MIN_FREE_MB}MB. Aborting."
    exit 1
fi
echo "Free space: ${FREE_MB}MB — OK"

# Stop running app containers
echo "Stopping running app containers..."
docker compose -f "$INSTALL_DIR/docker-compose.yaml" --project-name lumen down 2>/dev/null || true

# Prune old lumen-base image
echo "Removing old ${IMAGE_NAME}:${IMAGE_TAG} image (if any)..."
docker rmi -f "${IMAGE_NAME}:${IMAGE_TAG}" 2>/dev/null || true

# Build lumen-base from device rootfs
echo "Building ${IMAGE_NAME}:${IMAGE_TAG} from device rootfs..."
TMPTAR=$(mktemp /tmp/lumen-rootfs-XXXX.tar.gz)
tar -czf "$TMPTAR" \
    --exclude=./proc --exclude=./sys --exclude=./dev \
    --exclude=./tmp --exclude=./run --exclude=./var/lib/docker \
    --exclude=./opt/containerd \
    -C / . 2>/dev/null || true   # ignore permission warnings
docker import "$TMPTAR" "${IMAGE_NAME}:${IMAGE_TAG}"
rm -f "$TMPTAR"
echo "Image ${IMAGE_NAME}:${IMAGE_TAG} loaded"

# Deploy compose file
echo "Deploying compose file to ${INSTALL_DIR}..."
mkdir -p "$INSTALL_DIR"
cp "$COMPOSE_FILE" "$INSTALL_DIR/docker-compose.yaml"
chown -R nexus:nexus "$INSTALL_DIR" 2>/dev/null || true

echo ""
echo "Installation complete. Reboot to start the app, or run:"
echo "  sudo /etc/init.d/lumen-app start"
