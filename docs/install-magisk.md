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

CI builds a real `Image` and publishes **lindroid-pipa-anykernel.zip** on
[Releases](https://github.com/PAD6-DEV/lindroid-pipa/releases).

1. Pick a release whose kernel branch matches your Lineage (e.g. `lineage-22.2`).  
2. Flash `lindroid-pipa-anykernel.zip` in recovery (or Magisk module install for AK3).  
3. Keep a stock `boot` backup — wrong branch = no boot.

Artifacts also include raw `Image` + `kernel.config` for debugging.

## 3. Magisk module (LindroidUI)

CI builds **LindroidUI** + JNI/composer against AOSP `aosp_arm64` (`android-14.0.0_r75` by default) and publishes **lindroid-pipa-magisk.zip**.

1. Flash that zip in Magisk → reboot  
2. Prefer a ROM whose API matches the AOSP tag used in the release notes  
3. If the app crashes on a mismatched `ro.system.build.id`, rebuild with workflow input `aosp_tag` set to a closer tag (or rebuild locally with `./scripts/ci-magisk.sh`)

Still Magisk/apphwc-only — LXC/libhybris container side is separate (upstream Lindroid docs).

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
