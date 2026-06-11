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
    lumen-eth-static \
    ifupdown \
    sudo \
    htop \
    i2c-tools \
    util-linux \
    chrony \
    docker-moby \
    containerd-opencontainers \
    nvidia-container-toolkit \
    nvidia-docker \
    docker-compose \
    lumen-udev-rules \
"

# Post-install script to create nexus user, configure sudo, and pre-generate SSH host keys
rootfs_postinstall_lumen() {
    # Create nexus user with pre-computed password hash: Pp12345678
    echo 'nexus:$1$zqutX3PP$7yMwtINW/p.UC/W/qYHvF0:19000:0:99999:7:::' >> ${IMAGE_ROOTFS}/etc/shadow
    echo 'nexus:x:1000:1000:Nexus User:/home/nexus:/bin/bash' >> ${IMAGE_ROOTFS}/etc/passwd
    echo 'nexus:x:1000:' >> ${IMAGE_ROOTFS}/etc/group
    
    # Create home directory
    mkdir -p ${IMAGE_ROOTFS}/home/nexus
    chown -R 1000:1000 ${IMAGE_ROOTFS}/home/nexus
    chmod 755 ${IMAGE_ROOTFS}/home/nexus
    
    # Add nexus to sudo and docker groups
    sed -i 's/^%sudo/%sudo_members/' ${IMAGE_ROOTFS}/etc/group 2>/dev/null || true
    echo 'sudo:x:27:nexus' >> ${IMAGE_ROOTFS}/etc/group
    echo 'docker:x:999:nexus' >> ${IMAGE_ROOTFS}/etc/group
    
    # Ensure sudoers is configured
    echo 'nexus ALL=(ALL) NOPASSWD: ALL' >> ${IMAGE_ROOTFS}/etc/sudoers.d/nexus
    chmod 440 ${IMAGE_ROOTFS}/etc/sudoers.d/nexus
}

ROOTFS_POSTINSTALL_COMMAND:append:lumen = "rootfs_postinstall_lumen; "

# rootfs size: 8 GiB — Docker engine + /var/lib/docker layer storage requires headroom
IMAGE_ROOTFS_SIZE ?= "8388608"
IMAGE_OVERHEAD_FACTOR ?= "1.2"
