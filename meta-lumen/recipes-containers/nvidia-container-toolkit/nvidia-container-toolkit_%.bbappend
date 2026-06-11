# meta-lumen/recipes-containers/nvidia-container-toolkit/nvidia-container-toolkit_%.bbappend
#
# Adds a sysvinit init script that runs generate-config at boot to produce
# /run/nvidia-container-runtime/config.toml before dockerd starts GPU containers.
# This replaces the upstream systemd-only nvidia-container-setup.service unit.

FILESEXTRAPATHS:prepend := "${THISDIR}/nvidia-container-toolkit:"

SRC_URI:append = " \
    file://S50nvidia-container-setup \
"

do_install:append() {
    if ${@bb.utils.contains('DISTRO_FEATURES', 'sysvinit', 'true', 'false', d)}; then
        install -d ${D}${sysconfdir}/init.d
        install -m 0755 ${WORKDIR}/S50nvidia-container-setup \
            ${D}${sysconfdir}/init.d/nvidia-container-setup
        install -d ${D}${sysconfdir}/rc5.d
        ln -sf ../init.d/nvidia-container-setup \
            ${D}${sysconfdir}/rc5.d/S50nvidia-container-setup
    fi
}

INITSCRIPT_NAME = "nvidia-container-setup"
INITSCRIPT_PARAMS = "start 50 5 ."
