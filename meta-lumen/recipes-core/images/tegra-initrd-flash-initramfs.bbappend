# When NVMe + PCIe + PHY are built into the kernel (=y via no-initrd.cfg),
# their module packages don't exist. Remove them from the flash initramfs
# since the built-in drivers handle NVMe access automatically.
PACKAGE_INSTALL:remove = "kernel-module-nvme kernel-module-pcie-tegra194 kernel-module-phy-tegra194-p2u"
