# Remove bootlogd init scripts — serial console is available for boot debugging.
# bootlogd adds S07 to rcS.d and S99stop-bootlogd to rc[2-5].d, both unnecessary.
#
# Set HWCLOCKACCESS=no in /etc/default/rcS to skip RTC <-> system-clock sync at
# boot. util-linux hwclock --hctosys waits ~1.0s for the RTC second-edge, and
# the default boot path runs it TWICE: once via bootmisc.sh's internal call
# (`/etc/init.d/hwclock.sh start`) and again via S40hwclock.sh. Disabling both
# saves ~1.86s of serial rcS time (measured).
# Trade-off: system time tracks NTP from S20ntpd instead of RTC. This board
# already runs NTP (rc5.d/S20ntpd), so RTC sync at boot is redundant for our
# use case. Acceptable as long as boot does not require accurate wall-clock
# time before NTP locks (~rc5).

do_install:append() {
    rm -f ${D}${sysconfdir}/init.d/bootlogd
    rm -f ${D}${sysconfdir}/init.d/stop-bootlogd
    rm -f ${D}${sysconfdir}/rcS.d/S07bootlogd
    rm -f ${D}${sysconfdir}/rc2.d/S99stop-bootlogd
    rm -f ${D}${sysconfdir}/rc3.d/S99stop-bootlogd
    rm -f ${D}${sysconfdir}/rc4.d/S99stop-bootlogd
    rm -f ${D}${sysconfdir}/rc5.d/S99stop-bootlogd
    rm -f ${D}${sysconfdir}/default/volatiles/01_bootlogd

    echo "# Disable RTC <-> system-clock sync at boot (saves ~1.86s)." \
        >> ${D}${sysconfdir}/default/rcS
    echo "HWCLOCKACCESS=no" >> ${D}${sysconfdir}/default/rcS
}
