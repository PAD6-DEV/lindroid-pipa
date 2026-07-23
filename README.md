# Lindroid for Xiaomi Pad 6 (pipa)

CI automation of the upstream [Lindroid install steps](https://www.lindroid.org/)
for **pipa**, on **LineageOS 21** (`userdebug`).

> Non-developers: wait for a flashed build / Magisk path. This repo is for
> building a Lindroid-enabled ROM.

## Upstream install checklist (what CI automates)

| Step | CI |
|------|----|
| Clone `lindroid-drm` → `drivers/lindroid-drm` | [`kernel/integrate-drm.sh`](kernel/integrate-drm.sh) |
| `obj-y += lindroid-drm/` in `drivers/Makefile` | same |
| `source "drivers/lindroid-drm/Kconfig"` in `drivers/Kconfig` | same |
| Kernel defconfigs (pinned list) | [`kernel/lindroid.config`](kernel/lindroid.config) |
| Clone `vendor_lindroid`, `external_lxc`, `libhybris` (+ `vendor/extra`) | [`manifests/lindroid-pipa.xml`](manifests/lindroid-pipa.xml) |
| `$(call inherit-product, vendor/lindroid/lindroid.mk)` | [`device/lindroid_pipa.mk`](device/lindroid_pipa.mk) |
| frameworks/native Lindroid pick | [`scripts/ci-prepare.sh`](scripts/ci-prepare.sh) |
| Soft-reboot A14+ workaround / casefold overlayfs hack | documented; apply from Telegram pinned if needed |
| FCM `CONFIG_SYSVIPC` clash | CI strips `# CONFIG_SYSVIPC is not set` from `kernel/configs` |
| Build & flash AOSP **userdebug** | [`scripts/ci-build.sh`](scripts/ci-build.sh) |

## Kernel configs (required)

```
CONFIG_SYSVIPC=y
CONFIG_UTS_NS=y
CONFIG_PID_NS=y
CONFIG_IPC_NS=y
CONFIG_USER_NS=y
CONFIG_NET_NS=y
CONFIG_CGROUP_DEVICE=y
CONFIG_CGROUP_FREEZER=y
CONFIG_DRM_LINDROID_EVDI=y
```

If the build fails FCM because of SYSVIPC: remove `# CONFIG_SYSVIPC is not set`
from `$ANDROID_BUILD_TOP/kernel/configs/*/*/android-base.config` (CI does this).

## After flash

1. Open **Lindroid** and follow prompts.  
2. Attach to Debian shell:

```bash
adb shell -t lxc_attach default -- "/bin/bash -c \"source /etc/profile && exec su - root\""
```

3. Create container (example):

```bash
adb shell -t lxc_create default -t lindroid -- -f /dev/fd/4
# when prompted: user lindroid / pass lindroid
```

### Useful commands

```bash
# logs
adb logcat
adb shell dmesg
# inside container:
journalctl --no-pager --boot

# apt force overwrite
sudo apt-get -o Dpkg::Options::="--force-overwrite" …

# XDG hack (manual KWin)
export XDG_RUNTIME_DIR=/tmp/runtime-lindroid
mkdir -p "$XDG_RUNTIME_DIR"
chmod 700 "$XDG_RUNTIME_DIR"

# Wayland app from CLI (KWin running)
EGL_PLATFORM=wayland WAYLAND_DISPLAY=wayland-0 APP
# Plasma via DM:
XDG_RUNTIME_DIR=/run/user/1000 EGL_PLATFORM=wayland WAYLAND_DISPLAY=wayland-0 APP
```

**A14+ soft reboot** when starting the container and **overlayfs/casefold** mounts:
use the temporary hacks from the Lindroid Telegram pinned message
([t.me/linux_on_droid](https://t.me/linux_on_droid)).

## CI

- **GitHub-hosted:** kernel DRM + config prep only (`scripts/ci-kernel.sh`)  
- **Full ROM:** self-hosted runner label `lindroid-pipa` (≥300 GB disk) — Actions → *Run workflow* → `full_rom`

```bash
./scripts/ci.sh kernel    # hosted-friendly
./scripts/ci.sh all       # sync + prepare + brunch (fat runner)
```

## Layout

| Path | Role |
|------|------|
| `manifests/lindroid-pipa.xml` | Lindroid projects for `repo` |
| `device/lindroid_pipa.mk` | `inherit-product` lindroid.mk |
| `kernel/` | EVDI integrate + defconfig fragment |
| `scripts/ci-*.sh` | sync / prepare / build |

## License

Apache-2.0 for this repo’s scripts; Lindroid/Lineage keep their licenses.
