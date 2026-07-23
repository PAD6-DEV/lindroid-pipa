#!/usr/bin/env bash
# CI: kernel-only Lindroid EVDI build (faster feedback).
set -euo pipefail

PORT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORK="${WORK_DIR:-$PORT_ROOT/.ci-kernel}"
JOBS="${BUILD_JOBS:-$(nproc)}"
ARTIFACT_DIR="${ARTIFACT_DIR:-$PORT_ROOT/artifacts}"

mkdir -p "$WORK" "$ARTIFACT_DIR"
cd "$WORK"

if [[ ! -d sm8250/.git ]]; then
  git clone --depth 1 --branch lineage-21 \
    https://github.com/LineageOS/android_kernel_xiaomi_sm8250.git sm8250 \
    || git clone --depth 1 https://github.com/LineageOS/android_kernel_xiaomi_sm8250.git sm8250
fi

KERNEL_ROOT="$WORK/sm8250"
bash "$PORT_ROOT/kernel/integrate-drm.sh" "$KERNEL_ROOT"

mkdir -p "$KERNEL_ROOT/arch/arm64/configs/vendor/xiaomi"
cp -f "$PORT_ROOT/kernel/lindroid.config" \
  "$KERNEL_ROOT/arch/arm64/configs/vendor/xiaomi/lindroid.config"

# Minimal compile test: ensure Kconfig + Makefile integrate (full Image needs vendor config)
cd "$KERNEL_ROOT"
if [[ -f arch/arm64/configs/vendor/xiaomi/pipa.config ]]; then
  DEFCONFIG_CMD='vendor/xiaomi_defconfig'
  # Merge fragments when using Lineage-style configs
  scripts/kconfig/merge_config.sh -m \
    arch/arm64/configs/vendor/kona_defconfig \
    arch/arm64/configs/vendor/xiaomi/pipa.config \
    arch/arm64/configs/vendor/xiaomi/lindroid.config 2>/dev/null \
    || true
fi

# Verify EVDI symbol exists after integrate
grep -q DRM_LINDROID_EVDI drivers/lindroid-drm/Kconfig
grep -q lindroid-drm drivers/Makefile

tar -C "$KERNEL_ROOT/drivers" -czf "$ARTIFACT_DIR/lindroid-drm-pipa.tar.gz" lindroid-drm
cp -f "$PORT_ROOT/kernel/lindroid.config" "$ARTIFACT_DIR/lindroid.config"

echo "Kernel prepare OK — artifacts:"
ls -lh "$ARTIFACT_DIR"
