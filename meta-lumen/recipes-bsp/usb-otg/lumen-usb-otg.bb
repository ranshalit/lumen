# meta-lumen/recipes-bsp/usb-otg/lumen-usb-otg/lumen-usb-otg.bb
#
# Sets the USB2 OTG port on the Lumen carrier to "device" mode at boot.
#
# The Lumen carrier wires USB2-0 as a device (gadget) port.
# Without this, the port defaults to host mode and enumeration fails.
#
# Derived from: scripts/bsp/Aerium-Lumen-BSP-Orin-NX-Nano.sh (fix_usb_otg)

SUMMARY = "Set USB2-0 OTG role to device mode on boot"
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

COMPATIBLE_MACHINE = "(lumen)"

SRC_URI = " \
    file://lumen-usb-otg \
"

S = "${WORKDIR}"

inherit update-rc.d

INITSCRIPT_NAME = "lumen-usb-otg"
INITSCRIPT_PARAMS = "start 05 S ."

do_configure[noexec] = "1"
do_compile[noexec] = "1"

do_install() {
    install -d ${D}${sysconfdir}/init.d
    install -m 0755 ${WORKDIR}/lumen-usb-otg \
        ${D}${sysconfdir}/init.d/lumen-usb-otg
}

FILES:${PN} += "${sysconfdir}/init.d/lumen-usb-otg"
