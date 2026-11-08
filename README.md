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

## Build from Git (Reproducible)

This repo contains everything needed to produce the exact same image on any Ubuntu 22.04 machine.
All external layer versions are pinned by commit SHA in `kas/lumen-common.yml`. 

### 1. Prerequisites (one-time)

**Ubuntu 22.04** (native or VM). Minimum ~120 GB free disk, 8 GB RAM.

```bash
# Install kas
pip3 install kas

# Install Yocto host dependencies
sudo apt-get install -y \
    gawk wget git diffstat unzip texinfo gcc build-essential \
    chrpath socat cpio python3 python3-pip python3-pexpect \
    xz-utils debianutils iputils-ping python3-git python3-jinja2 \
    libegl1-mesa libsdl1.2-dev xterm python3-subunit \
    mesa-common-dev zstd liblz4-tool file locales libacl1 \
    device-tree-compiler
```

### 2. Clone and build

```bash
git clone <this-repo-url> lumen
cd lumen

# Pick your module variant:
kas build kas/lumen-orin-nx-16gb.yml    # Orin NX 16GB  (p3767-0000)
kas build kas/lumen-orin-nx-8gb.yml     # Orin NX 8GB   (p3767-0001)
kas build kas/lumen-orin-nano-8gb.yml   # Orin Nano 8GB (p3767-0003)
kas build kas/lumen-orin-nano-4gb.yml   # Orin Nano 4GB (p3767-0004)
```

kas will automatically:
- Clone **poky**, **meta-openembedded**, **meta-tegra** at the pinned commits
- Generate `build/conf/local.conf` and `build/conf/bblayers.conf`
- Run `bitbake lumen-image-minimal`

Expected build time: **2–4 hours** on a 20-core machine.

### Docker installation and build

Docker is an alternative to installing the Yocto host dependencies above. Run
the following host commands from the Lumen repository. Allow at least 120 GB
free disk space and 8 GB RAM for the image build.

#### 1. Install Docker on the Ubuntu host

```bash
sudo apt-get update
sudo apt-get install -y docker.io
sudo systemctl enable --now docker
sudo docker version
```

The examples use `sudo` for Docker access; the build helper still passes your
original user UID/GID into the container so generated files remain user-owned.

#### 2. Download the Scarthgap build environment

Authenticate with your Artifactory credentials when prompted, then pull the
shared image:

```bash
sudo docker login artifactory.rafael.co.il
sudo docker pull artifactory.rafael.co.il/rtsis-docker-local-ww/yocto-scarthgap:v1.4.0
```

Use this HTTPS registry URL, not the older `:6080` endpoint. Access requires the
appropriate Rafael network connection and Artifactory permissions.

The shared image is preferred for consistent package versions. If you need to
build the container image locally instead, use the infrastructure repository:

```bash
(
    cd ~/project/embedded_sw/embedded_sw_infrastructures/docker/yocto/docker-yocto-scarthgap
    sudo ./build.sh
)
```

This produces `yocto-scarthgap:v1.4.0`. It still needs access to the Dockerfile's
Artifactory base image, internal GitLab, and package repositories; it is not an
offline workaround for registry access.

#### 3. Prepare caches and start the container

The default host cache directories must exist and be writable by your user:

```bash
mkdir -p /media/ranshal/jetson/shared/downloads /media/ranshal/jetson/shared/sstate
sudo ./build-in-docker.sh lumen-orin-nx-16gb
```

The helper mounts this repository at its original absolute host path inside
the container and uses that path as the working directory. Yocto records the
absolute `TMPDIR` path, so preserving it lets an existing native build directory
be reused without a "TMPDIR has changed location" error. The helper also mounts
the download and sstate-cache directories configured in `kas/lumen-common.yml`.
Use a matching variant name from the supported-variants table for another module.

For a locally built container image, replace the launch command with:

```bash
sudo env LUMEN_YOCTO_DOCKER_IMAGE=yocto-scarthgap:v1.4.0 \
    ./build-in-docker.sh lumen-orin-nx-16gb
```

To use different existing, writable host cache directories:

```bash
sudo env LUMEN_DL_CACHE=/path/to/downloads LUMEN_SSTATE_CACHE=/path/to/sstate \
    ./build-in-docker.sh lumen-orin-nx-16gb
```

#### 4. Install kas and build Lumen inside the container

The Scarthgap image does not include `kas`. Run these commands inside its shell:

```bash
python3 -m pip install --user --upgrade pip
python3 -m pip install --user 'kas==4.8.2'
export PATH="$HOME/.local/bin:$PATH"
kas --version
kas build kas/lumen-orin-nx-16gb.yml
```

Replace the kas config for another module. Keep the container open until the
build finishes; the helper starts an interactive shell rather than running
BitBake as the container's top-level command. This is an incremental build if
the repository already has build outputs; it also reuses the shared caches.
Starting a new container does not make the Yocto build clean.

The container is removed when you exit its shell, so install kas again in each
new container. The repository, caches, and build outputs remain on the host.

#### 5. Access the image outside Docker

The repository is a bind mount, not container-local storage. Its path is the
same inside and outside Docker. For NX 16GB, the generated files are directly
accessible from a host terminal:

```bash
ls -lh build/tmp/deploy/images/lumen-orin-nx-16gb/lumen-image-minimal-*.rootfs.ext4
ls -lh build/tmp/deploy/images/lumen-orin-nx-16gb/lumen-image-minimal-*.tegraflash.tar.gz
```

No `docker cp` or Docker image export is needed. The rootfs and tegraflash
archive are the Lumen deliverables; the Scarthgap Docker image is only the build
environment.

### 3. Output

```
build/tmp/deploy/images/<machine>/
├── lumen-image-minimal-<machine>.rootfs.ext4    # rootfs
└── lumen-image-minimal-<machine>.tegraflash.tar.gz  # flash package
```

### Run a built image in QEMU

QEMU boots an existing build output; it does not build the image. Install QEMU
and `socat` on the Ubuntu host:

```bash
sudo apt-get install -y qemu-system-arm socat
```

Build the Lumen variant first, then pass its machine name to `run-qemu.sh`:

```bash
kas build kas/lumen-orin-nano-8gb.yml
./run-qemu.sh lumen-orin-nano-8gb
```

The launcher accepts `lumen-orin-nx-16gb`, `lumen-orin-nx-8gb`,
`lumen-orin-nano-8gb`, or `lumen-orin-nano-4gb`. In another terminal, follow
the boot log and connect to the serial login:

```bash
tail -f /tmp/lumen-qemu/lumen-orin-nano-8gb/console.log
socat - UNIX-CONNECT:/tmp/lumen-qemu/lumen-orin-nano-8gb/console.sock
```

Set `LUMEN_QEMU_LOGS=/path/to/log-root` to store logs and the serial socket
elsewhere; the launcher creates a machine-specific directory underneath it.
The rootfs is attached in snapshot mode, so changes made in the VM are discarded
when QEMU exits.

This is basic software testing on QEMU's generic ARM `virt` machine, not a
Jetson hardware emulator. It does not provide the Jetson GPU, camera, or
carrier-board peripherals, and its user-mode networking is not equivalent to
the Lumen board's network. Boot also depends on the existing Tegra kernel
supporting QEMU's virtio devices; a QEMU-specific Yocto target is not built.

### Build version on target

On the device, read the image version and build provenance with:

```sh
cat /etc/lumen-build-info
```

The release version starts at `1.0.0` and is manually bumped by changing
`LUMEN_BUILD_VERSION` in
`meta-lumen/recipes-core/lumen-build-info/lumen-build-info.bb`. The build
timestamp and Git commit identify the specific image build and source revision.

### 4. Flash

```bash
cd build/tmp/deploy/images/lumen-orin-nx-16gb/
tar -xf lumen-image-minimal-lumen-orin-nx-16gb.tegraflash.tar.gz
cd <extracted-dir>
sudo ./initrd-flash
```

> The Aerium BSP patches (UART, CSI, BCT, USB OTG) are applied automatically
> at build time. Do **not** run `scripts/bsp/Aerium-Lumen-BSP-Orin-NX-Nano.sh` manually.

For an Ethernet-only rootfs update without a serial connection, configure the
target's `DEVICE_IP`, `DEVICE_SSH_USER`, and `DEVICE_SSH_PASS` in `.env`, then run
from the repository root:

```bash
./flash_eth_initrd.sh --rootfs-only --no-serial \
    --image build/tmp/deploy/images/lumen-orin-nx-16gb/lumen-image-minimal-lumen-orin-nx-16gb.rootfs.ext4
```

Use the image path for the actual module variant. `SERIAL_PORT=""` also disables
serial. This mode requires host `debugfs` and `/etc/lumen-build-info` in the image:
success requires SSH to return and the device's build metadata to match the
selected image. The new image must provide SSH and reachable network settings.
There is no console supervision or recovery if boot fails. Keep power stable
throughout flashing; an SSH timeout is an unknown result, not permission to
power-cycle.

### Pinned layer versions

| Layer | Commit | Branch |
|---|---|---|
| poky | `d4576e3c` | scarthgap (Yocto 5.0 LTS) |
| meta-openembedded | `d8cc4e44` | scarthgap |
| meta-tegra (OE4T) | `d2613418` | scarthgap (L4T 36.5.0 / JetPack 6.x) |

To update layers: change the commit SHAs in `kas/lumen-common.yml` and re-test.

---

## Detailed Build Reference

### Step 1 — Host requirements

- Ubuntu 22.04 (native or VM)
- At least ~120 GB free disk space
- 8+ GB RAM recommended (16 GB for parallel builds)

### Step 2 — Install kas

```bash
pip3 install kas
```

Verify:
```bash
kas --version   # should print 4.x or 5.x
```

### Step 3 — Install Yocto host dependencies

```bash
sudo apt-get install -y \
    gawk wget git diffstat unzip texinfo gcc build-essential \
    chrpath socat cpio python3 python3-pip python3-pexpect \
    xz-utils debianutils iputils-ping python3-git python3-jinja2 \
    libegl1-mesa libsdl1.2-dev xterm python3-subunit \
    mesa-common-dev zstd liblz4-tool file locales libacl1 \
    device-tree-compiler
```

### Step 4 — Clone this repository

```bash
git clone <this-repo-url> lumen
cd lumen
```

### Step 5 — (Optional) Configure shared download/sstate cache

If you have an existing Yocto downloads or sstate-cache directory, point to it
to avoid re-downloading sources on subsequent builds:

```bash
# Example: export to override kas local_conf defaults
export BB_ENV_PASSTHROUGH_ADDITIONS="DL_DIR SSTATE_DIR"
export DL_DIR=/path/to/shared/downloads
export SSTATE_DIR=/path/to/shared/sstate-cache
```

Or just let kas create `downloads/` and `sstate-cache/` next to the `build/` directory
(default — no action needed).

### Step 6 — Accept NVIDIA binary license

During the first build, BitBake will stop and ask you to accept the NVIDIA binary
license. To pre-accept it (non-interactive builds / CI), the kas common config already
sets:

```
LICENSE_FLAGS_ACCEPTED = "commercial nvidia-tegra"
```

This is already in `kas/lumen-common.yml` — no action needed.

### Step 7 — Build

Pick the module variant you are building for and run:

```bash
# Orin NX 16GB  (p3767-0000)
kas build kas/lumen-orin-nx-16gb.yml

# Orin NX 8GB   (p3767-0001)
kas build kas/lumen-orin-nx-8gb.yml

# Orin Nano 8GB (p3767-0003)
kas build kas/lumen-orin-nano-8gb.yml

# Orin Nano 4GB (p3767-0004)
kas build kas/lumen-orin-nano-4gb.yml
```

kas will:
1. Clone poky, meta-openembedded, meta-tegra into `build/`
2. Generate `build/conf/local.conf` and `build/conf/bblayers.conf`
3. Run `bitbake lumen-image-minimal`

Expected duration: **2–4 hours** on a 20-core machine (first build).
Subsequent builds with a populated sstate-cache are much faster.

Build outputs land in:
```
build/tmp/deploy/images/<machine>/
```

### Step 8 — Flash

After a successful build:

```bash
cd build/tmp/deploy/images/lumen-orin-nx-16gb/
tar -xf lumen-image-minimal-lumen-orin-nx-16gb.tegraflash.tar.gz
cd <extracted-dir>
sudo ./initrd-flash
```

For other variants replace `lumen-orin-nx-16gb` with the machine name.

> **Note:** The Aerium BSP patches (UART, CSI, BCT, USB OTG) from
> `scripts/bsp/Aerium-Lumen-BSP-Orin-NX-Nano.sh` are applied **automatically at
> build time** by `meta-lumen`. Do **not** run the BSP script manually on the
> `Linux_for_Tegra` directory — it is only kept as a reference.

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

## Static Ethernet IP

The default `eth0` address is `192.0.5.10/24`. For a new image, change
`ETH_STATIC_IP` in `meta-lumen/recipes-core/network/lumen-eth-static.bb`;
the build inserts that address into both the boot script and the ifupdown
configuration.

On a **running device**, the address is present in two separate files:
`/etc/init.d/lumen-eth-static` (`IP=...`) sets it during boot, while
`/etc/network/interfaces` (`address ...`) is used by manual `ifup eth0`.
If changing the address directly on the device, update **both** files to
the same value. Otherwise boot and manual interface setup can use different
addresses. On the device these files are independent; changing the Yocto
recipe only affects a rebuilt image, not an already running device.

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
