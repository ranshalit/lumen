# Remove bootlogd init scripts — serial console is available for boot debugging.
# bootlogd adds S07 to rcS.d and S99stop-bootlogd to rc[2-5].d, both unnecessary.

do_install:append() {
    rm -f ${D}${sysconfdir}/init.d/bootlogd
    rm -f ${D}${sysconfdir}/init.d/stop-bootlogd
    rm -f ${D}${sysconfdir}/rcS.d/S07bootlogd
    rm -f ${D}${sysconfdir}/rc2.d/S99stop-bootlogd
    rm -f ${D}${sysconfdir}/rc3.d/S99stop-bootlogd
    rm -f ${D}${sysconfdir}/rc4.d/S99stop-bootlogd
    rm -f ${D}${sysconfdir}/rc5.d/S99stop-bootlogd
    rm -f ${D}${sysconfdir}/default/volatiles/01_bootlogd
}
