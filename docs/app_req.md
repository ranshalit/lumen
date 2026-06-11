# Application Docker Requirements Analysis

Analysis of whether `meta-lumen` supports running the Docker application defined in `scripts/docker-compose.yaml` and `scripts/anchor-compose.yaml`.

---

## 🟥 Blocking Issues

### 1. Docker/container stack not installed — and layer not even visible
`lumen-image-minimal.bb` has no `docker`, `containerd`, or container tooling in `IMAGE_INSTALL`. More critically, `meta-virtualization` is **not in `BBLAYERS`** — meaning the recipes aren't visible to bitbake at all. Simply adding packages to `IMAGE_INSTALL` is not sufficient; the layer must be added first.

### 2. `virtualization` missing from `DISTRO_FEATURES`
`lumen-common.inc` strips down `DISTRO_FEATURES`. Both `nvidia-container-toolkit` and `nvidia-docker` declare `REQUIRED_DISTRO_FEATURES = "virtualization"` — they won't build without it. This must be fixed alongside adding the layer.

### 3. No NVIDIA container runtime integration
`dmc`, `renderd`, and `matchd` all use `runtime: nvidia`. The `nvidia-container-toolkit` recipe exists in `meta-tegra` but is not added to the image. Without it, all GPU containers will fail to start.

### 4. NVIDIA runtime setup incompatible with busybox init
`nvidia-container-toolkit` only ships a **systemd** unit (`nvidia-container-setup.service`) to generate `/etc/nvidia-container-runtime/config.toml` before Docker starts. The image uses **busybox init** — the systemd unit will never run, so GPU runtime config is never generated and all `runtime: nvidia` containers fail.

Two options to resolve, both low effort:

- **Option A — busybox init script (~1 hour):** Add a `S50nvidia-container-setup` init script via bbappend that calls the existing `generate-config.sh` at boot. Config is regenerated each boot in `/run/nvidia-container-runtime/config.toml`.
- **Option B — static baked config (~2–3 hours, recommended):** Since Lumen is fixed hardware (Orin NX/Nano), generate the config once on a dev board, capture `config.toml`, and install it as a static file via bbappend. No runtime generation needed — simpler, faster boot, one less failure point.

### 5. Docker Compose V2 not available
No recipe for `docker-compose` (v2 plugin) exists in `meta-lumen` or `meta-tegra`. The YAML files require **Compose V2 specifically** — `docker-compose.yaml` uses top-level `include:` which v1 does not support.

### 6. Application image sources undefined
`anchor-compose.yaml` references build contexts `./services/server/run` and `./services/m3d/run` — these paths don't exist in this repo. `docker-compose.yaml` references pre-built images with no registry prefix. An image source strategy (registry, tarballs, or separate build repo) must be defined.

---

## 🟧 Important Concerns

### 7. Serial/camera device aliases missing from udev
`/dev/ttyPixhawk`, `/dev/ttyTeensy`, `/dev/ttyHodakev`, `/dev/ttyCameraSerial` are bind-mounted in the compose files but no udev rules exist in `meta-lumen` to create these aliases. Affected containers will fail to start.

### 8. Kernel networking — scoped risk
`strip-phase1-net.cfg` disables `CONFIG_BRIDGE_NETFILTER` and `CONFIG_NF_CONNTRACK`. Most app services use `network_mode: host` so this is not an issue for them. However, **dozzle** uses a published port (`13579:8080`) and is not host-networked — bridge/NAT prerequisites may be needed for it.

### 9. Root filesystem too small for Docker
`lumen-image-minimal.bb` sizes the rootfs at ~2 GiB. Docker engine + `/var/lib/docker` layer storage + GPU container images can easily exceed this. Docker data directory placement must be planned explicitly.

---

## 🟨 Deployment Notes

### 10. Environment variables not provisioned
The compose files require env vars (`GCU_VERSION`, `DMC_VERSION`, `INFRA_DIR`, etc.) with no `.env` file or startup script in the repo. Additionally, `$USER`-based bind mount paths (e.g. `/home/$USER/project_outputs/`) are fragile when running under a service or as root.

---

## 💡 Docker + Login Prompt: Can They Start Concurrently?

**Yes — using the same `inittab once` pattern already in use for eth0.**

### Key distinction: rcS vs inittab `once`

| Location | Behavior |
|----------|----------|
| `rcS.d/` | Sequential, **blocks boot** — login prompt waits until it finishes |
| `inittab once` at runlevel 5 | **Concurrent with getty** — correct place for Docker |

`rcS.d` is the wrong place for Docker — it would delay the login prompt until `dockerd` is fully up (~3–5 s on Orin). The eth0 bring-up script (`eth0:5:once:...`) proves the right pattern: an `inittab once` entry at runlevel 5 fires at the same time as getty so the login prompt appears immediately.

### Recommended boot sequence

```
rcS.d    →  (nothing Docker-related — keep it fast)
runlevel 5 → getty  (login prompt)             ← simultaneous
           → once:  dockerd + docker compose up ←
```

### Does Issue #4 (NVIDIA runtime config) block Docker startup?

**No — `dockerd` itself does not need `config.toml` to start.** The toolkit config is only read when a container with `runtime: nvidia` is actually launched. So:

- `dockerd` start → ✅ unaffected by Issue #4
- GPU containers (`dmc`, `renderd`, `matchd`) → ❌ fail at launch without `config.toml`

**Option B (pre-baked static `config.toml`)** is the cleanest fix here: the file is present on the rootfs at first boot, zero runtime overhead, no init script required. GPU containers find it immediately when `docker compose up` launches them.

---

## ✅ What Is There

- `meta-tegra` contains recipes for `docker-moby`, `nvidia-container-toolkit`, `nvidia-docker` — infrastructure exists, just not wired in
- Built kernel has `CONFIG_OVERLAY_FS`, `CONFIG_VETH`, and `CONFIG_BRIDGE` available as modules (confirmed in built config)
- All core app services use `network_mode: host`, minimizing kernel networking requirements

---

## Required Changes to Make It Work

1. Add `meta-virtualization` to `BBLAYERS`
2. Add `virtualization` to `DISTRO_FEATURES`
3. Add `docker moby-containerd nvidia-docker` to `IMAGE_INSTALL`
4. Add a Compose V2 provider recipe compatible with `include:` syntax
5. Resolve NVIDIA runtime setup for sysvinit (init script or pre-generated config)
6. Add udev rules for `/dev/ttyPixhawk`, `/dev/ttyTeensy`, `/dev/ttyHodakev`, `/dev/ttyCameraSerial`
7. Plan Docker storage placement (separate partition or volume) given rootfs size constraints
8. Define application image source strategy (registry pull or separate build repo)
