# Override docker.init with a non-blocking variant.
#
# The upstream docker.init (meta-virtualization) polls the dockerd pidfile
# with up to 10 x 1-second sleeps before returning from start().  This blocks
# the sysvinit rc5 sequence — and therefore the login prompt — for up to 10s.
#
# This bbappend replaces docker.init with a fire-and-forget version: dockerd is
# launched in the background and start() returns immediately.  dragonfly (S60)
# has its own bounded docker-readiness poll and is itself non-blocking.

FILESEXTRAPATHS:prepend := "${THISDIR}/files:"

# The modified docker.init is provided in files/ next to this bbappend.
# meta-tegra's do_install:append:tegra installs ${WORKDIR}/docker.init, so
# adding it to SRC_URI is sufficient — it overrides the meta-virtualization copy.
SRC_URI:append:tegra = " file://docker.init"
