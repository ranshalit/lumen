# Defer Ethernet bring-up to after the login prompt.
# Fires concurrently with getty when entering runlevel 5 — prompt wins the
# race to the terminal, eth0 comes up a second or two later in the background.
# lo (loopback) is handled automatically by the kernel (127.0.0.1 always up).

do_install:append() {
    echo "" >> ${D}${sysconfdir}/inittab
    echo "# Ethernet: deferred to after prompt (non-blocking)" >> ${D}${sysconfdir}/inittab
    echo "eth0:5:once:/etc/init.d/lumen-eth-static start" >> ${D}${sysconfdir}/inittab
}
