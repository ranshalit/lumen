# Boot Optimization Notes — Orin Nano Yocto BSP

## Overview

This document summarizes boot optimization strategies for the Jetson Orin Nano using busybox init (`INIT_MANAGER = "mdev-busybox"`).

---

## Fast Prompt vs. Fast Boot

Deferring services to the background gives a **faster prompt appearance**, but does **not reduce total initialization time**.

| Metric | Effect |
|---|---|
| Time to usable shell prompt | ✅ Significantly reduced |
| Time to ethernet/CUDA ready | ❌ Same — happens in background |
| Total system initialization time | ❌ Same or slightly longer |

---

## How Deferred Init Works

With busybox init, you control exactly what must finish *before* the prompt appears vs. what runs *after/alongside* it.

```
Power on
    │
    ▼
kernel boots (fixed, ~1-2s)
    │
    ▼
rcS-minimal runs (mount, mdev — ~0.5s)
    │
    ├──► getty spawns → PROMPT APPEARS  ← "boot" from user's perspective
    │
    └──► background: ifup, autoneg, CUDA daemons still running...
```

Think of it like a PC desktop — you see the login screen while services are still loading in the background.

---

## What to Keep in rcS (blocking)

These must complete before the prompt:

- `mount -a` (proc, sysfs, devtmpfs)
- `mdev -s` (device nodes)
- Root filesystem checks

## What to Defer (background/manual)

These can run after the prompt appears:

- `ifup` / `udhcpc` (DHCP + autoneg)
- Ethernet autonegotiation
- NFS mounts
- Any network-dependent service
- CUDA kernel modules and daemons

---

## inittab Pattern

```sh
# /etc/inittab
::sysinit:/etc/init.d/rcS-minimal    # kernel, mdev, mount — nothing network
ttyTCU0::respawn:/sbin/getty ...     # shell prompt ← appears here
::once:/sbin/ifup eth0 &             # autoneg + DHCP in background
::once:/etc/init.d/load-cuda &       # CUDA loads in background
```

The `&` on deferred entries runs them in the background — prompt appears while they initialize concurrently.

---

## Ethernet / Autonegotiation

Ethernet autonegotiation is one of the **biggest boot delay culprits** — it can take 3–5 seconds. Options:

1. **Defer to background** (UX win, same total time)
2. **Force link speed** to skip negotiation entirely (actual time reduction):
   ```sh
   ethtool -s eth0 speed 1000 duplex full autoneg off
   ```

---

## CUDA Deferred Loading

| Component | Nature | Defer strategy |
|---|---|---|
| Kernel modules (`nvhost`, `nvmap`, etc.) | Kernel | `modprobe` on-demand or background rcS script |
| CUDA runtime libraries | Userspace | Zero boot cost — load when app calls them |
| CUDA daemons (`nvpmodel`, etc.) | Userspace | Start manually or via background init script |

---

## Actual Boot Time Reduction (not just UX)

To genuinely reduce boot time (not just hide latency):

1. **Strip unused kernel drivers** — biggest impact
2. **`DISTRO_FEATURES:remove`** — already applied in `kas.yml` ✅
3. **Disable unused kernel modules** from loading at boot
4. **NVMe storage** — already in use ✅, fast by default
5. **Force ethernet link speed** — skip autoneg

---

## Application Readiness

> ⚠️ If you defer init of ethernet/CUDA, your **application must validate interface readiness** before using them.

Deferred init shifts the readiness burden from the init system to the application.

### Poll until ready patterns

```sh
# Wait for ethernet IP
while ! ip addr show eth0 | grep -q "inet "; do sleep 0.1; done

# Wait for ethernet link up
while ! ip link show eth0 | grep -q "UP"; do sleep 0.1; done

# Wait for CUDA device node
while [ ! -e /dev/nvhost-ctrl ]; do sleep 0.1; done
```

### Check before use

```sh
[ -e /dev/nvhost-ctrl ] || { echo "CUDA not ready"; exit 1; }
```

### App launcher wrapper

```sh
wait_for_cuda() { while [ ! -e /dev/nvhost-ctrl ]; do sleep 0.1; done; }
wait_for_net()  { while ! ip link show eth0 | grep -q "UP"; do sleep 0.1; done; }

wait_for_cuda
wait_for_net
exec /usr/bin/my-application
```

### Tradeoff summary

| Approach | Boot-to-prompt | App complexity |
|---|---|---|
| Wait for everything before prompt | Slow | App assumes everything is ready |
| Defer to background | Fast | App must validate readiness |
