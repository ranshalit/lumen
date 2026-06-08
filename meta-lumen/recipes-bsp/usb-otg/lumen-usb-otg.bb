# meta-lumen/recipes-bsp/usb-otg/lumen-usb-otg/lumen-usb-otg.bb
#
# Sets the USB2 OTG port on the Lumen carrier to "device" mode at boot.
#
# The Lumen carrier wires USB2-0 as a device (gadget) port.
# Without this, the port defaults to host mode and enumeration fails.
#
# Derived from: scripts/bsp/Aerium-Lumen-BSP-Orin-NX-Nano.sh (fix_usb_otg)
# Replaces the BSP's sed patch on nv-l4t-usb-device-mode-start.sh with a
# clean systemd oneshot service.

SUMMARY = "Set USB2-0 OTG role to device mode on boot"
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

COMPATIBLE_MACHINE = "(lumen)"

SRC_URI = " \
    file://lumen-usb-otg.service \
"

S = "${WORKDIR}"

inherit systemd

SYSTEMD_SERVICE:${PN} = "lumen-usb-otg.service"
SYSTEMD_AUTO_ENABLE = "enable"

do_configure[noexec] = "1"
do_compile[noexec] = "1"

do_install() {
    install -d ${D}${systemd_system_unitdir}
    install -m 0644 ${WORKDIR}/lumen-usb-otg.service \
        ${D}${systemd_system_unitdir}/lumen-usb-otg.service
}

FILES:${PN} += "${systemd_system_unitdir}/lumen-usb-otg.service"
