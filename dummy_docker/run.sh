#!/bin/sh
# Build and run the dummy validation container on the Lumen device.
# Usage: ./run.sh [--host <ip>] [--password <pw>]
#
# Requires: sshpass, docker (on device)

HOST=${1:-192.0.5.10}
PASS=${2:-Pp12345678}
SSH="sshpass -p $PASS ssh -o StrictHostKeyChecking=no nexus@$HOST"
SCP="sshpass -p $PASS scp -o StrictHostKeyChecking=no"

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)

echo ">>> Copying files to device..."
$SSH "mkdir -p /tmp/dummy_docker"
$SCP "$SCRIPT_DIR/Dockerfile" "$SCRIPT_DIR/validate.sh" nexus@$HOST:/tmp/dummy_docker/

echo ">>> Creating base image from device rootfs..."
$SSH "docker image inspect lumen-base:latest > /dev/null 2>&1 || \
    (tar -czf /tmp/lumen-rootfs.tar.gz \
        --exclude=./proc --exclude=./sys --exclude=./dev --exclude=./tmp \
        --exclude=./run --exclude=./var/run \
        -C / . && \
     docker import /tmp/lumen-rootfs.tar.gz lumen-base:latest && \
     rm /tmp/lumen-rootfs.tar.gz && \
     echo 'Base image created')"

echo ">>> Building image on device..."
$SSH "docker build -t lumen-dummy /tmp/dummy_docker/"

echo ">>> Running validation container (privileged + NVIDIA runtime)..."
$SSH "docker run --rm --runtime=nvidia --network host --privileged lumen-dummy"
