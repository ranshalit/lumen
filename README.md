## General

Aerium Lumen board — Yocto-based Linux build for the NVIDIA Jetson Orin NX / Orin Nano (p3767 SOM).

Product docs: https://docs.aerium.co.il/Product%20Manuals/Lumen

---

## Supported Variants

| kas config | Module | SKU |
|---|---|---|
| `kas/lumen-orin-nx-16gb.yml` | Jetson Orin NX 16GB | p3767-0000 |
| `kas/lumen-orin-nx-8gb.yml` | Jetson Orin NX 8GB | p3767-0001 |
| `kas/lumen-orin-nano-8gb.yml` | Jetson Orin Nano 8GB | p3767-0003 |
| `kas/lumen-orin-nano-4gb.yml` | Jetson Orin Nano 4GB | p3767-0004 |

---

## Prerequisites

- Ubuntu 22.04 host (native or VM)
- **kas** build tool:
  ```bash
  pip3 install kas
  ```
- Yocto dependencies:
  ```bash
  sudo apt-get install -y gawk wget git diffstat unzip texinfo gcc build-essential \
      chrpath socat cpio python3 python3-pip python3-pexpect xz-utils debianutils \
      iputils-ping python3-git python3-jinja2 libegl1-mesa libsdl1.2-dev xterm \
      python3-subunit mesa-common-dev zstd liblz4-tool file locales libacl1 \
      dtc
  ```
- NVIDIA BSP binary license acceptance (prompted automatically during build)

---

## Build

Pick the module variant you are building for:

```bash
# Orin NX 16GB
kas build kas/lumen-orin-nx-16gb.yml

# Orin NX 8GB
kas build kas/lumen-orin-nx-8gb.yml

# Orin Nano 8GB
kas build kas/lumen-orin-nano-8gb.yml

# Orin Nano 4GB
kas build kas/lumen-orin-nano-4gb.yml
```

Build outputs are in `build/tmp/deploy/images/<machine>/`.

---

## Flashing

After a successful build, the `tegraflash` tarball contains everything needed:

```bash
cd build/tmp/deploy/images/lumen-orin-nx-16gb/
tar -xf lumen-image-minimal-lumen-orin-nx-16gb.tegraflash.tar.gz
cd <extracted-dir>
sudo ./initrd-flash  # or: sudo ./flash.sh <board-config> mmcblk0p1
```

> **Note:** The hardware patches from `scripts/bsp/Aerium-Lumen-BSP-Orin-NX-Nano.sh`
> (UART, CSI, BCT, USB OTG) are applied automatically at build time via `meta-lumen`.
> You do **not** need to run that script manually.

---

## BSP Patches Applied

| Patch | File | Recipe |
|---|---|---|
| Enable UART `serial@3110000` (ttyTHS0) | kernel DTS | `linux-tegra_%.bbappend` |
| Fix serial aliases (`serial2`/`serial3`) | kernel DTS | `linux-tegra_%.bbappend` |
| CSI port-index=0, `serial_a` | kernel DTS + camera DTBO | `linux-tegra_%.bbappend` |
| EEPROM BCT `cvb_eeprom_read_size = <0x0>` | tegra-bootfiles BCT | `tegra-bootfiles_%.bbappend` |
| USB OTG device mode | systemd service | `lumen-usb-otg.bb` |

The original BSP reference script is at `scripts/bsp/Aerium-Lumen-BSP-Orin-NX-Nano.sh`.

---

## Repository Layout

```
lumen/
├── kas/                      # kas build configs (one per module variant)
├── meta-lumen/               # custom BSP layer
│   ├── conf/
│   │   ├── layer.conf
│   │   └── machine/          # one .conf per module variant
│   ├── recipes-bsp/
│   │   ├── device-tree/      # DTS patch files (UART, CSI, serial aliases)
│   │   ├── tegra-bootfiles/  # BCT EEPROM bbappend
│   │   └── usb-otg/          # USB OTG systemd service
│   ├── recipes-images/       # lumen-image-minimal.bb
│   └── recipes-kernel/       # linux-tegra bbappend (applies DTS patches)
└── scripts/bsp/              # original Aerium BSP reference script
```

> **DTS patch note:** The patch files under `meta-lumen/recipes-bsp/device-tree/lumen-dtb-patches/patches/`
> contain the intended changes but use placeholder context lines. Before the first build,
> generate real patches against the L4T kernel source by running:
> ```bash
> # After kas fetches sources:
> cd build/tmp/work-shared/<machine>/kernel-source
> # Edit the DTS files, then:
> git diff > ../../../../../meta-lumen/recipes-bsp/device-tree/lumen-dtb-patches/patches/0001-lumen-uart-enable-serial-3110000.patch
> ```

