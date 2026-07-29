# meta-lumen/recipes-core/udev/lumen-udev-rules.bb
#
# Installs udev symlink rules for application serial/camera devices.
# These rules replace the manual `cp *.rules /etc/udev/rules.d/` step
# that was previously done by hand on the JetPack/Ubuntu host before
# running docker compose. On Yocto every flash is a clean rootfs, so
# the rules must be baked into the image.
#
# Devices covered:
#   /dev/ttyPixhawk     — Pixhawk autopilot (USB serial)
#   /dev/ttyTeensy      — Teensy microcontroller (USB serial)
#   /dev/ttyHodakev     — Hodakev device (USB serial, VID:PID TBD)
#   /dev/ttyCameraSerial — Camera serial interface (USB serial, VID:PID TBD)
#
# The usb2-0 dual-role port host-mode switch used to live here as an
# `ATTR{role}="host"` rule but was moved to the lumen-usb2-host init script:
# writing the role attribute from a coldplug udev worker blocks `udevadm
# settle` for its full 120s default and freezes boot. See the note in
# 99-lumen-devices.rules and recipe lumen-usb2-host.bb.
#
# To find real VID:PID: udevadm info -a -n /dev/ttyUSB<N> on target hardware.

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
