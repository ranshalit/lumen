# Persistent IP Change Helper Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add an on-device command to change `eth0` or `portus0` IP/CIDR live and persist it safely across reboot.

**Architecture:** A POSIX shell helper stages the new address while preserving the old one, then requires confirmation from the new SSH destination (or explicit console confirmation) before updating boot and ifupdown config. A 120-second rollback removes an unconfirmed staged address. The Yocto recipe installs the helper; README documents use and limitations.

**Tech Stack:** POSIX shell/BusyBox, Yocto BitBake, Python standard-library `unittest`.

**Spec:** `docs/superpowers/specs/2026-11-09-persistent-ip-change-design.md`

## Global Constraints

- Support only `eth0` and `portus0`.
- Require the new IPv4 address to differ from the current address; netmask-only changes are out of scope.
- Accept IPv4 in CIDR form; reject invalid IPv4, prefixes outside `1..32`, and `/0`.
- Use a 120-second default rollback window.
- Do not alter gateways, DNS, DHCP, Wi-Fi, or unrelated interfaces.
- Persist target-side changes to `/etc/init.d/lumen-eth-static` and `/etc/network/interfaces`.
- A reflash restores Yocto recipe defaults; target-side edits do not update the recipe.
- Config writes are sequential with backup/restore on command failure; they are not power-loss atomic as a pair.

## Review Focus

- Invalid interface, IPv4, or prefix must fail before changing runtime or files; test in Task 1.
- SSH confirmation from an address other than the staged destination must fail; test in Task 1.
- Timeout/cancel must remove only the staged address and retain old config; test in Task 1.
- Failed update of either config file must restore both originals and retain the old live address; test in Task 1.
- Concurrent timeout and confirmation must not leave a partial config update; test in Task 1.

---

### Task 1: Implement and test staged IP changes

**Files:**
- Create: `meta-lumen/recipes-core/network/lumen-eth-static/lumen-set-ip`
- Create: `testing/test_lumen_set_ip.py`

**Interfaces:**
- CLI: `lumen-set-ip prepare <eth0|portus0> <IPv4/CIDR>`, `lumen-set-ip confirm`, `lumen-set-ip confirm --console`, and `lumen-set-ip cancel`.
- `prepare` accepts one current IPv4 address per supported interface, adds the requested address without removing the current one, records pending state under `/run`, and starts rollback after 120 seconds.
- `prepare` rejects an address equal to the current IPv4; both addresses must coexist until SSH confirmation.
- SSH `confirm` requires `SSH_CONNECTION` and verifies its server-address field equals the staged IPv4; `confirm --console` is the explicit serial/local path.
- `confirm` updates only the selected interface in both config files, converts CIDR prefix to dotted netmask, then removes the old runtime address and cancels rollback.
- Use an atomic lock under `/run` to serialize `confirm`, `cancel`, and timeout rollback. Config files are backed up; restore both if either replacement fails.
- For unprivileged tests only, allow `LUMEN_SET_IP_TEST_ROOT` and `LUMEN_SET_IP_TEST_TIMEOUT`; production invocation requires root and uses fixed system paths.

- [x] **Step 1: Write focused helper tests**

Add standard-library `unittest` cases using a temporary config root and mocked `ip`/`sleep` commands. Cover both interfaces; `/24` and `/25` netmask conversion; invalid interface/address/prefix; prepare without persistent edits; correct and mismatched SSH confirmation; console confirmation; cancel and timeout rollback; config-write failure; and confirmation/timeout serialization.

- [x] **Step 2: Run tests to establish failures**

Run: `python3 -m unittest testing.test_lumen_set_ip -v`
Expected: tests fail because the helper is not present.

- [x] **Step 3: Implement the POSIX shell helper**

Create the four CLI operations above. Parse and validate IPv4/CIDR without external dependencies beyond BusyBox applets already used by the image. Keep the prior address live until confirmation; the rollback operation removes only the staged address. Refuse a second pending operation or an interface with zero/multiple current IPv4 addresses. Keep test-root/test-timeout overrides disabled for root execution.

- [x] **Step 4: Run helper tests**

Run: `python3 -m unittest testing.test_lumen_set_ip -v`
Expected: all tests pass, including failure-injection and timeout cases.

- [x] **Step 5: Check shell syntax**

Run: `sh -n meta-lumen/recipes-core/network/lumen-eth-static/lumen-set-ip`
Expected: exit status 0.

### Task 2: Package the helper in the Lumen image

**Files:**
- Modify: `meta-lumen/recipes-core/network/lumen-eth-static.bb`

**Interfaces:**
- Consumes: `meta-lumen/recipes-core/network/lumen-eth-static/lumen-set-ip`.
- Produces: executable `/usr/sbin/lumen-set-ip` in package `${PN}`.

- [x] **Step 1: Add the helper to `SRC_URI` and install it**

Install the file to `${sbindir}/lumen-set-ip` with mode `0755`, and add it to `FILES:${PN}`. Add no new runtime packages; use the existing BusyBox `ip` command.

- [x] **Step 2: Build the recipe install task**

Run: `bitbake -c install -f lumen-eth-static`
Expected: task succeeds and the recipe image contains executable `usr/sbin/lumen-set-ip`.

### Task 3: Document runtime and persistent usage

**Files:**
- Modify: `README.md`

**Interfaces:**
- Document commands matching Task 1, for both `eth0` and `portus0`.

- [x] **Step 1: Replace the manual two-file procedure**

Explain prepare/connect/confirm, console confirmation, cancel and timeout behavior, CIDR/netmask handling, route/SSH interruption caveat, and that reflashing resets recipe defaults. Include an example using `192.0.5.20/24`.

- [x] **Step 2: Check documentation diff**

Run: `git diff --check`
Expected: no whitespace errors; README command names and flags match the helper.
