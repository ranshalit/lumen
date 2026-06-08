# meta-lumen/recipes-images/images/lumen-image-minimal.bb
#
# Minimal headless image for the Aerium Lumen board.
# Produces a console-only rootfs suitable for flashing via L4T tegraflash.

SUMMARY = "Aerium Lumen minimal headless image"
DESCRIPTION = "Minimal console image for Aerium Lumen board (Jetson Orin NX/Nano, p3767)"
LICENSE = "MIT"

COMPATIBLE_MACHINE = "(lumen)"

inherit core-image

# No GUI, no X11
IMAGE_FEATURES += "ssh-server-openssh"

IMAGE_INSTALL += " \
    packagegroup-core-boot \
    tegra-libraries-core \
    tegra-nvsciipc \
    lumen-usb-otg \
    htop \
    i2c-tools \
    util-linux \
"

# rootfs size: 2 GiB (override with IMAGE_ROOTFS_SIZE in local.conf if needed)
IMAGE_ROOTFS_SIZE ?= "2097152"
IMAGE_OVERHEAD_FACTOR ?= "1.2"
