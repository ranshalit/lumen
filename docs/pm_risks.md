# Suspend / Low-Power Mode Risk Analysis

Commits analyzed: `4637eaff24ebac2f52a99b70b41462f085f67cb5` → `HEAD`
Date: 2026-06-10

---

## 🔴 HIGH Risk

| Commit | Description | Risk |
|--------|-------------|------|
| `b9fb965` | EDK2 strips USB host, display, storage, ACPI thermal | Firmware resume paths depend on these; `Timeout=0` kills any PM boot window |
| `b1f1946` | Strips Bluetooth + **Tegra/HDA/HDMI audio** modules | Audio/BT are critical runtime-PM and resume paths |
| `e6f8d79` | Re-applies EDK2 strips including serial console + RAS/PRM | Loses resume debugging; `BOOT_UI_MENU_DISABLED` already caused a crash |

## 🟡 MEDIUM Risk

| Commit | Description | Risk |
|--------|-------------|------|
| `1559a73` | eth0 init moved to `inittab once` + USB OTG script removed | eth0 and USB role won't reinit after resume |
| `3ddbdb4` | Tegra services backgrounded (async) | Race if suspend happens mid-init or service needs re-establishment post-resume |
| `0a8e028` | Strips DP AUX bus drivers | DisplayPort retraining after resume will fail |

## 🟢 LOW Risk

| Commit | Description | Risk |
|--------|-------------|------|
| `8e5c1c1` | Async eth0 init.d script | No resume hook to re-run PHY config |
| `564aaec` | Strips WiFi/IPv6/CAN modules | Removes future WoWLAN / network-wake options |
| `d362798` | `MACHINE_FEATURES:remove = "alsa"` | Harder to validate audio/HDMI resume later |

---

## Detailed Notes

### `b9fb965` — EDK2 strip EMMC/SD/UFS/SATA/USB/Logo/Net/Shell + Timeout=0 + NVMe priority
EDK2 strips USB host, display, net boot, storage controllers, capsule support, and ACPI thermal zone, plus sets `Timeout=0` and NVMe-only priority.
Firmware/UEFI changes carry the biggest suspend risk. USB/display/storage/thermal features are exactly the kind of firmware pieces that resume/wake paths can depend on. `ACPI_THERMAL_ZONE_SINGLE` removal is especially PM-adjacent.
**Mitigate:** keep a non-stripped firmware profile for PM work; validate suspend/resume with unstripped EDK2 first.

### `b1f1946` — kernel: phase 2 — strip Bluetooth and audio codec modules
Strips Bluetooth and many audio modules including Tegra/HDA/HDMI audio platform pieces.
Audio and BT are common runtime-PM and wake/resume paths; removing Tegra audio platform pieces can break future audio/display resume support.
**Mitigate:** keep Tegra audio core/platform modules; strip only clearly board-irrelevant codecs/transports.

### `e6f8d79` — EDK2: re-add 7 safe strips (skip FIRMWARE_MANAGEMENT pending investigation)
Re-applies most EDK2 strips (except `FIRMWARE_MANAGEMENT`) including serial console and RAS/PRM, and reintroduces `BOOT_UI_MENU_DISABLED` which the next commit (`d60ae33`) confirms crashes firmware.
**Mitigate:** keep serial console for PM debugging; avoid stripping menu/PRM until sleep states are validated.

### `1559a73` — boot: strip unused features and defer ethernet for fast prompt
eth0 init moved to an `inittab once` entry (runs only at boot, not on resume), USB OTG role script removed, logging stripped.
eth0 and USB role won't reinitialize after resume; logging removal makes suspend/resume failures harder to debug; feature stripping (`bluetooth`, `wifi`, `x11`, `wayland`) narrows future wake/display options.
**Mitigate:** add PM hooks for USB role + eth0 reinit; keep logging in debug/PM builds; separate "fast-boot" vs "pm-capable" configs.

### `3ddbdb4` — boot: pre-gen SSH host keys and async tegra rc5 services
Backgrounds `nvsciipc_init` and `nvbootctrl verify` — Tegra service init becomes asynchronous and boot-only.
If suspend happens during init, or the service must be re-established after resume, ordering/race issues are likely.
**Mitigate:** ensure these services are resume-safe, or add explicit post-resume reinit hooks.

### `0a8e028` — kernel: phase 3 — strip display DRM and misc unused drivers
Strips `DRM_DP_AUX_BUS` and display bridge/encoder drivers while keeping `DRM_TEGRA`.
DP AUX is commonly needed for DisplayPort link retraining after resume; future external display resume may fail.
**Mitigate:** restore DP AUX / required bridge drivers in any suspend/display-capable build.

### `8e5c1c1` — lumen-eth-static: async non-blocking eth0 init.d script
Replaces blocking `pre-up` with a background SysV init script for `eth0`.
Async, boot-only network bring-up can race power transitions; no resume hook exists to re-run config if PHY/MAC resets after suspend.
**Mitigate:** add suspend/resume hook for eth0 reinit; avoid boot-only background logic for PM-sensitive devices.

### `564aaec` — kernel: phase 1 — strip unused networking modules
Strips IPv6/WiFi/CAN/netfilter-related kernel modules.
Removes possible future wake/low-power interfaces (WoWLAN, CAN wake, IPv6-based network wake scenarios).
**Mitigate:** keep a PM-oriented kernel fragment, or only strip modules proven irrelevant to future wake use-cases.

### `d362798` — boot: fix alsa removal
`MACHINE_FEATURES:remove = "alsa"` — not suspend-specific, but future audio/runtime-PM/audio-wake validation gets harder because the userspace audio stack integration is removed.
**Mitigate:** keep ALSA in a PM-capable image variant if audio or HDMI-audio resume may matter.

---

## Fan Control and ACPI Thermal Zone

### Does disabling `CONFIG_ACPI_THERMAL_ZONE_SINGLE` affect fan control?

No. On Jetson Orin, fan/thermal control goes through **BPMP** (Boot and Power Management
Processor), not the ACPI `\_TZ` thermal zone. The two paths are independent:

| Layer | Role |
|-------|------|
| EDK2 `CONFIG_ACPI_THERMAL_ZONE_SINGLE` (disabled in `b9fb965`) | Publishes `\_TZ` ACPI thermal zone in the ACPI tables handed to Linux |
| Linux `CONFIG_ACPI_THERMAL` | Consumes `\_TZ` tables for ACPI-based thermal throttling |
| Linux `tegra-bpmp-thermal` | **Independent** — talks directly to BPMP firmware, does not need ACPI `\_TZ` |

Disabling this EDK2 option has **no effect on fan control**. The BPMP thermal/fan path
continues to operate normally.

However, the ACPI thermal zone can be used by the OS for thermal throttling decisions
**during sleep transitions** on ACPI-compliant systems, which is why it remains noted as
a suspend/PM risk.

---

## initramfs and Power Management

initramfs is only required for **S4 hibernation** resume. All other suspend modes work without it:

| Suspend Type | initramfs needed? | Why |
|---|---|---|
| **S2idle** (`freeze`) | ❌ No | Pure CPU idle, kernel never exits |
| **S2RAM** (`mem`) | ❌ No | State saved to RAM, resumes directly back into running kernel — bootloader not involved |
| **SC7** (Tegra deep sleep) | ❌ No | Handled entirely by BPMP + TOS firmware |
| **S4 Hibernation** (`disk`) | ✅ Yes | Kernel image written to swap, then full power-off; on next boot initramfs must contain a `resume=` hook to restore the image before mounting rootfs |

### Project status

The device already exposes `freeze mem` as available suspend states. Both are initramfs-free
paths. SC7 on Jetson is the hardware-backed version of `mem`, also initramfs-free.

S4 hibernation would additionally require:
- A swap partition or swap file
- `CONFIG_HIBERNATION=y` in the kernel (not currently set)
- A `resume=` hook inside an initramfs

Since this project uses **BusyBox sysvinit** (no initramfs), **S4 hibernation is not
currently viable**. The `freeze`, `mem`, and SC7 paths are all usable without changes.

---

## Recommended Mitigations Before Adding Suspend Support

1. **Restore EDK2** USB/display/serial/thermal strips (`b9fb965`, `e6f8d79`) — or validate that firmware suspend S-states work without them.
2. **Keep Tegra audio** core/platform modules stripped in `b1f1946`.
3. **Add resume hooks** for `eth0` and USB OTG role (impacted by `1559a73`).
4. **Restore DP AUX** drivers if external display resume is needed (`0a8e028`).
5. **Separate configurations** — maintain a `pm-capable` image variant that preserves stripped features until suspend is fully validated.
