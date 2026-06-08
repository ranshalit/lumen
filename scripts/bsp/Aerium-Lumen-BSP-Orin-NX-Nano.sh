#!/bin/bash

set -e

# ========================================================
# PREFLASH MASTER SCRIPT FOR NVIDIA JETSON (Linux for Tegra)
# Applies:
#   1. UART DTB patch (enables serial@3110000)
#   2. CSI DTB patch (port-index and tegra_sinterface)
#   3. USB OTG runtime patch
#   4. EEPROM BCT patch (cvb_eeprom_read_size = <0x0>)
# --------------------------------------------------------
# Run this script INSIDE Linux_for_Tegra/ BEFORE flashing.
# ========================================================

# -------------------------------
# Configuration
# -------------------------------

DTB_DIR="kernel/dtb"
BCT_DTSI="bootloader/generic/BCT/tegra234-mb2-bct-misc-p3767-0000.dts"
USB_OTG_SCRIPT="rootfs/opt/nvidia/l4t-usb-device-mode/nv-l4t-usb-device-mode-start.sh"
BACKUP_DIR="$DTB_DIR/backup"
LOG_DIR="log"

mkdir -p "$LOG_DIR"

# Ask user if backup folder exists
if [ -d "$BACKUP_DIR" ]; then
    read -p "[WARN] Backup folder '$BACKUP_DIR' already exists. Overwrite? [y/N]: " answer
    if [[ "$answer" =~ ^[Yy]$ ]]; then
        echo "[INFO] Removing old backup directory..."
        rm -rf "$BACKUP_DIR"
    else
        echo "[ABORT] Exiting to avoid overwriting previous backups."
        exit 1
    fi
fi

mkdir -p "$BACKUP_DIR"

# -------------------------------
# Dependency Check
# -------------------------------

check_dependencies() {
    echo "[INFO] Checking for required tools..."
    command -v dtc >/dev/null 2>&1 || {
        echo >&2 "[ERROR] 'dtc' (Device Tree Compiler) not found. Install it and try again."
        exit 1
    }
    echo "[OK] All dependencies are met."
}

# -------------------------------
# USB OTG Patch
# -------------------------------

fix_usb_otg() {
    echo "[STEP] Applying USB OTG fix..."

    if [ ! -f "$USB_OTG_SCRIPT" ]; then
        echo "[WARN] USB OTG script not found: $USB_OTG_SCRIPT"
        return
    fi

    if grep -q 'usb2-0-role-switch' "$USB_OTG_SCRIPT"; then
        echo "[SKIP] USB OTG fix already present. No changes made."
    else
        sudo sed -i '/exit 0/iecho "device" > /sys/class/usb_role/usb2-0-role-switch/role\n' "$USB_OTG_SCRIPT"
        echo "[OK] USB OTG fix inserted."
    fi
}

# -------------------------------
# DTB Patch (CSI + UART)
# -------------------------------

patch_dtb_files() {
    echo "[STEP] Patching DTB files in: $DTB_DIR"

    if [ ! -d "$DTB_DIR" ]; then
        echo "[ERROR] DTB directory '$DTB_DIR' not found."
        exit 1
    fi

    for dtb_file in "$DTB_DIR"/*.dtb; do
        base_name=$(basename "$dtb_file" .dtb)
        dts_file="$DTB_DIR/$base_name.dts"

        # Only patch DTBs that match target device name
	if [[ "$base_name" != *"p3767"* ]]; then
	    echo "   [SKIP] Skipping $base_name.dtbo"
	    continue
	fi

        echo " - Processing $base_name.dtb..."

	cp "$dtb_file" "$BACKUP_DIR/$(basename "$dtb_file").back"

        if ! dtc -I dtb -O dts -o "$dts_file" "$dtb_file" >/dev/null 2>&1; then
            echo "[WARN] Failed to decompile $dtb_file. Skipping."
            continue
        fi

        # UART fix
	# Ensure status = "okay"; exists inside serial@3110000 block
	if awk '/serial@3110000 {/,/};/ { if ($0 ~ /status =/) found=1 } END { exit !found }' "$dts_file"; then
	    # Replace any status line inside the block with "okay"
	    sed -i '/serial@3110000 {/,/};/ s/^\(\s*\)status = .*/\1status = "okay";/' "$dts_file"
	else
	    # Insert status = "okay"; before the closing brace
	    sed -i '/serial@3110000 {/,/};/ {
		/};/ i\
		    status = "okay";
	    }' "$dts_file"
	fi

	# Replace the existing compatible line in serial@3110000 block
	if grep -A5 "serial@3110000" "$dts_file" | grep -q 'tegra234-uart'; then
	    sed -i '/serial@3110000 {/,/};/ s/^\(\s*\)compatible = .*;/\1compatible = "nvidia,tegra194-hsuart";/' "$dts_file"
	else
	    echo "   [SKIP] compatible already patched in $base_name.dts"
	fi


	# Insert reset-names only if not already present in serial@3110000 block
	if ! awk '/serial@3110000 {/,/};/ { if ($0 ~ /reset-names/) found=1 } END { exit !found }' "$dts_file"; then
	    sed -i '/serial@3110000 {/,/};/ {
		/};/ i\
		    reset-names = "serial";
	    }' "$dts_file"
	else
	    echo "   [SKIP] reset-names already exists in $base_name.dts"
	fi

	# Fix serial aliases (replace serial2 and add serial3)
	if grep -q 'serial2 = "/bus@0/serial@3140000";' "$dts_file" && ! grep -q 'serial3 = "/bus@0/serial@3140000";' "$dts_file"; then
		sed -i 's#serial2 = "/bus@0/serial@3140000";#serial2 = "/bus@0/serial@3110000";\n\tserial3 = "/bus@0/serial@3140000";#' "$dts_file"
	elif grep -q 'serial2 = "/bus@0/serial@3110000";' "$dts_file"; then
		echo "   [SKIP] serial aliases already patched in $base_name.dts"
	fi

        # CSI fix
        sed -i 's/port-index = <0x01>;/port-index = <0x00>;/g' "$dts_file"
        sed -i 's/tegra_sinterface = "serial_b";/tegra_sinterface = "serial_a";/g' "$dts_file"

	ERR_LOG="$LOG_DIR/$base_name.dtc.err"
	if dtc -I dts -O dtb -o "$dtb_file" "$dts_file" 2> "$ERR_LOG"; then
		echo "   [OK] Patched: $base_name.dtb"
        else
		echo "   [ERR] dtc output:"
		cat "$ERR_LOG"

            	echo "   [ERR] Failed to recompile. Restoring backup."
            	cp "$BACKUP_DIR/$(basename "$dtb_file").back" "$dtb_file"
        fi

        rm -f "$dts_file"
    done

    echo "[DONE] DTB patching complete."
}

# -------------------------------
# EEPROM BCT Patch
# -------------------------------

patch_bct_eeprom_read_size() {
    echo "[STEP] Patching EEPROM read size in BCT..."

    if [ ! -f "$BCT_DTSI" ]; then
        echo "[ERROR] BCT DTSI file not found: $BCT_DTSI"
        return 1
    fi

    cp "$BCT_DTSI" "$BCT_DTSI.back"

    if grep -q 'cvb_eeprom_read_size = <0x100>;' "$BCT_DTSI"; then
        sed -i 's/cvb_eeprom_read_size = <0x100>;/cvb_eeprom_read_size = <0x0>;/g' "$BCT_DTSI"
        echo "[OK] BCT EEPROM read size changed to <0x0>."
    elif grep -q 'cvb_eeprom_read_size = <0x0>;' "$BCT_DTSI"; then
        echo "[SKIP] No patch needed — already set to <0x0>."
    else
        echo "[SKIP] No matching EEPROM line found. Nothing changed."
    fi
}

# -------------------------------
# Camera CSI Port0 Patch
# -------------------------------
patch_camera_dtbo_overlays() {
    echo "[STEP] Patching DTBO camera overlays in: $DTB_DIR"

    if [ ! -d "$DTB_DIR" ]; then
        echo "[ERROR] DTB directory '$DTB_DIR' not found."
        exit 1
    fi

    mkdir -p "$BACKUP_DIR"

    for dtbo_file in "$DTB_DIR"/*camera*.dtbo; do
        base_name=$(basename "$dtbo_file" .dtbo)

        # Only process files that match target board name
	if [[ "$base_name" != *"p3767"* ]]; then
	    echo "   [SKIP] Skipping $base_name.dtbo"
	    continue
	fi

        dts_file="$DTB_DIR/$base_name.dts"
        dtbo_backup="$BACKUP_DIR/$base_name.dtbo.bak"

        echo " - Processing $base_name.dtbo..."

        cp "$dtbo_file" "$dtbo_backup"

        if ! dtc -I dtb -O dts -o "$dts_file" "$dtbo_file" >/dev/null 2>&1; then
            echo "   [WARN] Failed to decompile $dtbo_file. Skipping."
            continue
        fi

        TMP_FILE=$(mktemp)

        awk '
        BEGIN { in_i2c0 = 0; }
        /i2c@0/ { in_i2c0 = 1 }
        /i2c@1/ { in_i2c0 = 0 }

        {
            if (in_i2c0 && /tegra_sinterface = "serial_b"/) {
                sub(/serial_b/, "serial_a")
            }

            if (/tegra-capture-vi/) in_vi = 1
            if (in_vi && /port@0/) in_vi_port0 = 1
            if (in_vi_port0 && /port-index = <0x01>/) sub(/0x01/, "0x00")
            if (in_vi_port0 && /}/) in_vi_port0 = 0

            if (/channel@0/) in_chan0 = 1
            if (in_chan0 && /endpoint@0/) in_chan0_ep0 = 1
            if (in_chan0_ep0 && /port-index = <0x01>/) sub(/0x01/, "0x00")
            if (in_chan0_ep0 && /}/) in_chan0_ep0 = 0

            if (in_i2c0 && /port@0/) in_i2c0_port0 = 1
            if (in_i2c0_port0 && /port-index = <0x01>/) sub(/0x01/, "0x00")
            if (in_i2c0_port0 && /}/) in_i2c0_port0 = 0

            print
        }
        ' "$dts_file" > "$TMP_FILE"

        if dtc -@ -I dts -O dtb -o "$dtbo_file" "$TMP_FILE" >/dev/null 2>&1; then
            echo "   [OK] Patched: $base_name.dtbo"
            rm -f "$TMP_FILE" "$dts_file"
        else
            echo "   [ERR] Failed to recompile. Restoring original."
            cp "$dtbo_backup" "$dtbo_file"
            rm -f "$TMP_FILE"
        fi
    done

    echo "[DONE] DTBO camera overlays patched."
}

# -------------------------------
# Main
# -------------------------------

main() {
    echo "=============================================="
    echo "  Aerium Lumen BSP - Pre-Flash Master Script"
    echo "        NVIDIA Jetson ORIN NX/NANO"
    echo "=============================================="
    echo

    check_dependencies

    # USB OTG Patch
    if fix_usb_otg; then
        echo -e "✅ USB OTG patch applied."
    else
        echo -e "\033[1;31m❌ USB OTG patch failed or skipped.\033[0m"
    fi

    # Patch DTBO camera overlays
    if patch_camera_dtbo_overlays; then
        echo -e "✅ DTBO camera overlays patched (port-index + serial_a)."
        sudo cp "$DTB_DIR"/*.dtbo rootfs/boot/
    else
        echo -e "\033[1;31m❌ DTBO camera overlay patching failed.\033[0m"
    fi

    # DTB Patch
    if patch_dtb_files; then
        echo -e "✅ DTB files patched (UART + CSI)."
	sudo cp "$DTB_DIR"/*.dtb rootfs/boot/
    else
        echo -e "\033[1;31m❌ DTB patching failed.\033[0m"
    fi

    # EEPROM Patch
    if patch_bct_eeprom_read_size; then
        echo -e "✅ EEPROM BCT patch applied."
    else
        echo -e "\033[1;31m❌ EEPROM BCT patch failed.\033[0m"
    fi

    echo

    # Important note about system image
    echo -e "\033[1;36m⚠️  To ensure your changes take effect, delete:\033[0m"
    echo -e "\033[1;36m   - bootloader/system.img\033[0m"
    echo -e "\033[1;36m   - bootloader/system.img.raw\033[0m"
    echo -e "\033[1;36mThese will be re-generated during the next flash.\033[0m"
}


main "$@"
