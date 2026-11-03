# Lumen QEMU Runner Design

## Goal

Provide a Hadron-style way to boot an already-built Lumen ARM64 image in QEMU
for basic software and console testing, without changing Lumen's Yocto build
targets.

## Design

- Add a root-level `run-qemu.sh` that requires one of the four supported Lumen
  machine names as its argument.
- Resolve the matching kernel (`Image`) and
  `lumen-image-minimal-$MACHINE.rootfs.ext4` under
  `build/tmp/deploy/images/$MACHINE/`.
- Check the machine argument, required artifacts, and `qemu-system-aarch64`
  before launch; print actionable errors rather than silently selecting a
  different build.
- Boot the ARM64 kernel on QEMU's generic `virt` machine with a virtio root
  disk and headless PL011 console. Pass QEMU-specific kernel arguments rather
  than the Lumen board's physical UART console setting.
- Use QEMU snapshot mode so writes made during a session do not modify the
  built rootfs. Use a per-machine log directory, defaulting under
  `/tmp/lumen-qemu`, configurable through `LUMEN_QEMU_LOGS`. Save boot output
  to `console.log` and expose an interactive Unix socket for serial login.
- Document host dependencies, invocation, log/socket access, and the limits of
  the emulation in the root README.

This is a best-effort software boot path using the existing Tegra kernel and
rootfs, not hardware emulation. QEMU's generic virtual machine does not emulate
Jetson peripherals, GPU, camera, or carrier-board behavior. Boot success
depends on the existing kernel having the needed virtio support; if it does
not, this scope does not add a separate QEMU-specific Yocto target.

## Alternatives

- A fixed launcher for one Lumen variant would be simpler, but would not serve
  the other three existing build variants.
- A separate `qemuarm64` Yocto target would provide a QEMU-oriented kernel and
  image, but requires a separate build configuration and changes the scope
  beyond reusing existing Lumen artifacts.

## Validation

- Check shell syntax and run focused invocation/preflight tests for supported
  and unsupported machines and missing build artifacts.
- When QEMU and a built Lumen image are available, launch the VM and confirm
  boot output reaches the configured console log and the serial socket accepts
  a connection. Confirm the original rootfs remains unchanged after shutdown.
- Review the README instructions against the script's actual arguments and
  output paths.
