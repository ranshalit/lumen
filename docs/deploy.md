# Deploying / Flashing the Lumen Image

This document is for **software staff** who receive a built image and need to flash it onto a Lumen board.

---

## What You Need

### Files

| Variant | File |
|---|---|
| Orin NX 16GB | `lumen-image-minimal-lumen-orin-nx-16gb.rootfs.tegraflash.tar.gz` |
| Orin NX 8GB | `lumen-image-minimal-lumen-orin-nx-8gb.rootfs.tegraflash.tar.gz` |
| Orin Nano 8GB | `lumen-orin-nano-8gb-flash.tar.gz` (flat directory, packaged by the build team) |

The tarball contains **everything** needed — bootloader, kernel, rootfs, flashing scripts. No separate BSP or SDK install is required.

### Host machine

- **Ubuntu 22.04** (native or VM)
- `python3` (pre-installed on Ubuntu)
- `sudo` access
- USB-C cable connected to the board's **recovery port**

---

## Step 1 — Enter Recovery Mode

1. Connect the USB-C recovery cable from the board to your host PC.
2. **Hold** the `RECOVERY` button on the board.
3. While holding `RECOVERY`, press and release `RESET` (or apply power if the board is off).
4. Release `RECOVERY` after ~2 seconds.

Verify the board is in recovery mode on the host:

```bash
lsusb | grep -i nvidia
# Expected output: Bus ... ID 0955:7523 NVIDIA Corp. APX
```

---

## Step 2 — Extract and Flash

```bash
# Create a working directory and extract into it
mkdir flash && cd flash
tar -xf ../lumen-image-minimal-<variant>.tegraflash.tar.gz

# Flash (initrd-flash is at the top level of the extracted contents)
sudo ./initrd-flash
```

Flashing takes approximately **5–10 minutes**. The board will reboot automatically when done.

---

## Optional Flags

| Flag | Description |
|---|---|
| `--skip-bootloader` | Flash rootfs only, skip bootloader partitions |
| `--erase-nvme` | Wipe the NVMe drive before flashing |
| `--usb-instance <id>` | Target a specific USB instance (for multiple boards) |

Example:

```bash
sudo ./initrd-flash --erase-nvme
```

---

## Troubleshooting

| Symptom | Fix |
|---|---|
| `lsusb` shows no NVIDIA device | Re-enter recovery mode; check USB-C cable |
| `Permission denied` on `./initrd-flash` | Run with `sudo` |
| Flash fails mid-way | Re-enter recovery mode and retry |
| Board does not boot after flash | Re-flash with `--skip-bootloader` omitted |

---

## Notes

- The Aerium BSP patches (UART, CSI, BCT, USB OTG) are **already baked into the image** — no manual patching needed.
- Do **not** run `scripts/bsp/Aerium-Lumen-BSP-Orin-NX-Nano.sh` — it is a build-time reference only.
- Root filesystem is on NVMe (`nvme0n1`). An NVMe drive must be installed in the board slot before flashing.
