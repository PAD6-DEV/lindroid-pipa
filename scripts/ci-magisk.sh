#!/usr/bin/env bash
# CI: build LindroidUI (+ JNI / composer) from AOSP and pack Magisk zip.
# Intended for GitHub Actions (free-disk-space) or a large self-hosted runner.
set -euo pipefail

PORT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORK="${WORK_DIR:-$PORT_ROOT/.ci-aosp}"
OUT="${ARTIFACT_DIR:-$PORT_ROOT/artifacts}"
AOSP_TAG="${AOSP_TAG:-android-14.0.0_r75}"
LINDROID_REF="${LINDROID_REF:-lindroid-21}"
JOBS="${BUILD_JOBS:-$(nproc)}"
MANIFEST_URL="${MANIFEST_URL:-https://android.googlesource.com/platform/manifest}"

mkdir -p "$WORK" "$OUT"
cd "$WORK"

echo "==> Disk before sync"
df -h . || true

# --- repo tool ---
if ! command -v repo >/dev/null 2>&1; then
  mkdir -p "$HOME/bin"
  curl -fsSL https://storage.googleapis.com/git-repo-downloads/repo -o "$HOME/bin/repo"
  chmod +x "$HOME/bin/repo"
  export PATH="$HOME/bin:$PATH"
fi

git config --global user.email "ci@lindroid-pipa"
git config --global user.name "lindroid-pipa-ci"
git config --global color.ui false
git config --global trailer.sign.key ""

# --- init / sync (shallow) ---
if [[ ! -d .repo ]]; then
  echo "==> repo init $AOSP_TAG"
  repo init -u "$MANIFEST_URL" -b "$AOSP_TAG" --depth=1 --partial-clone --clone-filter=blob:limit=10M
fi

mkdir -p .repo/local_manifests
cp -f "$PORT_ROOT/manifests/lindroid-ui.xml" .repo/local_manifests/lindroid-ui.xml
# Pin vendor_lindroid revision via sed if LINDROID_REF overridden
sed -i "s/revision=\"lindroid-21\"/revision=\"$LINDROID_REF\"/" \
  .repo/local_manifests/lindroid-ui.xml

echo "==> repo sync (-j$JOBS)"
repo sync -c -j"$JOBS" --no-tags --optimized-fetch --prune --current-branch \
  || repo sync -c -j4 --no-tags --optimized-fetch --current-branch

# Drop bulky unused trees (need headroom for out/).
# Keep prebuilts/bazel and ALL of kernel/configs (kernel-config-soong-rules lives
# under kernel/configs/build — do not delete that path).
for d in \
  device/google \
  prebuilts/clang/host/darwin-x86 \
  prebuilts/gcc/darwin-x86 prebuilts/qemu-kernel \
  external/webrtc toolchain/pyston \
  art/test cts development/samples development/apps \
  external/chromium-webview external/deqp \
  prebuilts/asuite prebuilts/android-emulator \
  prebuilts/remoteexecution-client \
  tools/ndkports tools/vendor \
  kernel/common kernel/build kernel/tests \
  kernel/prebuilts kernel/hikey-modules
do
  [[ -d "$d" ]] && rm -rf "$d" && echo "removed $d" || true
done
if [[ ! -d kernel/configs ]]; then
  echo "ERROR: kernel/configs missing after sync — required for soong" >&2
  exit 1
fi
df -h . || true

echo "==> Disk after sync"
df -h . || true

# --- frameworks/native Lindroid pick (best-effort) ---
if [[ -d frameworks/native/.git ]]; then
  cd frameworks/native
  for url in \
    "https://github.com/LineageOS/android_frameworks_native/commit/94dd1b1bda79e783b1610470a5284bb6f300340e.patch" \
    "https://github.com/LMODroid/platform_frameworks_native/commit/51b680f33b66e06b18725fdf9a54fa923c14a10b.patch"
  do
    curl -fsSL "$url" -o /tmp/lindroid-native.patch || continue
    if git apply --check /tmp/lindroid-native.patch 2>/dev/null; then
      git apply /tmp/lindroid-native.patch
      echo "Applied $url"
      break
    fi
  done
  cd "$WORK"
fi

# Ensure vendor/lindroid is on requested ref (repo uses remote "github", not origin)
if [[ -d vendor/lindroid/.git ]]; then
  VL_REMOTE=github
  git -C vendor/lindroid remote get-url github >/dev/null 2>&1 \
    || VL_REMOTE="$(git -C vendor/lindroid remote | head -1)"
  git -C vendor/lindroid fetch --depth 1 "$VL_REMOTE" "$LINDROID_REF" || true
  git -C vendor/lindroid checkout -B "$LINDROID_REF" FETCH_HEAD 2>/dev/null \
    || git -C vendor/lindroid checkout -f "$LINDROID_REF" || true
fi

# --- build ---
# android-14.0.0_r75+ requires product-release-variant (e.g. aosp_arm64-ap2a-eng)
set +u
# shellcheck disable=SC1091
source build/envsetup.sh
LUNCH_OK=0
for combo in \
  "${LUNCH_COMBO:-}" \
  "aosp_arm64-ap2a-eng" \
  "aosp_arm64-ap2a-userdebug" \
  "aosp_arm64-aosp_current-eng" \
  "aosp_arm64-trunk_staging-eng" \
  "aosp_arm64-eng"
do
  [[ -z "$combo" ]] && continue
  echo "==> trying lunch $combo"
  if lunch "$combo"; then
    LUNCH_OK=1
    break
  fi
done
[[ "$LUNCH_OK" -eq 1 ]] || { echo "No valid lunch combo worked" >&2; exit 1; }
set -u

echo "==> m LindroidUI (-j$JOBS)"
m LindroidUI -j"$JOBS"

PRODUCT_OUT="$(get_build_var PRODUCT_OUT 2>/dev/null || true)"
PRODUCT_OUT="${PRODUCT_OUT:-$WORK/out/target/product/generic_arm64}"

APP_DIR=""
for cand in \
  "$PRODUCT_OUT/system_ext/app/LindroidUI" \
  "$PRODUCT_OUT/system/system_ext/app/LindroidUI" \
  "$WORK/out/target/product/generic_arm64/system_ext/app/LindroidUI" \
  "$WORK/out/target/product/generic_arm64/system/system_ext/app/LindroidUI"
do
  if [[ -d "$cand" ]]; then APP_DIR="$cand"; break; fi
done
[[ -n "$APP_DIR" ]] || { echo "LindroidUI app dir not found under $PRODUCT_OUT"; find out -name 'LindroidUI*' 2>/dev/null | head -50; exit 1; }

LIB64=""
for cand in \
  "$PRODUCT_OUT/system_ext/lib64" \
  "$PRODUCT_OUT/system/system_ext/lib64" \
  "$WORK/out/target/product/generic_arm64/system_ext/lib64" \
  "$WORK/out/target/product/generic_arm64/system/system_ext/lib64"
do
  if [[ -f "$cand/libjni_lindroidui.so" ]]; then LIB64="$cand"; break; fi
done
[[ -n "$LIB64" ]] || { echo "libjni_lindroidui.so not found"; exit 1; }

COMPOSER="$LIB64/vendor.lindroid.composer-ndk.so"
[[ -f "$COMPOSER" ]] || {
  # Sometimes only the aidl stub name differs — search
  COMPOSER="$(find "$PRODUCT_OUT" "$WORK/out" -name 'vendor.lindroid.composer*.so' 2>/dev/null | head -1 || true)"
}
[[ -n "${COMPOSER:-}" && -f "$COMPOSER" ]] || { echo "composer ndk .so missing"; exit 1; }

echo "==> Packaging Magisk zip"
STAGE="$OUT/magisk-stage"
rm -rf "$STAGE"
mkdir -p "$STAGE/META-INF/com/google/android"
mkdir -p "$STAGE/system_ext/app/LindroidUI"
mkdir -p "$STAGE/system_ext/lib64"

cp -a "$APP_DIR"/. "$STAGE/system_ext/app/LindroidUI/"
cp -f "$LIB64/libjni_lindroidui.so" "$STAGE/system_ext/lib64/"
cp -f "$COMPOSER" "$STAGE/system_ext/lib64/vendor.lindroid.composer-ndk.so"
# APK-local JNI symlink path used by some packagings
mkdir -p "$STAGE/system_ext/app/LindroidUI/lib/arm64"
ln -sfn /system_ext/lib64/libjni_lindroidui.so \
  "$STAGE/system_ext/app/LindroidUI/lib/arm64/libjni_lindroidui.so" 2>/dev/null || \
  cp -f "$LIB64/libjni_lindroidui.so" \
    "$STAGE/system_ext/app/LindroidUI/lib/arm64/libjni_lindroidui.so"

cp -f "$PORT_ROOT/magisk/module.prop" "$STAGE/module.prop"
cp -f "$PORT_ROOT/magisk/customize.sh" "$STAGE/customize.sh"
chmod +x "$STAGE/customize.sh"

cat >"$STAGE/META-INF/com/google/android/updater-script" <<'EOF'
#MAGISK
EOF
curl -fsSL \
  'https://raw.githubusercontent.com/topjohnwu/Magisk/master/scripts/module_installer.sh' \
  -o "$STAGE/META-INF/com/google/android/update-binary" \
  || printf '%s\n' '#!/sbin/sh' 'exit 0' >"$STAGE/META-INF/com/google/android/update-binary"
chmod +x "$STAGE/META-INF/com/google/android/update-binary"

# Record what we built
{
  echo "aosp_tag=$AOSP_TAG"
  echo "lindroid_ref=$LINDROID_REF"
  echo "built=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
} >"$STAGE/buildinfo.txt"

(
  cd "$STAGE"
  zip -r9 "$OUT/lindroid-pipa-magisk.zip" . >/dev/null
)

cp -f "$PORT_ROOT/docs/install-magisk.md" "$OUT/"
ls -lh "$OUT/lindroid-pipa-magisk.zip"
unzip -l "$OUT/lindroid-pipa-magisk.zip" | head -40
echo "==> Magisk module build OK"
