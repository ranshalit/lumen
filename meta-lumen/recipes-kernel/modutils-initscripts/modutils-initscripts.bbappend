# Defer kernel-module loading until after the login prompt.
#
# Upstream registers /etc/init.d/modutils.sh as S06 in rcS.d so it runs
# synchronously before any rc5 entry — including getty. On Lumen the four
# auto-loaded modules (nvgpu, nvmap, pwm-fan, ina3221) take ~3 s of wall
# time at boot, with nvgpu's GPU probe (~kernel +5.7 s → +8.8 s) being the
# single largest userspace blocker right before the prompt appears.
#
# INHIBIT_UPDATERCD_BBCLASS = "1" stops update-rc.d.bbclass from injecting
# the pkg_postinst that would create the S06modutils.sh symlink in rcS.d.
# do_install still installs /etc/init.d/modutils.sh itself.
# sysvinit-inittab_%.bbappend then fires the script as a `mod:5:once:` entry,
# so the modprobe loop races getty in the background and the prompt wins.
#
# Same async contract as Ethernet (commit ae9fa57) and Docker (commit 852177d):
# any application that needs nvgpu/nvmap (e.g. CUDA containers) must validate
# device readiness — lumen-app already waits for dockerd, which can in turn
# wait on /dev/nvhost-* if needed.

INHIBIT_UPDATERCD_BBCLASS = "1"

