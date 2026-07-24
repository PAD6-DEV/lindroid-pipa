#!/usr/bin/env bash
# CI: build Lineage sm8250 kernel for pipa with Lindroid EVDI, pack AnyKernel3 zip.
# Runs on GitHub Actions only — does not use local kernel trees.
set -euo pipefail

PORT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORK="${WORK_DIR:-$PORT_ROOT/.ci-kernel}"
JOBS="${BUILD_JOBS:-$(nproc)}"
ARTIFACT_DIR="${ARTIFACT_DIR:-$PORT_ROOT/artifacts}"
KERNEL_REPO="${KERNEL_REPO:-https://github.com/LineageOS/android_kernel_xiaomi_sm8250.git}"
KERNEL_BRANCH="${KERNEL_BRANCH:-lineage-22.2}"
CLANG_URL="${CLANG_URL:-https://android.googlesource.com/platform/prebuilts/clang/host/linux-x86/+archive/refs/heads/mirror-goog-main-llvm-toolchain-source/clang-r547379.tar.gz}"
AK3_REPO="${AK3_REPO:-https://github.com/osm0sis/AnyKernel3.git}"

mkdir -p "$WORK" "$ARTIFACT_DIR"
cd "$WORK"

# --- toolchain ---
CLANG_DIR="$WORK/clang"
if [[ ! -x "$CLANG_DIR/bin/clang" ]]; then
  echo "==> Fetching AOSP clang"
  rm -rf "$CLANG_DIR"
  mkdir -p "$CLANG_DIR"
  curl -L --retry 5 --retry-delay 5 -o "$WORK/clang.tar.gz" "$CLANG_URL"
  tar -xzf "$WORK/clang.tar.gz" -C "$CLANG_DIR"
  rm -f "$WORK/clang.tar.gz"
fi
export PATH="$CLANG_DIR/bin:$PATH"
clang --version | head -2

# --- kernel source ---
KERNEL_ROOT="$WORK/sm8250"
if [[ ! -d "$KERNEL_ROOT/.git" ]]; then
  echo "==> Cloning $KERNEL_REPO ($KERNEL_BRANCH)"
  rm -rf "$KERNEL_ROOT"
  git clone --depth 1 --branch "$KERNEL_BRANCH" "$KERNEL_REPO" "$KERNEL_ROOT"
else
  echo "==> Reusing existing kernel checkout"
fi

echo "==> Integrating Lindroid EVDI"
bash "$PORT_ROOT/kernel/integrate-drm.sh" "$KERNEL_ROOT"

mkdir -p "$KERNEL_ROOT/arch/arm64/configs/vendor/xiaomi"
cp -f "$PORT_ROOT/kernel/pipa.config" \
  "$KERNEL_ROOT/arch/arm64/configs/vendor/xiaomi/pipa.config"
cp -f "$PORT_ROOT/kernel/lindroid.config" \
  "$KERNEL_ROOT/arch/arm64/configs/vendor/xiaomi/lindroid.config"

cd "$KERNEL_ROOT"
rm -rf out
mkdir -p out

echo "==> Merging defconfig fragments (pipa + lindroid)"
# Lineage BoardConfigCommon + device pipa + our lindroid fragment
FRAGMENTS=(
  arch/arm64/configs/vendor/kona-perf_defconfig
  arch/arm64/configs/vendor/debugfs.config
  arch/arm64/configs/vendor/xiaomi/sm8250-common.config
  arch/arm64/configs/vendor/xiaomi/pipa.config
  arch/arm64/configs/vendor/xiaomi/lindroid.config
)
for f in "${FRAGMENTS[@]}"; do
  [[ -f "$f" ]] || { echo "missing fragment: $f" >&2; exit 1; }
done

export ARCH=arm64
export SUBARCH=arm64
export KBUILD_BUILD_USER=lindroid-pipa
export KBUILD_BUILD_HOST=github-actions

PATH_SAVE="$PATH"
# merge_config writes .config in cwd when -O is used
bash scripts/kconfig/merge_config.sh -m -O out "${FRAGMENTS[@]}"
make O=out ARCH=arm64 olddefconfig

# Lineage sm8250 + modern clang: unused vars/labels treated as errors otherwise
MAKE_ARGS=(
  ARCH=arm64
  SUBARCH=arm64
  O=out
  CC=clang
  LLVM=1
  LLVM_IAS=1
  CLANG_TRIPLE=aarch64-linux-gnu-
  CROSS_COMPILE=aarch64-linux-gnu-
  CROSS_COMPILE_COMPAT=arm-linux-gnueabi-
  CROSS_COMPILE_ARM32=arm-linux-gnueabi-
  KCFLAGS='-Wno-unused-variable -Wno-unused-label -Wno-error=unused-variable -Wno-error=unused-label'
  -j"$JOBS"
)

echo "==> Building Image (-j$JOBS)"
make "${MAKE_ARGS[@]}" Image 2>&1 | tee "$ARTIFACT_DIR/build.log"
# DTBO optional — fail soft if target missing
make "${MAKE_ARGS[@]}" dtbs 2>&1 | tee -a "$ARTIFACT_DIR/build.log" || true

IMAGE="$KERNEL_ROOT/out/arch/arm64/boot/Image"
[[ -f "$IMAGE" ]] || { echo "Image not produced" >&2; exit 1; }
ls -lh "$IMAGE"

# Verify Lindroid was enabled
if ! grep -q '^CONFIG_DRM_LINDROID_EVDI=y' out/.config; then
  echo "WARN: CONFIG_DRM_LINDROID_EVDI not y in final .config" >&2
  grep 'LINDROID\|DRM_EVDI\|SYSVIPC\|USER_NS' out/.config || true
fi
cp -f out/.config "$ARTIFACT_DIR/kernel.config"
cp -f "$IMAGE" "$ARTIFACT_DIR/Image"
cp -f "$PORT_ROOT/kernel/lindroid.config" "$ARTIFACT_DIR/lindroid.config"
cp -f "$PORT_ROOT/kernel/pipa.config" "$ARTIFACT_DIR/pipa.config"

# --- AnyKernel3 zip ---
echo "==> Packing AnyKernel3"
AK3="$WORK/AnyKernel3"
rm -rf "$AK3"
git clone --depth 1 "$AK3_REPO" "$AK3"
cp -f "$PORT_ROOT/anykernel/anykernel.sh" "$AK3/anykernel.sh"
cp -f "$IMAGE" "$AK3/Image"
# Drop stock sample Image.gz if present
rm -f "$AK3"/Image.gz "$AK3"/Image.lz4 2>/dev/null || true

ZIP_NAME="lindroid-pipa-kernel-${KERNEL_BRANCH}-$(date -u +%Y%m%d)-$(git -C "$KERNEL_ROOT" rev-parse --short HEAD).zip"
(
  cd "$AK3"
  zip -r9 "$ARTIFACT_DIR/$ZIP_NAME" \
    META-INF tools anykernel.sh Image LICENSE README.md 2>/dev/null \
    || zip -r9 "$ARTIFACT_DIR/$ZIP_NAME" META-INF tools anykernel.sh Image
)

# Convenience copy for release action
cp -f "$ARTIFACT_DIR/$ZIP_NAME" "$ARTIFACT_DIR/lindroid-pipa-anykernel.zip"

echo "==> Kernel build OK"
ls -lh "$ARTIFACT_DIR"
