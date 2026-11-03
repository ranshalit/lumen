# Lumen QEMU Runner Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a Hadron-style launcher to boot any already-built Lumen ARM64 image in QEMU for basic software and console testing.

**Architecture:** A root-level Bash launcher selects one of the four existing Lumen machine outputs, validates its kernel and ext4 rootfs, and boots them on QEMU's generic ARM64 `virt` machine. QEMU snapshot mode protects the built rootfs; serial output goes to a per-machine log and Unix socket. A focused shell test uses temporary fake artifacts and a mock QEMU executable, while the README documents use and limitations.

**Tech Stack:** Bash, QEMU (`qemu-system-aarch64`), socat, Git.

## Global Constraints

- The launcher requires one of the four supported Lumen machine names as its argument.
- This is a best-effort software boot path using the existing Tegra kernel and rootfs, not hardware emulation.
- QEMU snapshot mode ensures writes made during a session do not modify the built rootfs.
- QEMU's generic virtual machine does not emulate Jetson peripherals, GPU, camera, or carrier-board behavior.
- No separate QEMU-specific Yocto target is added.

---

## File Structure

- Create `run-qemu.sh`: validate invocation and artifacts, then start QEMU and expose its serial console.
- Create `testing/test_run_qemu.sh`: exercise launcher preflight and QEMU arguments with temporary fixture files and a mock executable.
- Modify `README.md`: document host dependencies, per-variant invocation, console/log access, and emulation limits.

### Task 1: Add a tested QEMU launcher

**Files:**
- Create: `testing/test_run_qemu.sh`
- Create: `run-qemu.sh`

**Interfaces:**
- Consumes: one positional `MACHINE` value from `lumen-orin-nx-16gb`, `lumen-orin-nx-8gb`, `lumen-orin-nano-8gb`, or `lumen-orin-nano-4gb`; optional `LUMEN_QEMU_LOGS` environment variable as the log root.
- Produces: QEMU invocation using `build/tmp/deploy/images/$MACHINE/Image` and `lumen-image-minimal-$MACHINE.rootfs.ext4`; logs and a serial socket under `$LUMEN_QEMU_LOGS/$MACHINE`, defaulting to `/tmp/lumen-qemu/$MACHINE`.

- [x] **Step 1: Create the focused launcher test**

Create `testing/test_run_qemu.sh`. The test copies the launcher into an isolated temporary project tree so its `build/` fixtures never touch the real worktree. A mock QEMU executable records each argument on its own line.

```bash
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
```

- [x] **Step 2: Run the test and verify it fails before the launcher exists**

Run: `bash testing/test_run_qemu.sh`

Expected: nonzero exit because `run-qemu.sh` does not exist yet.

- [x] **Step 3: Implement `run-qemu.sh`**

Create the launcher with this interface and behavior. Validate the argument before checking build files, and check `qemu-system-aarch64` before launching. Use QEMU's socket chardev logfile for `console.log`; remove only the known per-machine socket path before starting, as the Hadron launcher does.

```bash
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
```

- [x] **Step 4: Run focused tests and syntax checks**

Run: `bash -n run-qemu.sh testing/test_run_qemu.sh && bash testing/test_run_qemu.sh`

Expected: exit code 0 and output `QEMU launcher tests passed`.

- [x] **Step 5: Commit the launcher and tests**

```bash
git add run-qemu.sh testing/test_run_qemu.sh
git commit -m "feat: add Lumen QEMU runner" -m "Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>"
```

### Task 2: Document QEMU use and validate against the image

**Files:**
- Modify: `README.md`

**Interfaces:**
- Consumes: the machine argument and `LUMEN_QEMU_LOGS` behavior from `run-qemu.sh`.
- Produces: exact host install and run instructions, log/socket access commands, and a clear statement of emulation limitations.

- [x] **Step 1: Add a QEMU section to the README**

Place a section after the build output instructions. Document that QEMU does not build the image, so run `kas build kas/lumen-orin-nano-8gb.yml` (or the chosen variant's config) first. On Ubuntu, install the host tools with:

```bash
sudo apt-get install -y qemu-system-arm socat
```

Show this invocation and console access:

```bash
./run-qemu.sh lumen-orin-nano-8gb

# In another terminal:
tail -f /tmp/lumen-qemu/lumen-orin-nano-8gb/console.log
socat - UNIX-CONNECT:/tmp/lumen-qemu/lumen-orin-nano-8gb/console.sock
```

Also document `LUMEN_QEMU_LOGS=/path/to/log-root` and explain the launcher creates a machine-specific directory beneath that path. State that snapshot mode discards VM writes at exit; QEMU `virt` does not provide Jetson GPU, camera, carrier-board peripherals, or equivalent hardware/network behavior; and kernel virtio compatibility may limit boot success.

- [x] **Step 2: Review README commands and run targeted checks**

Run:

```bash
bash -n run-qemu.sh testing/test_run_qemu.sh
bash testing/test_run_qemu.sh
git diff --check -- README.md run-qemu.sh testing/test_run_qemu.sh
```

Expected: all commands exit 0.

If `qemu-system-aarch64` and a built Lumen image are available, run `./run-qemu.sh lumen-orin-nano-8gb`, confirm boot output appears in the printed log path, and connect with the printed `socat` command. After stopping QEMU, compare the rootfs checksum with the checksum captured before launch; it must be unchanged. If no built image or QEMU executable is available, report the integration boot as not run and retain the passing mock tests.

Capture the checksum before launch; after stopping QEMU, verify it in the same terminal:

```bash
ROOTFS=build/tmp/deploy/images/lumen-orin-nano-8gb/lumen-image-minimal-lumen-orin-nano-8gb.rootfs.ext4
sha256sum "$ROOTFS" > /tmp/lumen-qemu-rootfs.before
./run-qemu.sh lumen-orin-nano-8gb
# Stop QEMU with Ctrl+C, then run:
sha256sum -c /tmp/lumen-qemu-rootfs.before
```

Expected: `sha256sum -c` reports `OK`.

Execution note: `qemu-system-aarch64` is installed, but no Lumen `Image` or
`.rootfs.ext4` artifact was present, so the real-VM boot and checksum check were
not run.

- [x] **Step 3: Commit the documentation**

```bash
git add README.md
git commit -m "docs: explain running Lumen image in QEMU" -m "Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>"
```
