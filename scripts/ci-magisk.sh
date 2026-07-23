#!/usr/bin/env bash
# Package Magisk module zip (APK/libs placeholders + instructions).
set -euo pipefail

PORT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="${ARTIFACT_DIR:-$PORT_ROOT/artifacts}"
STAGE="$OUT/magisk-stage"

rm -rf "$STAGE"
mkdir -p "$STAGE/META-INF/com/google/android"
mkdir -p "$STAGE/system_ext/app/LindroidUI"
mkdir -p "$STAGE/system_ext/lib64"

cp -f "$PORT_ROOT/magisk/module.prop" "$STAGE/module.prop"
cp -f "$PORT_ROOT/magisk/customize.sh" "$STAGE/customize.sh"
chmod +x "$STAGE/customize.sh"

# Placeholder so zip structure is valid; CI/user must overwrite
cat >"$STAGE/system_ext/app/LindroidUI/README.txt" <<'EOF'
Replace this directory with out/target/product/*/system_ext/app/LindroidUI
from an AOSP/Lineage tree matching ro.system.build.id (mm LindroidUI).
Also copy:
  system_ext/lib64/libjni_lindroidui.so
  system_ext/lib64/vendor.lindroid.composer-ndk.so
See docs/install-magisk.md
EOF

# Minimal Magisk update-binary stub (module install uses Magisk app;
# for recovery flash, users should use Magisk Manager zip install)
cat >"$STAGE/META-INF/com/google/android/updater-script" <<'EOF'
#MAGISK
EOF

curl -fsSL \
  'https://raw.githubusercontent.com/topjohnwu/Magisk/master/scripts/module_installer.sh' \
  -o "$STAGE/META-INF/com/google/android/update-binary" \
  || printf '%s\n' '#!/sbin/sh' 'exit 0' >"$STAGE/META-INF/com/google/android/update-binary"
chmod +x "$STAGE/META-INF/com/google/android/update-binary"

mkdir -p "$OUT"
(
  cd "$STAGE"
  zip -r9 "$OUT/lindroid-pipa-magisk.zip" . >/dev/null
)

cp -f "$PORT_ROOT/docs/install-magisk.md" "$OUT/"
echo "Wrote $OUT/lindroid-pipa-magisk.zip"
ls -lh "$OUT"
