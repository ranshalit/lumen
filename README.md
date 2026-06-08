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

> **DTS patches:** Applied via `sed`/`awk` in `do_patch:append:lumen` inside
> `meta-lumen/recipes-kernel/linux/linux-tegra_%.bbappend` — no patch context lines needed,
> works out of the box. Reference `.patch` stubs (for documentation) are in
> `meta-lumen/recipes-bsp/device-tree/lumen-dtb-patches/patches/docs/`.

---

## How This BSP Was Created

These are all the steps taken to build this repository from scratch.

### 1. Analyse the Aerium BSP zip

Downloaded from the Aerium portal:
```
Aerium-Lumen-BSP-Orin-NX-Nano-788eac7a3626ed370ed40dfbd36c3a89.zip
```

Inspected the contents — the zip contains a single pre-flash script:
```bash
unzip -l Aerium-Lumen-BSP-Orin-NX-Nano-788eac7a3626ed370ed40dfbd36c3a89.zip
# → Aerium-Lumen-BSP-Orin-NX-Nano.sh
```

Read and analysed the script to extract all hardware patches:
- targets `p3767-*` DTBs/DTBOs only (confirms SOM family is p3767)
- UART fix: enable `serial@3110000`, change compatible, add reset-names, fix serial aliases
- CSI fix: `port-index = <0x01>` → `<0x00>`, `serial_b` → `serial_a`
- Camera DTBO: same CSI fixes applied to camera overlay files
- BCT fix: `cvb_eeprom_read_size = <0x100>` → `<0x0>` (EEPROM not populated on Lumen)
- USB OTG: write `"device"` to `/sys/class/usb_role/usb2-0-role-switch/role` at boot

### 2. Determine Yocto approach

Researched meta-tegra (OE4T) on GitHub:
- Confirmed `scarthgap` branch supports JetPack 6.x / L4T 36.x
- Identified the four p3767 machine confs:
  - `p3768-0000-p3767-0000.conf` (Orin NX 16GB) — requires `orin-nx.inc`
  - `p3768-0000-p3767-0001.conf` (Orin NX 8GB)
  - `p3768-0000-p3767-0003.conf` (Orin Nano 8GB) — requires `orin-nano.inc`
  - `p3768-0000-p3767-0004.conf` (Orin Nano 4GB)
- Confirmed `tegra-bootfiles` recipe handles the BCT template (`BCT_TEMPLATE` variable)
- Confirmed `l4t-usb-device-mode` recipe handles USB gadget setup (but not the OTG role switch)

Choices made:
- **Layer:** `meta-tegra` (OE4T) — community standard, open-source, active
- **Build tool:** `kas` — reproducible YAML-driven builds, CI-friendly
- **Yocto release:** `scarthgap` (Yocto 5.0 LTS)
- **Image:** minimal headless (`core-image` base)

### 3. Create directory structure

```bash
mkdir -p kas
mkdir -p meta-lumen/conf/machine
mkdir -p meta-lumen/recipes-bsp/device-tree/lumen-dtb-patches/patches
mkdir -p meta-lumen/recipes-bsp/tegra-bootfiles
mkdir -p meta-lumen/recipes-bsp/usb-otg/lumen-usb-otg
mkdir -p meta-lumen/recipes-images
mkdir -p meta-lumen/recipes-kernel/linux
mkdir -p scripts/bsp
```

### 4. Extract and archive the BSP reference script

```bash
unzip ~/Downloads/Aerium-Lumen-BSP-Orin-NX-Nano-*.zip -d scripts/bsp/
```

The script is committed as `scripts/bsp/Aerium-Lumen-BSP-Orin-NX-Nano.sh` for reference.
It is **not** run during the Yocto build — its logic is replicated in recipes instead.

### 5. Write kas configs

- `kas/lumen-common.yml` — declares all layers (poky, meta-oe, meta-tegra, meta-lumen),
  sets `DISTRO=tegra`, `IMAGE_FSTYPES`, license acceptance, systemd, parallel build settings
- `kas/lumen-orin-{nx-16gb,nx-8gb,nano-8gb,nano-4gb}.yml` — each includes
  `lumen-common.yml` and sets `machine:` to the corresponding Lumen machine name

### 6. Write meta-lumen layer

**`conf/layer.conf`**
Registers the layer with `BBPATH`, `BBFILES`, depends on `meta-tegra`, compat `scarthgap`.

**`conf/machine/lumen-*.conf`** (4 files)
Each file:
- `require`s the matching upstream `p3768-0000-p3767-XXXX.conf` from meta-tegra (pulls in all
  SOM-level memory, SKU, flashing config)
- Prepends `"lumen:"` to `MACHINEOVERRIDES` so all Lumen-specific bbappends/recipes are
  activated only for Lumen builds
- Appends `console=ttyTHS0,115200` to `KERNEL_ARGS` (the UART enabled by our patch)

### 7. Write DTS patch infrastructure

**`meta-lumen/recipes-kernel/linux/linux-tegra_%.bbappend`**

Uses `do_patch:append:lumen` to run `sed`/`awk` directly on the kernel DTS source
files after they are fetched — mirroring the BSP script logic exactly, but without
needing `.patch` context lines:

- Iterates over `arch/arm64/boot/dts/nvidia/tegra234-p3768-0000+p3767-*.dts`
- **UART:** replaces compatible → `nvidia,tegra194-hsuart`, ensures `status = "okay"`,
  adds `reset-names = "serial"`, fixes serial2/serial3 aliases
- **CSI (base DTB):** `port-index = <0x00>`, `tegra_sinterface = "serial_a"`
- Iterates over `*camera*.dts` overlays, applies the same CSI fix using the awk
  script from the BSP (scoped to `i2c@0` block, VI port, channel endpoint)

**Reference patch stubs** (`patches/docs/`) — kept as documentation showing the
intended diff, to be regenerated as proper `git format-patch` output once the L4T
kernel source is available locally.

### 8. Write BCT bbappend

**`meta-lumen/recipes-bsp/tegra-bootfiles/tegra-bootfiles_%.bbappend`**
- `do_compile:prepend:lumen` runs a `sed` command on
  `bootloader/generic/BCT/tegra234-mb2-bct-misc-p3767-0000.dts` inside the fetched L4T
  source to replace `cvb_eeprom_read_size = <0x100>` with `<0x0>`

### 9. Write USB OTG systemd service

Instead of patching the binary `nv-l4t-usb-device-mode-start.sh` (as the BSP script does),
a clean systemd oneshot service was created:

**`lumen-usb-otg.service`** — runs before `network.target`, writes `"device"` to
`/sys/class/usb_role/usb2-0-role-switch/role`

**`lumen-usb-otg.bb`** — installs the service, inherits `systemd`, auto-enables it.
Uses `COMPATIBLE_MACHINE = "(lumen)"` so it only builds for Lumen targets.

### 10. Write image recipe

**`meta-lumen/recipes-images/lumen-image-minimal.bb`**
- Inherits `core-image`
- `IMAGE_INSTALL` adds: `packagegroup-base-tegra`, `lumen-usb-otg`, `openssh`, `htop`,
  `i2c-tools`, `util-linux`
- `COMPATIBLE_MACHINE = "(lumen)"` guards the recipe

### 11. Update .gitignore

Added entries for `build/`, `downloads/`, `sstate-cache/`, `.kas-*`.

