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

# Keep: acl xattr opengl vulkan alsa ext2 ipv4 usbgadget usbhost seccomp

# syslog: removable — dmesg ring buffer is accessible live via `dmesg`
VIRTUAL-RUNTIME_base-utils-syslog = ""

# alsa-state: no audio hardware in use on Lumen
BAD_RECOMMENDATIONS:append = " alsa-state alsa-states"
