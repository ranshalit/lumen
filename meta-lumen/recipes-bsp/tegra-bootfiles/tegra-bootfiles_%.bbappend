# meta-lumen/recipes-bsp/tegra-bootfiles/tegra-bootfiles_%.bbappend
#
# Lumen board: patch the BCT DTSI to set cvb_eeprom_read_size = <0x0>.
#
# The EEPROM on the Lumen carrier is not accessible during boot; the default
# read size of 0x100 causes a hang. Setting it to 0x0 disables the read.
#
# Derived from: scripts/bsp/Aerium-Lumen-BSP-Orin-NX-Nano.sh
#               (patch_bct_eeprom_read_size section)

do_compile:prepend:lumen() {
    BCT_DTSI="${S}/bootloader/generic/BCT/tegra234-mb2-bct-misc-p3767-0000.dts"
    if [ -f "${BCT_DTSI}" ]; then
        if grep -q 'cvb_eeprom_read_size = <0x100>;' "${BCT_DTSI}"; then
            sed -i 's/cvb_eeprom_read_size = <0x100>;/cvb_eeprom_read_size = <0x0>;/' \
                "${BCT_DTSI}"
            bbdebug 1 "lumen: patched cvb_eeprom_read_size to <0x0>"
        fi
    else
        bberror "lumen: BCT DTSI not found: ${BCT_DTSI}"
    fi
}
