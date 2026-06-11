# meta-lumen/recipes-core/udev/lumen-udev-rules.bb
#
# Installs udev symlink rules for application serial/camera devices:
#   /dev/ttyPixhawk, /dev/ttyTeensy, /dev/ttyHodakev, /dev/ttyCameraSerial
#
# NOTE: USB VID:PID values in 99-lumen-devices.rules are placeholders.
# Update them with real values from: udevadm info -a -n /dev/ttyUSB<N>

SUMMARY = "Lumen application udev device rules"
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

SRC_URI = "file://99-lumen-devices.rules"

S = "${WORKDIR}"

do_install() {
    install -d ${D}${sysconfdir}/udev/rules.d
    install -m 0644 ${WORKDIR}/99-lumen-devices.rules \
        ${D}${sysconfdir}/udev/rules.d/99-lumen-devices.rules
}

FILES:${PN} = "${sysconfdir}/udev/rules.d/99-lumen-devices.rules"
