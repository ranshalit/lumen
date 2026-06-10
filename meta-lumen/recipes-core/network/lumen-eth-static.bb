# Configure persistent static IP on the Lumen wired Ethernet interface
# via ifupdown (/etc/network/interfaces).
# eth0 is brought up asynchronously at boot to avoid blocking the init sequence.

SUMMARY = "Configure static Ethernet IP via ifupdown (async)"
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

PACKAGE_ARCH = "${MACHINE_ARCH}"
COMPATIBLE_MACHINE = "(lumen)"

# lumen-eth-static owns /etc/network/interfaces, replacing the default init-ifupdown file
RCONFLICTS:${PN} += "init-ifupdown"
RREPLACES:${PN} += "init-ifupdown"
RPROVIDES:${PN} += "init-ifupdown"

SRC_URI = "file://interfaces file://lumen-eth-static"

S = "${WORKDIR}"

inherit update-rc.d

INITSCRIPT_NAME = "lumen-eth-static"
INITSCRIPT_PARAMS = "start 40 S ."

do_configure[noexec] = "1"
do_compile[noexec] = "1"

do_install() {
    install -d ${D}${sysconfdir}/network
    install -m 0644 ${WORKDIR}/interfaces \
        ${D}${sysconfdir}/network/interfaces

    install -d ${D}${sysconfdir}/init.d
    install -m 0755 ${WORKDIR}/lumen-eth-static \
        ${D}${sysconfdir}/init.d/lumen-eth-static
}

FILES:${PN} += "${sysconfdir}/network/interfaces ${sysconfdir}/init.d/lumen-eth-static"
