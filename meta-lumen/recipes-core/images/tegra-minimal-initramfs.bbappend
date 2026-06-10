# When NVMe + PCIe + PHY are built into the kernel (=y via no-initrd.cfg),
# their module packages don't exist. Remove them from the boot initramfs too.
# This recipe is only built when INITRAMFS_IMAGE is non-empty; with
# INITRAMFS_IMAGE="" set in lumen-common.inc this bbappend has no effect.
PACKAGE_INSTALL:remove = "kernel-module-nvme kernel-module-pcie-tegra194 kernel-module-phy-tegra194-p2u"
