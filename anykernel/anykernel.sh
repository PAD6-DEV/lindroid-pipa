## AnyKernel3 for Xiaomi Pad 6 (pipa) — Lindroid Image only
## Based on osm0sis AnyKernel3 layout

properties() { '
do.devicecheck=1
do.modules=0
do.systemless=1
do.cleanup=1
do.cleanuponabort=0
device.name1=pipa
device.name2=
device.name3=
device.name4=
device.name5=
supported.versions=
supported.patchlevels=
'; }

block=boot;
is_slot_device=auto;
ramdisk_compression=auto;
patch_vbmeta_flag=auto;

. tools/ak3-core.sh;

ui_print "Lindroid pipa kernel (EVDI + LXC namespaces)";

split_boot;
flash_boot;
