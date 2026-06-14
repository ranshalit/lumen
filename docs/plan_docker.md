# Plan: lumen-app Auto-Start at Boot

## Problem
The dummy Docker container (later: real operational app) must start at boot,
non-blocking, concurrently with the login prompt, after docker and NVIDIA runtime
are ready.

## Approach
Add a sysvinit `S60lumen-app` init script that:
1. Runs at rc5.d level 60 (after docker S20, after nvidia-container-setup S50)
2. Immediately backgrounds `docker run` and exits — so S99/getty are not delayed
3. Gracefully skips if the `lumen-base:latest` image isn't loaded yet (no crash)

The image (`lumen-base:latest`) is loaded separately (e.g. copied by ops team),
not baked into the rootfs.

## Boot sequence after change
```
S20docker.init        → dockerd starts
S50nvidia-container-setup → config.toml written
S60lumen-app          → docker run -d lumen-base /validate.sh  (backgrounds immediately)
S99rmnologin.sh       → login prompt unblocked
[inittab] getty       → login prompt appears
[inittab] eth0        → eth0 up (concurrent with getty)
[background] lumen-app container runs
```

## Files to create/modify

1. **meta-lumen/recipes-containers/lumen-app/lumen-app.bb** (new)
   - Minimal recipe: installs init script + rc5.d symlink
   - INITSCRIPT_NAME = "lumen-app", starts at level 60 runlevel 5

2. **meta-lumen/recipes-containers/lumen-app/lumen-app/S60lumen-app** (new)
   - Checks `docker image inspect lumen-base:latest` → skip gracefully if missing
   - Stops existing container on `stop`
   - Runs: `docker run -d --rm --runtime=nvidia --network host --privileged
             --name lumen-app lumen-base:latest /bin/sh /validate.sh`
   - Uses `&` — returns immediately, doesn't block boot

3. **meta-lumen/recipes-images/images/lumen-image-minimal.bb** (modify)
   - Add `lumen-app` to IMAGE_INSTALL

## Notes
- `--rm` so the container cleans itself up after validate.sh finishes
- `--name lumen-app` so `stop` can do `docker stop lumen-app`
- validate.sh from dummy_docker/ is the payload (baked into the image by run.sh)
- When replacing with real app: only the init script's `docker run` line changes
- No rebuild/reflash needed to load the image — `docker load -i <tar>` on device
