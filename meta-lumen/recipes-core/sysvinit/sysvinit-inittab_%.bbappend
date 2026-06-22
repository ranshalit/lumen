# Defer slow init work until after the login prompt.
#
# Entries use the sysvinit `once` action: they fire concurrently with getty
# when entering runlevel 5, so the prompt wins the race to the terminal and
# the deferred work happens a second or two later in the background.
#
# Each entry replaces a synchronous rcS.d/* script removed in its own bbappend.

do_install:append() {
    echo "" >> ${D}${sysconfdir}/inittab

    # Ethernet (replaces rcS.d default ifup): lo is auto-up by the kernel,
    # eth0 static IP is brought up here.
    echo "# Ethernet: deferred to after prompt (non-blocking)" >> ${D}${sysconfdir}/inittab
    echo "eth0:5:once:/etc/init.d/lumen-eth-static start" >> ${D}${sysconfdir}/inittab

    # Kernel module auto-load (replaces rcS.d/S06modutils.sh):
    # loads /etc/modules + /etc/modules-load.d/*.conf — on Lumen that means
    # nvgpu, nvmap, pwm-fan, ina3221. nvgpu probe is ~3s of wall time and
    # was the single largest userspace blocker before the prompt appeared.
    echo "# Kernel modules: deferred to after prompt (non-blocking)" >> ${D}${sysconfdir}/inittab
    echo "mod:5:once:/etc/init.d/modutils.sh" >> ${D}${sysconfdir}/inittab
}
