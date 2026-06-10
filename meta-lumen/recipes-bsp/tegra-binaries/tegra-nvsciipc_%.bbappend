# Make nv_nvsciipc_init non-blocking.
# The original script runs /usr/bin/nvsciipc_init synchronously, which
# can take a noticeable amount of time initialising the NvSciIpc device.
# We simply background it — the IPC framework is ready well before any
# userspace app needs it.

do_install:append() {
    sed -i 's|/usr/bin/nvsciipc_init$|/usr/bin/nvsciipc_init \&|' \
        ${D}${sysconfdir}/init.d/nv_nvsciipc_init
}
