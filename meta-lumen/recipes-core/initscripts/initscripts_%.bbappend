# Remove dmesg.sh from rcS.d — the kernel ring buffer is always accessible
# live via `dmesg`, so saving it to /var/log/dmesg on every boot is wasteful.

do_install:append() {
    rm -f ${D}${sysconfdir}/init.d/dmesg.sh
    rm -f ${D}${sysconfdir}/rcS.d/S38dmesg.sh
}
