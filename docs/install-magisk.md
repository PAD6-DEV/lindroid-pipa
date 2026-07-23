# Install: stock Lineage + Magisk (pipa)

## 0. Prerequisites

- Unlocked bootloader  
- [LineageOS for pipa](https://github.com/LineageOS/android_device_xiaomi_pipa) community build (or crDroid / similar)  
- [Magisk](https://github.com/topjohnwu/Magisk) or KernelSU  
- Backup `boot` / `dtbo` before flashing kernels

## 1. Flash Lineage + Magisk

Install Lineage as usual, then Magisk (patch `boot.img` or flash Magisk APK via recovery).

Confirm:

```bash
adb shell getprop ro.system.build.id
adb shell su -c id
```

## 2. Lindroid kernel

CI prepares:

- `drivers/lindroid-drm` (EVDI)  
- `lindroid.config` fragment  

Flash a **boot image built with that kernel** for your Lineage major version.  
Mismatched kernels will not boot — match Lineage 21 / 22 / … tree to your zip.

Until CI publishes a ready `boot.img`, build Image with the fragment from this repo’s artifacts and pack with your Lineage ramdisk (`mkbootimg` / Android `boot.img` tools).

## 3. Magisk module (LindroidUI)

Upstream module only ships the **apphwc** side. You must supply binaries built against your ROM API:

1. Note `ro.system.build.id`  
2. Sync AOSP (or Lineage) matching that tag (generic_arm64 is OK for `mm`)  
3. Clone `vendor_lindroid`, `libhybris`, `external_lxc`; apply frameworks/native Lindroid pick  
4. `mm LindroidUI`  
5. Copy into the Magisk zip from this repo / upstream release:

```
system_ext/app/LindroidUI/
system_ext/lib64/libjni_lindroidui.so
system_ext/lib64/vendor.lindroid.composer-ndk.so
```

6. Flash module in Magisk → reboot  

**Do not** flash an upstream release zip without replacing those files for your build id.

Details: https://github.com/fish4terrisa-MSDSM/lindroid_module

## 4. SELinux + soft reboot

```bash
adb shell su -c setenforce 0
```

A14+ soft reboot when starting container: disable `systemd-udevd` in container, or [uUeventPatch](https://github.com/fish4terrisa-MSDSM/uEventPatch), or services.jar hack from Telegram pin.

## 5. Use Lindroid

Open **LindroidUI** → follow prompts → create/attach container.  
See [usage.md](usage.md).

## Still needed besides Magisk module

LXC userspace / libhybris bits may still need installing into the container side per Lindroid docs — the Magisk module does **not** replace a full `vendor/lindroid` userspace by itself. Expect iteration (logs: `adb logcat`, `dmesg`, `journalctl` in container).
