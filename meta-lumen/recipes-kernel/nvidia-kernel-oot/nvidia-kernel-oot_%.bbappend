# meta-lumen/recipes-kernel/nvidia-kernel-oot/nvidia-kernel-oot_%.bbappend
#
# Applies Aerium Lumen board-specific DTB patches after DTBs are compiled.
# Works by decompiling DTB → sed/awk patch → recompile, mirroring the logic
# in scripts/bsp/Aerium-Lumen-BSP-Orin-NX-Nano.sh.
#
# Active only when MACHINEOVERRIDES contains "lumen".
#
# Depends on dtc being available as a native tool.
DEPENDS:append:lumen = " dtc-native"

# DTBs are built into ${B}/kernel-devicetree/generic-dts/dtbs/
do_compile:append:lumen() {
    DTB_DIR="${B}/kernel-devicetree/generic-dts/dtbs"

    if [ ! -d "${DTB_DIR}" ]; then
        bbwarn "lumen: DTB dir not found: ${DTB_DIR} — skipping patches"
        return
    fi

    bbdebug 1 "lumen: patching DTBs in ${DTB_DIR}"

    # ------------------------------------------------------------------ #
    # Patch base DTBs: tegra234-p3768-0000+p3767-*.dtb
    # ------------------------------------------------------------------ #
    for dtb in "${DTB_DIR}"/tegra234-p3768-0000+p3767-*.dtb; do
        [ -f "$dtb" ] || continue
        base=$(basename "$dtb" .dtb)
        dts="${DTB_DIR}/${base}.dts"

        bbdebug 1 "lumen: decompiling ${base}.dtb"
        dtc -I dtb -O dts -o "$dts" "$dtb" || { bberror "lumen: dtc decompile failed: $dtb"; continue; }

        # A — UART: enable serial@3110000, switch compatible, add reset-names
        sed -i '/serial@3110000 {/,/\};/ s/compatible = "nvidia,tegra234-uart"[^;]*/compatible = "nvidia,tegra194-hsuart"/' "$dts"
        sed -i '/serial@3110000 {/,/\};/ s/status = "disabled";/status = "okay";/' "$dts"

        if grep -q 'serial@3110000' "$dts" && \
           ! awk '/serial@3110000 \{/,/\};/' "$dts" | grep -q 'status ='; then
            awk '/serial@3110000 \{/{found=1} found && /\};/{print "\t\tstatus = \"okay\";"; found=0} {print}' "$dts" > "${dts}.tmp" && mv "${dts}.tmp" "$dts"
        fi
        if grep -q 'serial@3110000' "$dts" && \
           ! awk '/serial@3110000 \{/,/\};/' "$dts" | grep -q 'reset-names'; then
            awk '/serial@3110000 \{/{found=1} found && /\};/{print "\t\treset-names = \"serial\";"; found=0} {print}' "$dts" > "${dts}.tmp" && mv "${dts}.tmp" "$dts"
        fi

        # B — Serial aliases: serial2=ttyTHS0, serial3=ttyTHS1
        sed -i 's|serial2 = "/bus@0/serial@3140000";|serial2 = "/bus@0/serial@3110000";\n\t\tserial3 = "/bus@0/serial@3140000";|' "$dts"

        # C — CSI: port-index=0, serial_a
        sed -i 's/port-index = <0x01>;/port-index = <0x00>;/g' "$dts"
        sed -i 's/tegra_sinterface = "serial_b";/tegra_sinterface = "serial_a";/g' "$dts"

        bbdebug 1 "lumen: recompiling ${base}.dtb"
        if dtc -I dts -O dtb -o "$dtb" "$dts" 2>/dev/null; then
            bbdebug 1 "lumen: patched ${base}.dtb"
        else
            bberror "lumen: dtc recompile failed for ${base}, restoring original"
        fi
        rm -f "$dts"

        # D — PCIe: disable empty slot pcie@141e0000 (C7, M.2 M Key secondary)
        # Confirmed empty from boot log: bus probed then immediately released,
        # no device enumerated. Disabling saves kernel probe time at boot.
        # Kept: 140a0000 (Realtek r8168 Ethernet), 14160000 (NVMe SSD),
        #        14100000 (Microchip 1055:7430, purpose unknown — kept safe).
        if fdtput -t s "$dtb" "/bus@0/pcie@141e0000" status disabled 2>/dev/null; then
            bbdebug 1 "lumen: disabled pcie@141e0000 in ${base}.dtb"
        else
            bbwarn "lumen: could not disable pcie@141e0000 in ${base}.dtb (node may not exist)"
        fi

        # E — Unused peripherals: audio fabric + SPI controllers (no hardware on Lumen)
        # aconnect@2900000: APB audio fabric — no audio hardware on Lumen
        # spi@3210000/3230000/3270000: SPI-A/B/D — no SPI devices on Lumen carrier
        # Kept: rce-fabric (camera in use), actmon/hwpm/mc-hwpm (tegrastats/Nsight).
        for node in aconnect@2900000 spi@3210000 spi@3230000 spi@3270000; do
            if fdtput -t s "$dtb" "/bus@0/${node}" status disabled 2>/dev/null; then
                bbdebug 1 "lumen: disabled ${node} in ${base}.dtb"
            else
                bbwarn "lumen: could not disable ${node} in ${base}.dtb (node may not exist)"
            fi
        done
    done

    # ------------------------------------------------------------------ #
    # Patch camera DTBO overlays: tegra234-p3768-0000+p3767-*camera*.dtbo
    # ------------------------------------------------------------------ #
    for dtbo in "${DTB_DIR}"/tegra234-p3768-0000+p3767-*camera*.dtbo; do
        [ -f "$dtbo" ] || continue
        base=$(basename "$dtbo" .dtbo)
        dts="${DTB_DIR}/${base}.dts"

        dtc -I dtb -O dts -o "$dts" "$dtbo" 2>/dev/null || { bbwarn "lumen: dtc decompile failed: $dtbo"; continue; }

        awk '
        BEGIN { in_i2c0=0; in_vi=0; in_vi_port0=0; in_chan0=0; in_chan0_ep0=0; in_i2c0_port0=0 }
        /i2c@0[^0-9]/ { in_i2c0=1 }
        /i2c@1[^0-9]/ { in_i2c0=0 }
        /tegra-capture-vi/ { in_vi=1 }
        in_vi && /port@0/ { in_vi_port0=1 }
        in_vi_port0 && /port-index = <0x01>/ { sub(/0x01/, "0x00") }
        in_vi_port0 && /}/ { in_vi_port0=0 }
        /channel@0/ { in_chan0=1 }
        in_chan0 && /endpoint@0/ { in_chan0_ep0=1 }
        in_chan0_ep0 && /port-index = <0x01>/ { sub(/0x01/, "0x00") }
        in_chan0_ep0 && /}/ { in_chan0_ep0=0 }
        in_i2c0 && /tegra_sinterface = "serial_b"/ { sub(/serial_b/, "serial_a") }
        in_i2c0 && /port@0/ { in_i2c0_port0=1 }
        in_i2c0_port0 && /port-index = <0x01>/ { sub(/0x01/, "0x00") }
        in_i2c0_port0 && /}/ { in_i2c0_port0=0 }
        { print }
        ' "$dts" > "${dts}.tmp" && mv "${dts}.tmp" "$dts"

        if dtc -@ -I dts -O dtb -o "$dtbo" "$dts" 2>/dev/null; then
            bbdebug 1 "lumen: patched camera overlay ${base}.dtbo"
        else
            bbwarn "lumen: dtc recompile failed for ${base}.dtbo"
        fi
        rm -f "$dts"
    done

    bbdebug 1 "lumen: DTB patching complete"
}
