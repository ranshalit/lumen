# Lumen Build Version Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make an image's release version and build provenance readable with `cat /etc/lumen-build-info`.

**Architecture:** Add a focused Yocto package that writes a plain-text metadata file and install that package in `lumen-image-minimal`. Set release version to `1.0.0` in the recipe and bump it manually; calculate the full Git SHA during BitBake parsing so it is part of the install task signature.

**Tech Stack:** Yocto BitBake recipe, kas image build, ext4 image inspection with `debugfs`.

## Global Constraints

- The release version starts at `1.0.0` and changes only by a manual tracked edit.
- Include UTC build timestamp, full Git SHA, Yocto machine variant, and Yocto release version.
- Install the metadata at `/etc/lumen-build-info`.
- Include the Git SHA in the BitBake task signature so cached package output cannot silently report an earlier source commit.

---

### Task 1: Package and expose image build metadata

**Files:**
- Create: `meta-lumen/recipes-core/lumen-build-info/lumen-build-info.bb`
- Modify: `meta-lumen/recipes-images/images/lumen-image-minimal.bb`
- Modify: `README.md`

**Interfaces:**
- Consumes: BitBake `DATETIME`, `MACHINE`, `DISTRO_VERSION`, and current Git HEAD.
- Produces: `/etc/lumen-build-info` with `VERSION`, `BUILD_TIMESTAMP_UTC`, `GIT_COMMIT`, `MACHINE`, and `YOCTO_RELEASE`; package name `lumen-build-info`.

- [ ] **Step 1: Create the metadata recipe**

Create `meta-lumen/recipes-core/lumen-build-info/lumen-build-info.bb`:

```bitbake
SUMMARY = "Lumen image build information"
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

LUMEN_BUILD_VERSION = "1.0.0"
LUMEN_BUILD_GIT_SHA = ""

python __anonymous() {
    import os
    import subprocess

    recipe_dir = os.path.dirname(d.getVar("FILE"))
    git_sha = subprocess.check_output(
        ["git", "-C", recipe_dir, "rev-parse", "HEAD"],
        text=True,
    ).strip()
    d.setVar("LUMEN_BUILD_GIT_SHA", git_sha)
}

do_install() {
    install -d ${D}${sysconfdir}
    cat > ${D}${sysconfdir}/lumen-build-info <<EOF
VERSION=${LUMEN_BUILD_VERSION}
BUILD_TIMESTAMP_UTC=${DATETIME}
GIT_COMMIT=${LUMEN_BUILD_GIT_SHA}
MACHINE=${MACHINE}
YOCTO_RELEASE=${DISTRO_VERSION}
EOF
}

FILES:${PN} = "${sysconfdir}/lumen-build-info"
```

The Python function must fail the parse/build if Git SHA lookup fails; do not emit a blank or fallback value. The shell task references `LUMEN_BUILD_GIT_SHA`, so the commit affects the task signature.

- [ ] **Step 2: Install the package in the image**

Add `lumen-build-info \` to the `IMAGE_INSTALL` list in `meta-lumen/recipes-images/images/lumen-image-minimal.bb`.

- [ ] **Step 3: Document target lookup and manual release bump**

Add a short section to `README.md` stating that the target reports metadata with:

```sh
cat /etc/lumen-build-info
```

Document that maintainers manually update `LUMEN_BUILD_VERSION` in `meta-lumen/recipes-core/lumen-build-info/lumen-build-info.bb` for a release bump; timestamp and Git SHA vary by build/source revision.

- [ ] **Step 4: Rebuild the configured image**

Run:

```bash
rtk kas build kas/lumen-orin-nx-16gb.yml
```

Expected: kas exits successfully and regenerates the Orin NX 16GB rootfs image.

- [ ] **Step 5: Verify metadata in the produced rootfs**

Run:

```bash
rtk proxy debugfs -R 'cat /etc/lumen-build-info' build/tmp/deploy/images/lumen-orin-nx-16gb/lumen-image-minimal-lumen-orin-nx-16gb.rootfs.ext4
```

Expected: five non-empty fields; `VERSION=1.0.0`; `GIT_COMMIT` is the full 40-character current commit SHA; `MACHINE=lumen-orin-nx-16gb`; and `YOCTO_RELEASE` matches the build's `DISTRO_VERSION`. `BUILD_TIMESTAMP_UTC` is BitBake's UTC `DATETIME`.
