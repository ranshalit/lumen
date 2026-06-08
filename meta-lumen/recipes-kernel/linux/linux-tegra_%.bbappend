# meta-lumen/recipes-kernel/linux/linux-tegra_%.bbappend
#
# Applies Aerium Lumen board-specific DTS patches using sed/awk,
# mirroring the logic in scripts/bsp/Aerium-Lumen-BSP-Orin-NX-Nano.sh.
#
# Approach: sed/awk on kernel DTS source files (no patch context needed).
# Reference .patch stubs (for documentation / future git-format-patch use)
# are in meta-lumen/recipes-bsp/device-tree/lumen-dtb-patches/patches/docs/.
#
# Active only when MACHINEOVERRIDES contains "lumen".
#
# Patches applied:
#   A — UART: enable serial@3110000 (ttyTHS0), fix compatible + reset-names
#   B — Serial aliases: serial2=ttyTHS0, serial3=ttyTHS1
#   C — CSI: port-index=0x00, tegra_sinterface=serial_a (base DTB)
#   D — Camera DTBO: same CSI fix in overlay DTS files

DTS_DIR = "${S}/arch/arm64/boot/dts/nvidia"

do_patch:append:lumen() {
    set -e
    bbdebug 1 "lumen: applying DTS patches via sed/awk"

    # ------------------------------------------------------------------ #
    # Targets: tegra234-p3768-0000+p3767-*.dts (all p3767 base DTSes)
    # ------------------------------------------------------------------ #
    for dts in ${DTS_DIR}/tegra234-p3768-0000+p3767-*.dts; do
        [ -f "$dts" ] || continue
        base=$(basename "$dts")
        bbdebug 1 "lumen: patching $base"

        # A — UART: enable serial@3110000
        #     Replace compatible with hsuart driver
        sed -i '/serial@3110000 {/,/\};/ s/compatible = "nvidia,tegra234-uart"[^;]*/compatible = "nvidia,tegra194-hsuart"/' "$dts"
        #     Ensure status = "okay"
        sed -i '/serial@3110000 {/,/\};/ s/status = "disabled";/status = "okay";/' "$dts"
        #     Add status if missing from the block
        if grep -q 'serial@3110000' "$dts" && \
           ! awk '/serial@3110000 \{/,/\};/' "$dts" | grep -q 'status ='; then
            sed -i '/serial@3110000 {/,/\};/ { /\};/ i\\t\tstatus = "okay"; }' "$dts"
        fi
        #     Add reset-names if missing
        if grep -q 'serial@3110000' "$dts" && \
           ! awk '/serial@3110000 \{/,/\};/' "$dts" | grep -q 'reset-names'; then
            sed -i '/serial@3110000 {/,/\};/ { /\};/ i\\t\treset-names = "serial"; }' "$dts"
        fi

        # B — Serial aliases: serial2 = ttyTHS0, serial3 = ttyTHS1
        sed -i 's|serial2 = "/bus@0/serial@3140000";|serial2 = "/bus@0/serial@3110000";\n\t\tserial3 = "/bus@0/serial@3140000";|' "$dts"

        # C — CSI: port-index=0, serial_a (base DTB)
        sed -i 's/port-index = <0x01>;/port-index = <0x00>;/g' "$dts"
        sed -i 's/tegra_sinterface = "serial_b";/tegra_sinterface = "serial_a";/g' "$dts"
    done

    # ------------------------------------------------------------------ #
    # Targets: tegra234-p3768-0000+p3767-*camera*.dts (camera DTBO sources)
    # ------------------------------------------------------------------ #
    # D — Camera DTBO: CSI serial_a + port-index fix (mirrors awk logic
    #     from BSP script patch_camera_dtbo_overlays, scoped to i2c@0 block)
    for dts in ${DTS_DIR}/tegra234-p3768-0000+p3767-*camera*.dts \
               ${DTS_DIR}/tegra234-p3768-0000+p3767-*camera*.dtso; do
        [ -f "$dts" ] || continue
        bbdebug 1 "lumen: patching camera overlay $(basename $dts)"

        awk '
        BEGIN { in_i2c0 = 0; in_vi = 0; in_vi_port0 = 0; in_chan0 = 0; in_chan0_ep0 = 0 }
        /i2c@0[^0-9]/ { in_i2c0 = 1 }
        /i2c@1[^0-9]/ { in_i2c0 = 0 }
        /tegra-capture-vi/ { in_vi = 1 }
        in_vi && /port@0/ { in_vi_port0 = 1 }
        in_vi_port0 && /port-index = <0x01>/ { sub(/0x01/, "0x00") }
        in_vi_port0 && /}/ { in_vi_port0 = 0 }
        /channel@0/ { in_chan0 = 1 }
        in_chan0 && /endpoint@0/ { in_chan0_ep0 = 1 }
        in_chan0_ep0 && /port-index = <0x01>/ { sub(/0x01/, "0x00") }
        in_chan0_ep0 && /}/ { in_chan0_ep0 = 0 }
        in_i2c0 && /tegra_sinterface = "serial_b"/ { sub(/serial_b/, "serial_a") }
        in_i2c0 && /port@0/ { in_i2c0_port0 = 1 }
        in_i2c0_port0 && /port-index = <0x01>/ { sub(/0x01/, "0x00") }
        in_i2c0_port0 && /}/ { in_i2c0_port0 = 0 }
        { print }
        ' "$dts" > "${dts}.tmp" && mv "${dts}.tmp" "$dts"
    done

    bbdebug 1 "lumen: DTS patches applied"
}
