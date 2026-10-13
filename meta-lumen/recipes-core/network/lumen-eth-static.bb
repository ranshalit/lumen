# Configure persistent static IP on the Lumen wired Ethernet interface
# via ifupdown (/etc/network/interfaces).
# eth0 is brought up via an inittab `once` entry after the login prompt,
# so it never blocks the boot path. lo is handled automatically by the kernel.

SUMMARY = "Configure static Ethernet IP via ifupdown (post-prompt)"
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

PACKAGE_ARCH = "${MACHINE_ARCH}"
COMPATIBLE_MACHINE = "(lumen)"

# Single source of truth for the address used by both configuration paths.
ETH_STATIC_IP = "192.0.5.10"
PORTUS_STATIC_IP = "192.168.1.10"

# lumen-eth-static owns /etc/network/interfaces, replacing the default init-ifupdown file
RCONFLICTS:${PN} += "init-ifupdown"
RREPLACES:${PN} += "init-ifupdown"
RPROVIDES:${PN} += "init-ifupdown"

# The init script uses ethtool to tune the PHY at link-up (skip 1000BASE-T
# training cycle, disable EEE/pause negotiation pages) for faster boot-to-ping.
RDEPENDS:${PN} += "ethtool"

SRC_URI = "file://interfaces file://lumen-eth-static"

S = "${WORKDIR}"

do_configure[noexec] = "1"
do_compile[noexec] = "1"

do_install() {
    install -d ${D}${sysconfdir}/network
    sed -e "s/@ETH_STATIC_IP@/${ETH_STATIC_IP}/g" \
        -e "s/@PORTUS_STATIC_IP@/${PORTUS_STATIC_IP}/g" \
        ${WORKDIR}/interfaces \
        > ${D}${sysconfdir}/network/interfaces
    chmod 0644 ${D}${sysconfdir}/network/interfaces

    install -d ${D}${sysconfdir}/init.d
    sed -e "s/@ETH_STATIC_IP@/${ETH_STATIC_IP}/g" \
        -e "s/@PORTUS_STATIC_IP@/${PORTUS_STATIC_IP}/g" \
        ${WORKDIR}/lumen-eth-static \
        > ${D}${sysconfdir}/init.d/lumen-eth-static
    chmod 0755 ${D}${sysconfdir}/init.d/lumen-eth-static

    # Run early in rcS.d (S07, just after S06modutils loads r8168) so the
    # script's background subshell can wait for /sys/class/net/eth0 and
    # start autoneg in parallel with the rest of rcS — this overlaps the
    # ~3s autoneg phase with the ~5s of remaining rcS work, saving ~2s
    # vs the previous "fire after runlevel 5 entry" approach.
    install -d ${D}${sysconfdir}/rcS.d
    ln -sf ../init.d/lumen-eth-static \
        ${D}${sysconfdir}/rcS.d/S07lumen-eth-static
}

FILES:${PN} += "${sysconfdir}/network/interfaces ${sysconfdir}/init.d/lumen-eth-static ${sysconfdir}/rcS.d/S07lumen-eth-static"
