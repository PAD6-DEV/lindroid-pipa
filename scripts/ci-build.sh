#!/usr/bin/env bash
# CI: build lineage_pipa userdebug with Lindroid.
set -euo pipefail

ROOT="${ANDROID_BUILD_TOP:-${PWD}/android}"
OUT_DIR="${OUT_DIR:-$ROOT/out}"
ARTIFACT_DIR="${ARTIFACT_DIR:-${PWD}/artifacts}"
cd "$ROOT"

# shellcheck disable=SC1091
source build/envsetup.sh
lunch lineage_pipa-userdebug

mka bacon -j"${BUILD_JOBS:-$(nproc)}"

mkdir -p "$ARTIFACT_DIR"
# Collect typical Lineage artifacts
shopt -s nullglob
for f in \
  "$OUT_DIR"/target/product/pipa/lineage-*.zip \
  "$OUT_DIR"/target/product/pipa/boot.img \
  "$OUT_DIR"/target/product/pipa/dtbo.img \
  "$OUT_DIR"/target/product/pipa/vendor_boot.img \
  "$OUT_DIR"/target/product/pipa/recovery.img
do
  cp -v "$f" "$ARTIFACT_DIR/"
done

echo "Artifacts in $ARTIFACT_DIR"
ls -lh "$ARTIFACT_DIR"
