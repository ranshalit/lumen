# Make nv_update_verifier non-blocking.
# nvbootctrl verify checks the redundant boot slot status — important for
# OTA safety but has no dependency from other rc5.d services. Run it in
# the background so it doesn't hold up sshd and the login prompt.

do_install:append() {
    sed -i 's|/usr/sbin/nvbootctrl verify < /dev/null$|/usr/sbin/nvbootctrl verify < /dev/null \&|' \
        ${D}${sysconfdir}/init.d/nv_update_verifier
}
