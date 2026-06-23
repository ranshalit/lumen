# Boot Optimization Plan

## Defer Driver Module Loading for Faster Prompt

### Background

`S06modutils.sh` runs synchronously in `rcS.d`, loading 4 kernel modules
**before** getty spawns the login prompt:

| Module     | Purpose                  |
|------------|--------------------------|
| `nvgpu`    | NVIDIA GPU driver (slow) |
| `nvmap`    | NVIDIA memory mapping    |
| `pwm-fan`  | Fan speed control        |
| `ina3221`  | Current/voltage monitor  |

None of these are required for a login prompt to appear.

### Proposed Change

Same pattern used for Ethernet deferral (commit `1559a73`):

1. **`modutils_%.bbappend`** — remove `S06modutils.sh` from `rcS.d`
2. **`sysvinit-inittab_%.bbappend`** — add `inittab once` entry:
   ```
   mod:5:once:/etc/init.d/modutils.sh
   ```
   Fires concurrently with getty → prompt wins the race, modules load in background.

### Trade-offs

| Concern | Impact |
|---------|--------|
| `pwm-fan` deferred | Fan runs at default speed for ~1–2 s — harmless |
| `nvgpu` deferred | GPU unavailable for a few seconds after prompt — no GPU needed at shell |
| `ina3221` deferred | Power monitoring delayed briefly — no user impact |
| App at login needs `nvgpu` immediately | Must wait — same async contract as Ethernet |

### Status

- [ ] Implement `modutils_%.bbappend` to remove `S06modutils.sh` from `rcS.d`
- [ ] Add `mod:5:once` entry to `sysvinit-inittab_%.bbappend`
- [ ] Build and measure prompt time improvement
