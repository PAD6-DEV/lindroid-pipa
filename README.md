# Lindroid for Xiaomi Pad 6 (pipa) — Lineage + Magisk

**No full custom ROM.** Stock/community **LineageOS** + **Magisk/KernelSU** + CI-built **Lindroid kernel** + Magisk **module**.

Releases: https://github.com/PAD6-DEV/lindroid-pipa/releases

## Flash

1. LineageOS for `pipa` + Magisk  
2. Flash **lindroid-pipa-anykernel.zip** from [Releases](https://github.com/PAD6-DEV/lindroid-pipa/releases) (recovery or Magisk)  
3. Build/replace LindroidUI libs in the Magisk zip for your `ro.system.build.id` — [docs/install-magisk.md](docs/install-magisk.md)  
4. `adb shell su -c setenforce 0` → open LindroidUI  

## CI (GitHub Actions only)

| Job | Output |
|-----|--------|
| **Build Lindroid kernel** | Compiles `Image` from LineageOS `android_kernel_xiaomi_sm8250` + EVDI + LXC configs → **AnyKernel3 zip** |
| Magisk module | Zip skeleton |
| Release | Uploads kernel zip + Image + Magisk zip to GitHub Releases (tags `v*`, `main` nightlies, or workflow_dispatch) |

Manual run: Actions → **Lindroid pipa** → Run workflow → pick kernel branch (`lineage-22.2` default).

```bash
# local reproduction of CI scripts (still clones into .ci-kernel/, not your trees)
KERNEL_BRANCH=lineage-22.2 ./scripts/ci-kernel.sh
```

## Kernel configs added

```
CONFIG_SYSVIPC / UTS/PID/IPC/USER/NET_NS / CGROUP_DEVICE / CGROUP_FREEZER
CONFIG_DRM_LINDROID_EVDI=y
```

Plus Lineage fragments: `kona-perf` + `debugfs` + `sm8250-common` + `pipa.config`.

## Layout

| Path | Role |
|------|------|
| `scripts/ci-kernel.sh` | Clone Lineage kernel, EVDI, build Image, AnyKernel3 |
| `kernel/` | EVDI integrate + config fragments |
| `anykernel/` | pipa AnyKernel3 script |
| `magisk/` | Magisk module template |
| `docs/install-magisk.md` | Full install notes |

## License

Apache-2.0 for this repo; upstream projects keep their licenses.
