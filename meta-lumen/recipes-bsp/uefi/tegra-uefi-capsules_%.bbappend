# Lumen disables the boot initramfs globally (INITRAMFS_IMAGE="" in
# lumen-common.inc, because NVMe+PCIe+PHY are built into the kernel). That
# leaves tegra-uefi-capsules' BUP generator with an empty dependency
# ("${INITRAMFS_IMAGE}:do_image_complete" -> ":do_image_complete"), so the
# recipe fails to parse with "Nothing PROVIDES ''".
#
# The UEFI capsule (and the BUP payload it wraps) only needs an initramfs to
# assemble the kernel BUP image; restore a minimal one *for this recipe only*
# so the bootloader (bl_only) capsule -> tegra-bl.cap can be generated. This
# does NOT re-enable the boot initramfs for the main image build.
INITRAMFS_IMAGE = "tegra-minimal-initramfs"

# ── Capsule version control ───────────────────────────────────────────────────
# The stock signing class sets BOTH the FMP fw-version and the lowest-supported
# version (lsv) to the L4T BSP version (36.5.0 = 0x240500), i.e. identical to the
# firmware already in QSPI. UEFI may then SKIP applying the capsule (not newer),
# making "did our firmware get written?" ambiguous.
#
# Real update flow: derive the fw-version MONOTONICALLY per build from the lumen
# layer's git commit count, so every new build wraps a strictly-newer capsule and
# UEFI always applies it (ESRT fw_version / last_attempt_version advance, A/B slot
# flips). The value is (stock 0x240500 + commit_count) kept in the low bits:
#   0x240500 + N   (e.g. commit 446 -> 0x2406BE)
# Keep --lsv at the stock 0x240500 so we do NOT raise the anti-rollback floor
# (the stock firmware can still be re-applied).
#
# NOTES / overrides:
#   - Rebuilding the SAME commit yields the SAME version, so UEFI will skip a
#     redundant re-apply. To force a re-apply of an unchanged tree, override at
#     build time, e.g.  CAPSULE_FW_VERSION=0x2407FF bitbake tegra-uefi-capsules
#   - If git is unavailable, falls back to the stock+1 value (0x240501).
def lumen_capsule_fw_version(d):
    import subprocess
    base = 0x240500
    try:
        layerdir = d.getVar('CAPSULE_LAYER_DIR')
        n = subprocess.check_output(
            ['git', '-C', layerdir, 'rev-list', '--count', 'HEAD'],
            stderr=subprocess.DEVNULL).decode().strip()
        return "0x%06X" % (base + (int(n) & 0xFFFF))
    except Exception:
        return "0x240501"

# Capture THIS bbappend's directory at parse time (:=). At expansion time THISDIR
# points at the main recipe (meta-tegra), so we must snapshot the meta-lumen path
# here to count the LUMEN repo's commits (the thing that actually changes builds).
CAPSULE_LAYER_DIR := "${THISDIR}"
CAPSULE_FW_VERSION ?= "${@lumen_capsule_fw_version(d)}"
CAPSULE_LSV ?= "${BSP_VERSION32}"

sign_uefi_capsules() {
    export PYTHONPATH="${PYTHONPATH}:${PYTHON_BASETOOLS}"
    if [ -e ${B}/${BUPFILENAME}.bl_only.bup-payload ]; then
        python3 ${PYTHON_BASETOOLS}/Capsule/GenerateCapsule.py \
            -v --encode --monotonic-count 1 \
            --fw-version "${CAPSULE_FW_VERSION}" \
            --lsv "${CAPSULE_LSV}" \
            --guid "${GUID}" \
            --signer-private-cert "${UEFI_CAPSULE_SIGNER_PRIVATE_CERT}" \
            --other-public-cert "${UEFI_CAPSULE_OTHER_PUBLIC_CERT}" \
            --trusted-public-cert "${UEFI_CAPSULE_TRUSTED_PUBLIC_CERT}" \
            -o ./tegra-bl.cap \
            ${B}/${BUPFILENAME}.bl_only.bup-payload
    fi
    if [ -e ${B}/${BUPFILENAME}.kernel_only.bup-payload ]; then
        python3 ${PYTHON_BASETOOLS}/Capsule/GenerateCapsule.py \
            -v --encode --monotonic-count 1 \
            --fw-version "${CAPSULE_FW_VERSION}" \
            --lsv "${CAPSULE_LSV}" \
            --guid "${GUID}" \
            --signer-private-cert "${UEFI_CAPSULE_SIGNER_PRIVATE_CERT}" \
            --other-public-cert "${UEFI_CAPSULE_OTHER_PUBLIC_CERT}" \
            --trusted-public-cert "${UEFI_CAPSULE_TRUSTED_PUBLIC_CERT}" \
            -o ./tegra-kernel.cap \
            ${B}/${BUPFILENAME}.kernel_only.bup-payload
    fi
}
