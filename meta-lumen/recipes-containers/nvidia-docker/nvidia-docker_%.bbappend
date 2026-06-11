# meta-lumen/recipes-containers/nvidia-docker/nvidia-docker_%.bbappend
#
# Override daemon.json to disable iptables and bridge networking.
# All application containers use --network=host so bridge/NAT are never
# needed. With iptables=false dockerd skips NAT chain creation entirely,
# allowing CONFIG_NF_CONNTRACK and CONFIG_NF_NAT to remain stripped from
# the kernel.

FILESEXTRAPATHS:prepend := "${THISDIR}/nvidia-docker:"

SRC_URI:append = " file://daemon.json"

do_install:append() {
    install -m 0644 ${WORKDIR}/daemon.json ${D}/${sysconfdir}/docker/daemon.json
}
