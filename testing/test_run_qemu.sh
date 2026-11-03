#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT

PROJECT="$TMP_DIR/project"
MACHINE=lumen-orin-nano-8gb
IMAGE_DIR="$PROJECT/build/tmp/deploy/images/$MACHINE"
MOCK_BIN="$TMP_DIR/bin"
mkdir -p "$IMAGE_DIR" "$MOCK_BIN"
cp "$REPO_ROOT/run-qemu.sh" "$PROJECT/run-qemu.sh"
touch "$IMAGE_DIR/Image"
touch "$IMAGE_DIR/lumen-image-minimal-$MACHINE.rootfs.ext4"

cat > "$MOCK_BIN/qemu-system-aarch64" <<'MOCK'
#!/usr/bin/env bash
printf '%s\n' "$@" > "$QEMU_ARGS_FILE"
MOCK
chmod +x "$MOCK_BIN/qemu-system-aarch64"

export PATH="$MOCK_BIN:$PATH"
export QEMU_ARGS_FILE="$TMP_DIR/qemu-args"
export LUMEN_QEMU_LOGS="$TMP_DIR/logs"

if "$PROJECT/run-qemu.sh" invalid-machine >"$TMP_DIR/invalid.out" 2>&1; then
    echo "Expected unsupported machine to fail" >&2
    exit 1
fi
grep -q 'Unsupported machine' "$TMP_DIR/invalid.out"
test ! -e "$QEMU_ARGS_FILE"

"$PROJECT/run-qemu.sh" "$MACHINE"
grep -Fxq -- '-M' "$QEMU_ARGS_FILE"
grep -Fxq -- 'virt,gic-version=3' "$QEMU_ARGS_FILE"
grep -Fq -- "file=$IMAGE_DIR/lumen-image-minimal-$MACHINE.rootfs.ext4,format=raw,cache=unsafe,snapshot=on" "$QEMU_ARGS_FILE"
grep -Fxq -- "$IMAGE_DIR/Image" "$QEMU_ARGS_FILE"
test -f "$TMP_DIR/logs/$MACHINE/console.log"

rm -f "$QEMU_ARGS_FILE"
rm "$IMAGE_DIR/Image"
if "$PROJECT/run-qemu.sh" "$MACHINE" >"$TMP_DIR/missing.out" 2>&1; then
    echo "Expected missing kernel to fail" >&2
    exit 1
fi
grep -q 'Image not found' "$TMP_DIR/missing.out"
test ! -e "$QEMU_ARGS_FILE"

touch "$IMAGE_DIR/Image"
rm "$IMAGE_DIR/lumen-image-minimal-$MACHINE.rootfs.ext4"
if "$PROJECT/run-qemu.sh" "$MACHINE" >"$TMP_DIR/missing-rootfs.out" 2>&1; then
    echo "Expected missing rootfs to fail" >&2
    exit 1
fi
grep -q 'Rootfs not found' "$TMP_DIR/missing-rootfs.out"
test ! -e "$QEMU_ARGS_FILE"

echo "QEMU launcher tests passed"
