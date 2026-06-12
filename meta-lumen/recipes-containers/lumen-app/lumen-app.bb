SUMMARY = "Auto-start lumen application stack via docker compose at boot"
DESCRIPTION = "Installs a sysvinit init script (S60lumen-app) that runs \
docker compose up on /opt/dragonfly/docker-compose.yaml at runlevel 5. \
BSP owns the boot mechanism; app team owns the compose file and images."

LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

PACKAGE_ARCH = "${MACHINE_ARCH}"
COMPATIBLE_MACHINE = "(lumen)"

SRC_URI = "file://S60lumen-app"

S = "${WORKDIR}"

do_configure[noexec] = "1"
do_compile[noexec] = "1"

do_install() {
    install -d ${D}${sysconfdir}/init.d
    install -m 0755 ${WORKDIR}/S60lumen-app \
        ${D}${sysconfdir}/init.d/lumen-app

    install -d ${D}${sysconfdir}/rc5.d
    ln -sf ../init.d/lumen-app \
        ${D}${sysconfdir}/rc5.d/S60lumen-app
}

FILES:${PN} += "${sysconfdir}/init.d/lumen-app ${sysconfdir}/rc5.d/S60lumen-app"

INITSCRIPT_NAME = "lumen-app"
INITSCRIPT_PARAMS = "start 60 5 ."

inherit update-rc.d
