#!/usr/bin/env bash
set -euo pipefail

usage() {
    echo "Usage: $0 <lumen-machine> [timeout-seconds]" >&2
    exit 2
}

[[ $# -ge 1 && $# -le 2 ]] || usage
MACHINE=$1
TIMEOUT=${2:-300}
case "$MACHINE" in
    lumen-orin-nx-16gb|lumen-orin-nx-8gb|lumen-orin-nano-8gb|lumen-orin-nano-4gb) ;;
    *) usage ;;
esac
[[ "$TIMEOUT" =~ ^[1-9][0-9]*$ ]] || usage

ROOT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
LOG_ROOT=${LUMEN_QEMU_LOGS:-"$ROOT_DIR/build/qemu-ci"}
mkdir -p "$LOG_ROOT"
# Isolate each run so a previous login prompt cannot satisfy this test.
RUN_DIR=$(mktemp -d "$LOG_ROOT/run-XXXXXX")
CONSOLE_LOG="$RUN_DIR/$MACHINE/console.log"
LAUNCHER_LOG="$RUN_DIR/launcher.log"

echo "QEMU boot test: $MACHINE (timeout: ${TIMEOUT}s)"
echo "Logs: $RUN_DIR"
LUMEN_QEMU_LOGS="$RUN_DIR" "$ROOT_DIR/run-qemu.sh" "$MACHINE" \
    >"$LAUNCHER_LOG" 2>&1 &
QEMU_PID=$!

cleanup() {
    kill "$QEMU_PID" 2>/dev/null || true
    wait "$QEMU_PID" 2>/dev/null || true
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

fail() {
    echo "FAIL: $1" >&2
    for log in "$LAUNCHER_LOG" "$CONSOLE_LOG"; do
        if [[ -f "$log" ]]; then
            echo "--- $log ---" >&2
            tail -n 40 "$log" >&2
        fi
    done
    exit 1
}

DEADLINE=$((SECONDS + TIMEOUT))
while true; do
    if ! kill -0 "$QEMU_PID" 2>/dev/null; then
        fail "QEMU exited before reaching a login prompt."
    fi
    if [[ -f "$CONSOLE_LOG" ]]; then
        if grep -aq 'Kernel panic' "$CONSOLE_LOG"; then
            fail "Kernel panic detected."
        fi
        if grep -aEq '^[[:alnum:]_.-]+ login:[[:space:]]*$' "$CONSOLE_LOG"; then
            echo "PASS: $MACHINE reached a login prompt."
            exit 0
        fi
    fi
    if (( SECONDS >= DEADLINE )); then
        fail "Timed out after ${TIMEOUT}s waiting for a login prompt."
    fi
    sleep 0.2
done
