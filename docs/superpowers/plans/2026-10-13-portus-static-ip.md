# Portus Static IP Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Configure Portus LAN743x as `192.168.1.10/24` on every boot without delaying boot or changing `eth0`.

**Architecture:** Keep the existing udev `lan743x` → `portus0` naming rule. Extend `lumen-eth-static`'s generated interfaces file and its init script with a separate background path for Portus; leave the current `eth0` setup intact.

**Tech Stack:** Yocto/BitBake recipe, ifupdown interfaces file, POSIX shell, `ip` utility, udev.

## Global Constraints

- Portus address: `192.168.1.10`.
- Portus netmask: `255.255.255.0` (`/24`).
- Preserve the existing `eth0` address and fast-start sequence.
- Do not wait for Portus carrier or tune its PHY.
- Do not add a gateway for `portus0`.
- Keep Portus setup asynchronous so boot does not wait for it.

---

### Task 1: Configure Portus static address asynchronously

**Files:**
- Modify: `meta-lumen/recipes-core/network/lumen-eth-static.bb`
- Modify: `meta-lumen/recipes-core/network/lumen-eth-static/interfaces`
- Modify: `meta-lumen/recipes-core/network/lumen-eth-static/lumen-eth-static`
- Keep unchanged: `meta-lumen/recipes-core/udev/lumen-udev-rules/99-lumen-devices.rules`

**Interfaces:**
- The recipe renders the interfaces template and init script using the existing `ETH_STATIC_IP` pattern and a new `PORTUS_STATIC_IP` recipe variable.
- The init script keeps its existing `start|stop` interface and adds Portus-specific setup in a separate background subshell.

- [x] **Step 1: Add recipe variable and render it into both configuration files**

In `lumen-eth-static.bb`, define:

```bitbake
PORTUS_STATIC_IP = "192.168.1.10"
```

Keep the existing `ETH_STATIC_IP` value. Update both rendering commands in
`do_install()` to substitute both template variables:

```bitbake
    sed -e "s/@ETH_STATIC_IP@/${ETH_STATIC_IP}/g" \
        -e "s/@PORTUS_STATIC_IP@/${PORTUS_STATIC_IP}/g" \
        ${WORKDIR}/interfaces \
        > ${D}${sysconfdir}/network/interfaces

    sed -e "s/@ETH_STATIC_IP@/${ETH_STATIC_IP}/g" \
        -e "s/@PORTUS_STATIC_IP@/${PORTUS_STATIC_IP}/g" \
        ${WORKDIR}/lumen-eth-static \
        > ${D}${sysconfdir}/init.d/lumen-eth-static
```

- [x] **Step 2: Add the static Portus stanza**

Append this stanza to `meta-lumen/recipes-core/network/lumen-eth-static/interfaces`, leaving the existing `lo` and `eth0` stanzas untouched:

```text
auto portus0
iface portus0 inet static
    address @PORTUS_STATIC_IP@
    netmask 255.255.255.0
```

- [x] **Step 3: Add independent background setup to the init script**

Inside the `start)` branch, after the existing `eth0` background subshell, add a second background subshell. It waits up to five seconds for `/sys/class/net/portus0`, brings the interface up, and applies the templated address as `/24`. It must not wait for `carrier` or call `ethtool`.

Use this block, substituting the recipe-rendered address for `@PORTUS_STATIC_IP@`:

```sh
        (
            i=0
            while [ "$i" -lt 100 ] && [ ! -e /sys/class/net/portus0 ]; do
                sleep 0.05
                i=$((i + 1))
            done

            if [ ! -e /sys/class/net/portus0 ]; then
                echo "lumen-eth-static: portus0 did not appear" >&2
                exit 1
            fi

            if ! ip link set portus0 up; then
                echo "lumen-eth-static: failed to bring up portus0" >&2
                exit 1
            fi

            if ! ip addr replace @PORTUS_STATIC_IP@/24 dev portus0; then
                echo "lumen-eth-static: failed to assign address to portus0" >&2
                exit 1
            fi
        ) &
```

Do not change the current `eth0` block or the `stop)` behavior. The existing udev rule already assigns the `portus0` name and remains unchanged.

- [x] **Step 4: Build the affected recipe install task**

Run:

```sh
bitbake -c install -f lumen-eth-static
```

Expected: BitBake completes the task successfully.

- [x] **Step 5: Verify generated runtime configuration**

Get the recipe work directory:

```sh
WORKDIR=$(bitbake -e lumen-eth-static | sed -n 's/^WORKDIR="\([^"]*\)"$/\1/p')
test -n "$WORKDIR"
```

```sh
grep -F -A3 'iface portus0 inet static' "$WORKDIR/image/etc/network/interfaces"
grep -F 'ip addr replace 192.168.1.10/24 dev portus0' "$WORKDIR/image/etc/init.d/lumen-eth-static"
grep -F 'address 192.168.1.10' "$WORKDIR/image/etc/network/interfaces"
grep -F 'address 192.0.5.10' "$WORKDIR/image/etc/network/interfaces"
```

Expected: generated files contain Portus address `192.168.1.10`, netmask `255.255.255.0`, and unchanged eth0 address `192.0.5.10`; the script has no Portus carrier wait and still contains the existing `eth0` PHY tuning.

- [x] **Step 6: Check patch whitespace and review scope**

Run:

```sh
git diff --check
git diff -- meta-lumen/recipes-core/network/lumen-eth-static.bb meta-lumen/recipes-core/network/lumen-eth-static/interfaces meta-lumen/recipes-core/network/lumen-eth-static/lumen-eth-static
```

Expected: no whitespace errors; only Portus recipe/template/startup changes, with the udev name rule and existing `eth0` fast path unchanged.
