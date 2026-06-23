# Defer kernel-module loading until after the login prompt.
#
# Two cooperating pieces are needed to keep nvgpu's ~3 s GPU probe off the
# critical path:
#
# 1. Drop the S06modutils.sh symlink from rcS.d (INHIBIT_UPDATERCD_BBCLASS=1
#    below) and re-fire /etc/init.d/modutils.sh from inittab as
#    `mod:5:once:` (see sysvinit-inittab_%.bbappend). That moves the explicit
#    `modprobe` loop off the boot path.
#
# 2. Install /etc/modprobe.d/defer-nv.conf with `blacklist nvgpu`. WITHOUT
#    this, S04udev's `udevadm trigger`/`udevadm settle` matches nvgpu's
#    internal modalias (`of:N*T*Cnvidia,ga10b*` for Orin) and modprobes it
#    during coldplug — *before* S06modutils.sh ever ran, which is why the
#    rcS.d-symlink-only deferral measured as a no-op. The blacklist makes
#    modprobe ignore nvgpu's internal aliases (kernel-driven auto-load and
#    udev coldplug both go through them), while an explicit
#    `modprobe nvgpu` by name from modutils.sh still loads it — and pulls
#    nvmap + nvsciipc + host1x + mc-utils via modules.dep at the same time.
#
# pwm-fan and ina3221 are intentionally NOT blacklisted (fast probes; their
# fan-control / power-monitor surfaces are expected live in userspace).
#
# Same async contract as Ethernet (commit ae9fa57) and Docker (commit 852177d):
# any application that needs nvgpu/nvmap (e.g. CUDA containers) must validate
# device readiness — lumen-app already waits for dockerd, which can in turn
# wait on /dev/nvhost-* if needed.

INHIBIT_UPDATERCD_BBCLASS = "1"

FILESEXTRAPATHS:prepend := "${THISDIR}/files:"

SRC_URI += "file://defer-nv.conf"

do_install:append() {
    install -d ${D}${sysconfdir}/modprobe.d
    install -m 0644 ${WORKDIR}/defer-nv.conf \
        ${D}${sysconfdir}/modprobe.d/defer-nv.conf
}

FILES:${PN} += "${sysconfdir}/modprobe.d/defer-nv.conf"

