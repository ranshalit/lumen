# Force the usb2-0 dual-role USB port into host mode at boot.
#
# Replaces the previous `SUBSYSTEM=="usb_role", ATTR{role}="host"` udev rule
# (see meta-lumen/recipes-core/udev/lumen-udev-rules). That rule made a
# coldplug udev worker write the `role` sysfs attribute, which blocks in the
# tegra padctl role-switch driver and stalls `udevadm settle` for its full
# 120s default — freezing the whole boot (~8s -> ~130s boot-to-ping).
#
# This init script does the same role write but from a detached background
# subshell, so it can never block the boot path.

SUMMARY = "Force usb2-0 dual-role port to host mode at boot (non-blocking)"
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

PACKAGE_ARCH = "${MACHINE_ARCH}"
COMPATIBLE_MACHINE = "(lumen)"

SRC_URI = "file://lumen-usb2-host"

S = "${WORKDIR}"

do_configure[noexec] = "1"
do_compile[noexec] = "1"

do_install() {
    install -d ${D}${sysconfdir}/init.d
    install -m 0755 ${WORKDIR}/lumen-usb2-host \
        ${D}${sysconfdir}/init.d/lumen-usb2-host

    # Run in rcS.d after S04udev (so the padctl role-switch node exists) and
    # after S07lumen-eth-static. The script backgrounds all work, so this
    # ordering only affects when the write is *kicked off*, never boot timing.
    install -d ${D}${sysconfdir}/rcS.d
    ln -sf ../init.d/lumen-usb2-host \
        ${D}${sysconfdir}/rcS.d/S08lumen-usb2-host
}

FILES:${PN} += "${sysconfdir}/init.d/lumen-usb2-host ${sysconfdir}/rcS.d/S08lumen-usb2-host"
