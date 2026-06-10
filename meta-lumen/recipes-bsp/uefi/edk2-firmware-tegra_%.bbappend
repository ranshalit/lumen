FILESEXTRAPATHS:prepend := "${THISDIR}/${PN}:"

SRC_URI:append = " file://edk2-boot-strip.cfg "

# Strip unused drivers + set Timeout=0 to eliminate UEFI boot countdown
do_deploy:append() {
    fdtput -t s ${DEPLOYDIR}/L4TConfiguration.dtbo \
        /fragment@0/__overlay__/firmware/uefi/variables/gNVIDIATokenSpaceGuid/DefaultBootPriority \
        data "nvme"
    fdtput -p -t hu ${DEPLOYDIR}/L4TConfiguration.dtbo \
        /fragment@0/__overlay__/firmware/uefi/variables/gEfiGlobalVariableGuid/Timeout \
        data 0x0
}
