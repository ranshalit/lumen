# meta-lumen/recipes-kernel/linux/linux-jammy-nvidia-tegra_%.bbappend
#
# Lumen-specific kernel config fragments.
# DTS/DTB patches are applied in nvidia-kernel-oot_%.bbappend because
# in JetPack 6.x (L4T 36.x) device trees are built out-of-tree by
# the nvidia-kernel-oot recipe.
#
# Module-stripping fragments (all machines, applied in phase order):
#   Phase 1 — IPv6, WiFi stack, CAN, tunnels, netfilter modules, BTRFS, BCM Ethernet
#   Phase 2 — Bluetooth transport drivers, all audio codec/platform modules (~110 modules)
#
# To roll back a phase: git revert <phase-commit> && bitbake linux-jammy-nvidia-tegra
SRC_URI:append:lumen = " \
    file://strip-phase1-net.cfg \
    file://strip-phase2-bt-audio.cfg \
    "
