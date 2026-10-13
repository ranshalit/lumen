# Lumen Build Version Design

## Goal

Make each Lumen image's release version and build provenance readable on the
device.

## Design

Add a dedicated `lumen-build-info` Yocto package to the minimal image. It
installs `/etc/lumen-build-info`, a plain-text file containing:

- Manually maintained semantic version, initially `1.0.0`
- UTC build timestamp
- Full Git SHA for the source commit used to build
- Yocto machine variant
- Yocto release version

On the target, users can inspect it with `cat /etc/lumen-build-info`. Release
version stays unchanged across rebuilds until intentionally bumped; timestamp
and Git SHA identify each image build/source revision. The package must include
the Git SHA in its BitBake task signature so cached package output cannot
silently report an earlier source commit.

## Alternatives

- Generate the file in the existing image postinstall hook: fewer files, but
  mixes build metadata with unrelated rootfs user setup.
- Add metadata to `/etc/issue`: visible at login, but awkward for scripts and
  less explicit to query.

The dedicated package is preferred because it isolates the feature and provides
a stable file interface.

## Validation

Rebuild the configured image and inspect `/etc/lumen-build-info` inside the
resulting rootfs. Verify the version starts at `1.0.0`, timestamp is UTC, the
full SHA matches the source commit, and machine and Yocto release match the
build configuration.
