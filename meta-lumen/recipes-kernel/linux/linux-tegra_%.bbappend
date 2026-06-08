# meta-lumen/recipes-kernel/linux/linux-tegra_%.bbappend
#
# Applies Aerium Lumen board-specific patches to the L4T kernel:
#   0001 — Enable UART serial@3110000 (ttyTHS0), fix serial aliases
#   0002 — CSI port-index=0, tegra_sinterface=serial_a (base DTB)
#   0003 — CSI serial_a fix in camera DTBO overlay DTS files
#
# These patches are only applied when building for a Lumen machine
# (MACHINEOVERRIDES contains "lumen").

FILESEXTRAPATHS:prepend:lumen := "${THISDIR}/../../recipes-bsp/device-tree/lumen-dtb-patches/patches:"

SRC_URI:append:lumen = " \
    file://0001-lumen-uart-enable-serial-3110000.patch \
    file://0002-lumen-csi-port-index-serial-a.patch \
    file://0003-lumen-camera-dtbo-csi-serial-a.patch \
"
