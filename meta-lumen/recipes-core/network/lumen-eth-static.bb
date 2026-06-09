# Configure persistent static IP on the Lumen wired Ethernet interface
# through systemd-networkd (which is enabled in the image).

SUMMARY = "Configure static Ethernet IP via systemd-networkd"
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

PACKAGE_ARCH = "${MACHINE_ARCH}"
COMPATIBLE_MACHINE = "(lumen)"

SRC_URI = "file://10-enP8p1s0.network"

S = "${WORKDIR}"

do_configure[noexec] = "1"
do_compile[noexec] = "1"

do_install() {
    install -d ${D}${sysconfdir}/systemd/network
    install -m 0644 ${WORKDIR}/10-enP8p1s0.network \
        ${D}${sysconfdir}/systemd/network/10-enP8p1s0.network
}

FILES:${PN} += "${sysconfdir}/systemd/network/10-enP8p1s0.network"
