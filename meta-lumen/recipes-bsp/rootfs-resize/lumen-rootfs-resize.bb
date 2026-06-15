# meta-lumen/recipes-bsp/rootfs-resize/lumen-rootfs-resize.bb
#
# Grows the rootfs filesystem to fill the APP partition on first boot.
#
# The Lumen image flashes a small ext4 filesystem (IMAGE_ROOTFS_SIZE, 8 GiB)
# for fast flashing, while NVIDIA's flasher auto-grows the APP partition
# (nvme0n1p1) to span the entire NVMe. Without this service the rootfs would
# stay at 8 GiB regardless of disk size. The init script runs an online
# resize2fs early in the rcS sequence and is a no-op once the filesystem
# already fills the partition.

SUMMARY = "Grow the rootfs to fill the APP partition on first boot"
DESCRIPTION = "Installs a sysvinit script (S02, runlevel S) that runs \
resize2fs on the mounted rootfs so the filesystem expands to fill the \
auto-grown APP partition. Disk-size-agnostic and idempotent."

LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

PACKAGE_ARCH = "${MACHINE_ARCH}"
COMPATIBLE_MACHINE = "(lumen)"

SRC_URI = "file://lumen-rootfs-resize"

S = "${WORKDIR}"

do_configure[noexec] = "1"
do_compile[noexec] = "1"

do_install() {
    install -d ${D}${sysconfdir}/init.d
    install -m 0755 ${WORKDIR}/lumen-rootfs-resize \
        ${D}${sysconfdir}/init.d/lumen-rootfs-resize

    install -d ${D}${sysconfdir}/rcS.d
    ln -sf ../init.d/lumen-rootfs-resize \
        ${D}${sysconfdir}/rcS.d/S02lumen-rootfs-resize
}

FILES:${PN} += "${sysconfdir}/init.d/lumen-rootfs-resize ${sysconfdir}/rcS.d/S02lumen-rootfs-resize"

# resize2fs lives in e2fsprogs-resize2fs; findmnt comes from util-linux (already
# in the image). Pull resize2fs in explicitly so the package is self-contained.
RDEPENDS:${PN} += "e2fsprogs-resize2fs"

INITSCRIPT_NAME = "lumen-rootfs-resize"
INITSCRIPT_PARAMS = "start 02 S ."

inherit update-rc.d
