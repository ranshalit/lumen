# lumen-common.inc — shared settings for all Aerium Lumen machine variants
#
# Strips DISTRO_FEATURES that have no hardware or use-case backing on Lumen:
#   - No Bluetooth/WiFi radio (no devkit-wifi.inc included)
#   - No NFC hardware
#   - No telephony/modem (3g/ofono)
#   - No mDNS needed (static IP 192.0.5.x)
#   - No NFS mounts (local NVMe, SSH/SCP for transfers)
#   - Headless (no X11/Wayland display stack)
#   - IPv4-only static network
#   - No 32-bit multiarch support needed
#   - No test/debug infrastructure in production image

DISTRO_FEATURES:remove = " \
    bluetooth \
    3g \
    nfc \
    zeroconf \
    nfs \
    wifi \
    x11 \
    wayland \
    ptest \
    debuginfod \
    multiarch \
    pcmcia \
    ipv6 \
"

# Keep: acl xattr opengl vulkan ext2 ipv4 usbgadget usbhost seccomp

# Remove alsa from MACHINE_FEATURES — no audio hardware on Lumen.
# tegra-common.inc adds it, but packagegroup-base-alsa → alsa-state is unwanted.
MACHINE_FEATURES:remove = "alsa"

# syslog: removable — dmesg ring buffer is accessible live via `dmesg`
VIRTUAL-RUNTIME_base-utils-syslog = ""

# Skip the extlinux boot menu countdown — always auto-boot the first entry.
# The menu is never used on Lumen; recovery is via reflash (flash-lumen workflow).
UBOOT_EXTLINUX_TIMEOUT = "0"

# Eliminate the boot initramfs — NVMe + PCIe are built into the kernel (no-initrd.cfg).
# Rootfs is always on nvme0n1p1 (APP partition id=1; A/B redundancy is kernel-only).
INITRAMFS_IMAGE = ""
INITRAMFS_IMAGE_BUNDLE = "0"
KERNEL_ARGS:append = " root=/dev/nvme0n1p1 rootwait rw"

# MB1/BPMP serial logging: silence pre-kernel bootloader output.
# Serial console is only used post-kernel on Lumen; MB1/BPMP debug not needed.
TEGRA_MB1_LOG_LEVEL = "0"
TEGRA_BPMP_SERIAL_LOGGING = "0"

# Keep the Tegra UART and add QEMU virt's PL011 UART. ttyrun starts getty
# only when the device exists, so the same image supports both environments.
SERIAL_CONSOLES:append = " 115200;ttyAMA0"

# Suppress kernel log output on serial during boot (saves time at 115200 baud).
# dmesg is available post-boot for diagnostics.
KERNEL_ARGS:append = " quiet loglevel=0 audit=0"
