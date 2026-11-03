#!/usr/bin/env bash
set -euo pipefail

usage() {
    echo "Usage: $0 <lumen-machine>" >&2
    echo "Machines: lumen-orin-nx-16gb lumen-orin-nx-8gb lumen-orin-nano-8gb lumen-orin-nano-4gb" >&2
}

if [[ $# -ne 1 ]]; then
    usage
    exit 2
fi

MACHINE=$1
case "$MACHINE" in
    lumen-orin-nx-16gb|lumen-orin-nx-8gb|lumen-orin-nano-8gb|lumen-orin-nano-4gb) ;;
    *)
        echo "Unsupported machine: $MACHINE" >&2
        usage
        exit 2
        ;;
esac

ROOT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
IMAGE_DIR="$ROOT_DIR/build/tmp/deploy/images/$MACHINE"
KERNEL="$IMAGE_DIR/Image"
ROOTFS="$IMAGE_DIR/lumen-image-minimal-$MACHINE.rootfs.ext4"

if ! command -v qemu-system-aarch64 >/dev/null 2>&1; then
    echo "Required command not found: qemu-system-aarch64" >&2
    exit 1
fi
if [[ ! -f "$KERNEL" ]]; then
    echo "Image not found: $KERNEL (build this Lumen variant first)" >&2
    exit 1
fi
if [[ ! -f "$ROOTFS" ]]; then
    echo "Rootfs not found: $ROOTFS (build this Lumen variant first)" >&2
    exit 1
fi

LOG_ROOT=${LUMEN_QEMU_LOGS:-/tmp/lumen-qemu}
LOG_DIR="$LOG_ROOT/$MACHINE"
CONSOLE_LOG="$LOG_DIR/console.log"
CONSOLE_SOCK="$LOG_DIR/console.sock"
mkdir -p "$LOG_DIR"
rm -f "$CONSOLE_SOCK"
: > "$CONSOLE_LOG"

cat <<EOF
Lumen QEMU boot
  machine: $MACHINE
  kernel:  $KERNEL
  rootfs:  $ROOTFS (snapshot; original unchanged)

Serial socket: socat - UNIX-CONNECT:$CONSOLE_SOCK
Boot log:      tail -f $CONSOLE_LOG
Starting QEMU... (Ctrl+C to stop)
EOF

exec qemu-system-aarch64 \
    -M virt,gic-version=3 \
    -cpu max \
    -m 4096 \
    -smp 4 \
    -kernel "$KERNEL" \
    -drive "if=virtio,file=$ROOTFS,format=raw,cache=unsafe,snapshot=on" \
    -netdev user,id=net0 \
    -device virtio-net-pci,netdev=net0 \
    -append "root=/dev/vda rw rootfstype=ext4 rootwait earlycon=pl011,mmio32,0x09000000 console=ttyAMA0,115200" \
    -chardev "socket,id=serial0,path=$CONSOLE_SOCK,server=on,wait=off,logfile=$CONSOLE_LOG" \
    -serial chardev:serial0 \
    -display none \
    -monitor none \
    -no-reboot
