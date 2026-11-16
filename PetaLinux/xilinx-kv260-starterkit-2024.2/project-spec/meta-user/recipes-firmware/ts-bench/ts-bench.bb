#
# This file is the ts-bench recipe.
#

SUMMARY = "Simple ts-bench to use dfx_user_dts class"
SECTION = "PETALINUX/apps"
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

inherit dfx_user_dts

COMPATIBLE_MACHINE:versal-net = ".*"
COMPATIBLE_MACHINE:versal = ".*"
COMPATIBLE_MACHINE:zynqmp = ".*"
COMPATIBLE_MACHINE:zynq = ".*"


SRC_URI = "file://timestamp_block.bit \
	file://pl.dtsi \
	file://shell.json"

inherit update-alternatives

# Point /etc/dfx-mgrd/default_firmware at ts-bench so dfx-mgr loads it at boot.
do_install:append() {
	install -d ${D}${sysconfdir}/dfx-mgrd
	echo "${PN}" > ${D}${sysconfdir}/dfx-mgrd/${PN}
}

FILES:${PN} += "${sysconfdir}"

ALTERNATIVE:${PN} = "default_firmware"
ALTERNATIVE_TARGET[default_firmware] = "${sysconfdir}/dfx-mgrd/${PN}"
ALTERNATIVE_LINK_NAME[default_firmware] = "${sysconfdir}/dfx-mgrd/default_firmware"
ALTERNATIVE_PRIORITY[default_firmware] = "100"
