# Lumen Board — App Deployment Guide

This document describes how to deploy and update a Docker-based application on the
Lumen board. It is intended for the application team.

---

## Overview

The BSP provides the boot infrastructure. The application team provides the app.

| Responsibility | Owner |
|---|---|
| Boot OS, start dockerd, start app at boot | BSP (this repo) |
| Docker images (`.tar.gz`) | App team |
| `docker-compose.yaml` | App team |
| Config files, mission data | App team |

The BSP init script (`S60lumen-app`) runs at every boot and executes:
```
docker compose -f /opt/dragonfly/docker-compose.yaml --project-name lumen up -d
```

Everything under `/opt/dragonfly/` is owned by the app team. **No BSP rebuild or
reflash is needed to update the application.**

---

## First-Time Deployment

### Step 1 — Flash the board

Flash the Lumen BSP image for your specific module variant. Each variant has its
own KAS config and produces a separate tegraflash tarball.

**Variant → machine name mapping:**

| Module | Machine name | SKU |
|---|---|---|
| Orin Nano 8GB | `lumen-orin-nano-8gb` | p3767-0003 |
| Orin Nano 4GB | `lumen-orin-nano-4gb` | p3767-0004 |
| Orin NX 8GB | `lumen-orin-nx-8gb` | p3767-0001 |
| Orin NX 16GB | `lumen-orin-nx-16gb` | p3767-0000 |

> ⚠️ The machine name must match the physical module. Flashing the wrong image onto the wrong board will likely brick it.

**Build the image** (BSP team, from the lumen project root):

```bash
MACHINE=lumen-orin-nano-8gb   # adjust per variant
kas build kas/$MACHINE.yml
```

The output tarball will be at:
```
build/tmp/deploy/images/$MACHINE/lumen-image-minimal-$MACHINE.rootfs.tegraflash.tar.gz
```

**Flash the board:**

```bash
MACHINE=lumen-orin-nano-8gb   # adjust per variant
TARBALL=build/tmp/deploy/images/$MACHINE/lumen-image-minimal-$MACHINE.rootfs.tegraflash.tar.gz

# 1. Reboot board into USB recovery (APX) mode
python /home/ranshal/.copilot/skills/serial-console/scripts/serial_session.py reboot-recovery

# 2. Confirm the board is visible as an APX USB device
lsusb | grep -i "nvidia\|0955"

# 3. Extract and flash
FLASH_TMP=$(mktemp -d /tmp/lumen-flash-XXXX)
tar -xf "$TARBALL" -C "$FLASH_TMP"
cd "$FLASH_TMP" && sudo ./initrd-flash

# 4. Clean up (initrd-flash creates root-owned files)
cd / && sudo rm -rf "$FLASH_TMP"
```

Flashing typically takes 3–10 minutes. The board reboots automatically when done.

#### Entering recovery mode manually (no serial console)

If you don't have serial access, you can enter USB recovery mode by following these steps:

1. **Power off** the board completely.
2. **Connect** a USB-C cable between the board's USB recovery port and your host PC.
3. **Press and hold** the **RECOVERY** button on the carrier board.
4. **Apply power** (or press the POWER button if the board is already connected to power).
5. **Release** the RECOVERY button after ~2 seconds.
6. Verify the board is visible as an APX device on your host:
   ```bash
   lsusb | grep -i "nvidia\|0955"
   # Expected: Bus ... ID 0955:7523 NVIDIA Corp. APX
   ```
7. Proceed with the extract-and-flash steps above.

> 💡 On the Lumen carrier board the RECOVERY button is labeled **REC** and is located next to the POWER button.

The board boots to a login prompt automatically. Docker starts at boot but
`/opt/dragonfly/` is empty so no containers run yet.

### Step 2 — Copy your deployment package to the board

```bash
scp -r <your-package-folder> nexus@<board-ip>:/tmp/app/
```

Your package folder must contain:
- `install.sh` (see requirements below)
- `docker-compose.yaml`
- All Docker image tarballs (`*.tar.gz`)
- Any config files your compose file references

### Step 3 — Run install.sh on the board

```bash
ssh nexus@<board-ip>
cd /tmp/app
sudo bash install.sh
```

`install.sh` must:
1. **Check free disk space** — abort if less than ~2 GB free
2. **Stop running app containers** (for updates):
   ```bash
   docker compose -f /opt/dragonfly/docker-compose.yaml --project-name lumen down 2>/dev/null || true
   ```
3. **Prune old images before loading new ones** (prevents rootfs bloat — images are ~1-5 GB each):
   ```bash
   docker images --format "{{.Repository}}:{{.Tag}}" | grep "<your-image-prefix>" | xargs -r docker rmi -f
   ```
4. **Load new images:**
   ```bash
   for file in *.tar.gz; do docker load -i "$file"; done
   ```
5. **Deploy to `/opt/dragonfly/`:**
   ```bash
   mkdir -p /opt/dragonfly
   cp docker-compose.yaml /opt/dragonfly/
   cp <config-files> /opt/dragonfly/
   chown -R nexus:nexus /opt/dragonfly
   ```

See `dummy_docker/install.sh` in this repo as a reference implementation.

### Step 4 — Reboot

```bash
sudo reboot
```

The BSP init script picks up `/opt/dragonfly/docker-compose.yaml` automatically
and starts your containers. No manual intervention needed.

---

## Updating the Application

Same steps as first-time deployment — `install.sh` handles cleanup of old images
and replaces the compose file. Then reboot (or restart without reboot):

```bash
sudo /etc/init.d/lumen-app restart
```

---

## docker-compose.yaml Requirements

Your compose file must follow these rules to work correctly on the Lumen board:

### 1. Network: host mode only

The board kernel has NAT/iptables stripped. Bridge networking will not work.
**All services must use:**
```yaml
network_mode: host
```

### 2. NVIDIA runtime for GPU services

Services that need GPU access:
```yaml
runtime: nvidia
```

### 3. Share `/dev` for serial device access

The BSP installs udev symlinks for application serial devices:

| Symlink | Device | Notes |
|---|---|---|
| `/dev/ttyTeensy` | On-board UART (ttyTHS1) | Always present |
| `/dev/ttyHodakev` | On-board UART (ttyS2) | Always present |
| `/dev/ttyPixhawk` | USB serial (067b:2303 or 10c4:ea60) | Present when plugged in |
| `/dev/ttyCameraSerial` | USB serial (Cypress 04b4:7510) | Present when plugged in |

To access these inside the container, mount the host `/dev`:
```yaml
volumes:
  - /dev:/dev
```

### 4. Crash recovery

Add `restart: unless-stopped` to all long-running services:
```yaml
restart: unless-stopped
```

### 5. Log output directory

The board creates `/home/nexus/project_outputs/dockers/` for app logs.
Mount it into your containers:
```yaml
volumes:
  - /home/nexus/project_outputs/dockers/:/app/logs
```

### 6. No `ports:` mapping — use `network_mode: host`

Instead of:
```yaml
ports:
  - "13579:8080"   # ❌ requires bridge networking
```

Use:
```yaml
network_mode: host          # ✅
environment:
  - MY_APP_PORT=13579       # configure the app to listen on the right port
```

### Full example compose snippet

```yaml
version: '3.9'

services:
  my-service:
    image: my-app:1.0.0-arm64
    container_name: my-service
    network_mode: host
    runtime: nvidia
    restart: unless-stopped
    volumes:
      - /dev:/dev
      - /home/nexus/project_outputs/dockers/:/app/logs
    environment:
      - MY_APP_PORT=8080
```

---

## Useful Commands on the Board

```bash
# Check running containers
docker ps

# View container logs
docker logs <container-name>

# Start / stop app manually
sudo /etc/init.d/lumen-app start
sudo /etc/init.d/lumen-app stop
sudo /etc/init.d/lumen-app restart
sudo /etc/init.d/lumen-app status

# Check available disk space
df -h /

# List loaded docker images
docker images

# Remove a specific image manually
docker rmi <image>:<tag>
```

---

## Reference Implementation

See `dummy_docker/` in this repository for a minimal working example that follows
all the patterns described above:

```
dummy_docker/
├── install.sh          ← reference install script
├── docker-compose.yaml ← reference compose file
└── validate.sh         ← reference app entrypoint (checks network, GPU, serial)
```

---

## Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| Containers don't start at boot | `/opt/dragonfly/docker-compose.yaml` missing | Run `install.sh` |
| `cannot connect to Docker daemon` | dockerd still starting | Wait 10s and retry; init script handles this automatically |
| `image not found` | Image not loaded | Re-run `install.sh` |
| Container keeps restarting | App crash / missing file | Check `docker logs <container>` |
| Disk full after update | Old images not pruned | Add `docker rmi` cleanup to `install.sh` |
| Serial device not found in container | `/dev` not mounted | Add `- /dev:/dev` to volumes |
| Network connection fails at startup | eth0 not up yet | Add retry loop in app entrypoint; eth0 comes up a few seconds after boot |
