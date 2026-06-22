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
# Bump fw-version one patch level (0x240501) so an apply is unambiguous: after
# reboot the device ESRT fw_version / last_attempt_version read the new value and
# the A/B bootloader slot flips. Keep --lsv at the stock 0x240500 so we do NOT
# raise the anti-rollback floor (the stock firmware can still be re-applied).
CAPSULE_FW_VERSION ?= "0x240501"
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
