# Boot Optimization Candidates — Round 2

Derived from walking all commits on `orin_yocto/autoresearch/boot-opt-v2`
(`79731243` → HEAD) and comparing each experiment against the current lumen repo.
Lumen baseline: ~32s. orin_yocto achieved 6s from a 30s baseline.

## Interview Results

| # | Optimization | Decision | Est. Saving | Notes |
|---|---|---|---|---|
| OPT-8 | `UBOOT_EXTLINUX_TIMEOUT = "0"` | ✅ Approved | −1 to −3s | Menu never used; recovery via reflash |
| OPT-3 | MB1/BPMP serial logging silence (`TEGRA_MB1_LOG_LEVEL=0`, `TEGRA_BPMP_SERIAL_LOGGING=0`) | ✅ Approved | −0.5 to −1.5s | Serial only used post-kernel |
| OPT-7 | `KERNEL_ARGS` append: `quiet loglevel=0 audit=0` | ✅ Approved | 0 to −0.3s | `dmesg` post-boot sufficient for diagnostics |
| OPT-2 | Eliminate boot initramfs (NVMe=y built-in, `root=/dev/nvme0n1p1`) | ✅ Approved | −1.5 to −2s | Rootfs always on nvme0n1p1; A/B is kernel-only |
| OPT-4 | Remove `nvidia-kernel-oot-display` from `MACHINE_EXTRA_RDEPENDS` | ✅ Approved (display only — fan control, nvstartup, Ethernet modules must stay) | −0.1 to −0.2s | orin_yocto blanked all of `MACHINE_EXTRA_RDEPENDS`; lumen can only remove the display module |
| OPT-5 | DTB disable: `aconnect@2900000` (audio) + `spi@3210000/3230000/3270000` | ✅ Approved (audio+SPI only — monitoring HW and camera RCE must stay) | ~−0.1s | orin_yocto disabled 7 nodes; lumen keeps `actmon`/`hwpm`/`mc-hwpm` (tegrastats/Nsight) and `rce-fabric` (camera) |
| OPT-1 | DTB disable: `pcie@141e0000` (confirmed empty slot) | ✅ Approved (1 controller only — Ethernet, NVMe, and unknown Microchip slot must stay) | −0.5 to −0.8s | orin_yocto disabled 3 controllers; lumen keeps `140a0000` (Ethernet), `14160000` (NVMe), `14100000` (Microchip 1055:7430, purpose unknown) |
| OPT-6 | `CONFIG_HZ_100` — reduce kernel timer frequency to 100Hz | ❌ Rejected | — | Real-time control requires sub-10ms timer precision |

## PCIe Topology (from actual Lumen boot log)

| Controller | Bus | PCI Device ID | Hardware | Verdict |
|---|---|---|---|---|
| `pcie@140a0000` | 0008 | `10ec:8168` | Realtek RTL8168 GbE Ethernet | 🔴 Keep |
| `pcie@14100000` | 0001 | `1055:7430` | Microchip/SMSC (unknown) | 🟡 Keep (unknown) |
| `pcie@14160000` | 0004 | `126f:2263` | Silicon Motion NVMe SSD | 🔴 Keep |
| `pcie@141e0000` | 0007 | *(empty — bus released)* | Nothing | ✅ Disable |

## Projected Result

| Scenario | Saving | Boot Time |
|---|---|---|
| Conservative (low estimates) | −3.7s | ~28s |
| Optimistic (high estimates) | −7.8s | ~24s |
