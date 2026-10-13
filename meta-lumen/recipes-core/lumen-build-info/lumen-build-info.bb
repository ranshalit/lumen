SUMMARY = "Lumen image build information"
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

LUMEN_BUILD_VERSION = "1.0.0"
LUMEN_BUILD_TIMESTAMP = "${DATETIME}"
LUMEN_BUILD_TIMESTAMP[vardepsexclude] = "DATETIME"
LUMEN_BUILD_GIT_SHA = ""

python __anonymous() {
    import os
    import subprocess

    recipe_dir = os.path.dirname(d.getVar("FILE"))
    git_sha = subprocess.check_output(
        ["git", "-C", recipe_dir, "rev-parse", "HEAD"],
        text=True,
    ).strip()
    d.setVar("LUMEN_BUILD_GIT_SHA", git_sha)
}

do_configure[noexec] = "1"
do_compile[noexec] = "1"

# Refresh the embedded timestamp and all dependent package/image tasks every build.
do_install[vardepsexclude] += "DATETIME DATE TIME"
do_install[nostamp] = "1"

do_install() {
    install -d ${D}${sysconfdir}
    cat > ${D}${sysconfdir}/lumen-build-info <<EOF
VERSION=${LUMEN_BUILD_VERSION}
BUILD_TIMESTAMP_UTC=${LUMEN_BUILD_TIMESTAMP}
GIT_COMMIT=${LUMEN_BUILD_GIT_SHA}
MACHINE=${MACHINE}
YOCTO_RELEASE=${DISTRO_VERSION}
EOF
}

FILES:${PN} = "${sysconfdir}/lumen-build-info"
