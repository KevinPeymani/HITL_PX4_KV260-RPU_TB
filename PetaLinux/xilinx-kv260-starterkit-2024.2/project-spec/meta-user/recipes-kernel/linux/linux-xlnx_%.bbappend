FILESEXTRAPATHS:prepend := "${THISDIR}/${PN}:"

SRC_URI:append = " file://bsp.cfg"
KERNEL_FEATURES:append = " bsp.cfg"
SRC_URI += "file://user_2026-06-11-21-25-00.cfg \
            file://user_2026-10-22-20-53-00.cfg \
            "

