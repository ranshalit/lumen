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
    lumen-usb2-host \
    ifupdown \
    ethtool \
    sudo \
    htop \
    i2c-tools \
    util-linux \
    rsync \
    python3 \
    nano \
    vim \
    ntp \
    ntpq \
    ntpdc \
    docker-moby \
    containerd-opencontainers \
    nvidia-container-toolkit \
    nvidia-docker \
    docker-compose \
    lumen-udev-rules \
    lumen-build-info \
    dragonfly \
    lumen-rootfs-resize \
    tegra-flash-reboot \
    kernel-module-usbserial \
    kernel-module-ftdi-sio \
    kernel-module-lan743x \
    kernel-module-cdc-acm \
    kernel-module-uvcvideo \
    kernel-module-fat \
    kernel-module-vfat \
"

# Post-install script to create nexus user, configure sudo, and pre-generate SSH host keys
rootfs_postinstall_lumen() {
    # Create nexus user with pre-computed password hash: Pp12345678
    echo 'nexus:$1$zqutX3PP$7yMwtINW/p.UC/W/qYHvF0:19000:0:99999:7:::' >> ${IMAGE_ROOTFS}/etc/shadow
    echo 'nexus:x:1000:1000:Nexus User:/home/nexus:/bin/bash' >> ${IMAGE_ROOTFS}/etc/passwd
    echo 'nexus:x:1000:' >> ${IMAGE_ROOTFS}/etc/group
    
    # Create home directory
    mkdir -p ${IMAGE_ROOTFS}/home/nexus

    # Shell init: system-wide profile.d snippet + nexus ~/.bashrc
    # (Ubuntu-era users had a Debian-style .bashrc; we ship a Yocto-appropriate
    # equivalent with the same day-to-day feel: aliases, colored PS1, history.)
    install -d -m 0755 ${IMAGE_ROOTFS}${sysconfdir}/profile.d
    install -m 0644 ${LUMEN_IMAGE_FILES}/lumen-profile.sh \
        ${IMAGE_ROOTFS}${sysconfdir}/profile.d/lumen.sh
    install -m 0644 ${LUMEN_IMAGE_FILES}/nexus.bashrc \
        ${IMAGE_ROOTFS}/home/nexus/.bashrc

    chown -R 1000:1000 ${IMAGE_ROOTFS}/home/nexus
    chmod 755 ${IMAGE_ROOTFS}/home/nexus
    
    # Add nexus to sudo group and to the docker group created by docker-moby
    sed -i 's/^%sudo/%sudo_members/' ${IMAGE_ROOTFS}/etc/group 2>/dev/null || true
    echo 'sudo:x:27:nexus' >> ${IMAGE_ROOTFS}/etc/group
    # docker-moby creates the docker group; append nexus to its member list
    if grep -q '^docker:' ${IMAGE_ROOTFS}/etc/group; then
        sed -i '/^docker:/s/\(.*:\)$/\1nexus/' ${IMAGE_ROOTFS}/etc/group
        sed -i '/^docker:/s/:nexus$/:nexus/' ${IMAGE_ROOTFS}/etc/group
    else
        echo 'docker:x:999:nexus' >> ${IMAGE_ROOTFS}/etc/group
    fi
    
    # Ensure sudoers is configured
    echo 'nexus ALL=(ALL) NOPASSWD: ALL' >> ${IMAGE_ROOTFS}/etc/sudoers.d/nexus
    chmod 440 ${IMAGE_ROOTFS}/etc/sudoers.d/nexus
}

LUMEN_IMAGE_FILES = "${THISDIR}/files"

ROOTFS_POSTINSTALL_COMMAND:append:lumen = "rootfs_postinstall_lumen; "

# Flashed rootfs size: 8 GiB — keeps the flash payload small/fast. The APP
# partition (nvme0n1p1) is auto-grown by NVIDIA's flasher to fill the entire
# NVMe, and lumen-rootfs-resize expands this ext4 filesystem to fill that
# partition on first boot (e.g. ~237 GiB usable on a 256 GB NVMe).
IMAGE_ROOTFS_SIZE ?= "8388608"
IMAGE_OVERHEAD_FACTOR ?= "1.2"
