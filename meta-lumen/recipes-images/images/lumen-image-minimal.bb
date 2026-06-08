# meta-lumen/recipes-images/lumen-image-minimal.bb
#
# Minimal headless image for the Aerium Lumen board.
# Produces a console-only rootfs suitable for flashing via L4T tegraflash.

SUMMARY = "Aerium Lumen minimal headless image"
DESCRIPTION = "Minimal console image for Aerium Lumen board (Jetson Orin NX/Nano, p3767)"
LICENSE = "MIT"

COMPATIBLE_MACHINE = "(lumen)"

inherit core-image

# Base image features — no GUI
IMAGE_FEATURES += "ssh-server-openssh"

IMAGE_INSTALL += " \
    packagegroup-core-boot \
    packagegroup-base-tegra \
    lumen-usb-otg \
    htop \
    i2c-tools \
    util-linux \
"

# rootfs size (1 GiB — adjust as needed)
IMAGE_ROOTFS_SIZE ?= "1048576"
IMAGE_OVERHEAD_FACTOR ?= "1.2"
