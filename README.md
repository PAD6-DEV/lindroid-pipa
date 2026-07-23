# Lindroid for Xiaomi Pad 6 (pipa) — Lineage + Magisk

**No full custom ROM.** Use stock/community **LineageOS** (or similar) + **Magisk/KernelSU** + a Lindroid-ready **kernel** and Magisk **module**.

Based on upstream Lindroid install notes and
[fish4terrisa-MSDSM/lindroid_module](https://github.com/fish4terrisa-MSDSM/lindroid_module)
(Android 14 tested with KernelSU; Magisk untested upstream).

## What you flash

1. **LineageOS for pipa** (stock community build — not a Lindroid-forked ROM)  
2. **Magisk** (or KernelSU)  
3. **CI kernel** with LXC namespaces + `CONFIG_DRM_LINDROID_EVDI`  
4. **Lindroid Magisk module** (LindroidUI / composer libs; SELinux permissive for now)

## What CI builds

| Job | Runner | Output |
|-----|--------|--------|
| Kernel prep + Image | `ubuntu-latest` | EVDI-integrated tree, `lindroid.config`, optional `Image` |
| Magisk module zip | `ubuntu-latest` | Module skeleton + instructions to drop in built APK/libs |

Full `brunch` ROM builds are **out of scope**.

## Install (short)

1. Unlock bootloader; flash Lineage for `pipa` + Magisk.  
2. Flash CI **boot** image (Lindroid kernel) matching your Lineage base.  
3. Build or obtain `LindroidUI` + libs for your ROM’s `ro.system.build.id` (see [docs/install-magisk.md](docs/install-magisk.md)).  
4. Pack/flash Magisk module; set SELinux permissive; open LindroidUI.  
5. Create/attach container (upstream commands in [docs/usage.md](docs/usage.md)).

A14+ soft-reboot / casefold: Telegram pin — https://t.me/linux_on_droid

## Kernel configs

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

## Layout

| Path | Role |
|------|------|
| `kernel/` | EVDI integrate + defconfig fragment |
| `magisk/` | Module template (apphwc) |
| `scripts/ci-kernel.sh` | CI kernel job |
| `scripts/ci-magisk.sh` | Package Magisk zip |
| `docs/install-magisk.md` | Full Magisk path |
| `docs/usage.md` | Container attach / logs |

## License

Apache-2.0 for this repo; upstream projects keep their licenses.
