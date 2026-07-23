#!/usr/bin/env bash
# CI: inject Lindroid per upstream install guide (lindroid.org / Telegram pin).
set -euo pipefail

ROOT="${ANDROID_BUILD_TOP:-${PWD}/android}"
PORT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

KERNEL_ROOT="${KERNEL_ROOT:-$ROOT/kernel/xiaomi/sm8250}"
DEVICE_MK="${DEVICE_MK:-$ROOT/device/xiaomi/pipa/lineage_pipa.mk}"

if [[ ! -d "$KERNEL_ROOT" ]]; then
  echo "ERROR: kernel tree missing at $KERNEL_ROOT" >&2
  exit 1
fi

# --- Kernel: drivers/lindroid-drm + Makefile/Kconfig ---
bash "$PORT_ROOT/kernel/integrate-drm.sh" "$KERNEL_ROOT"

FRAG_DIR="$KERNEL_ROOT/arch/arm64/configs/vendor/xiaomi"
mkdir -p "$FRAG_DIR"
cp -f "$PORT_ROOT/kernel/lindroid.config" "$FRAG_DIR/lindroid.config"

BOARD="$ROOT/device/xiaomi/pipa/BoardConfig.mk"
if [[ -f "$BOARD" ]] && ! grep -q 'lindroid.config' "$BOARD"; then
  if grep -q 'TARGET_KERNEL_CONFIG += vendor/xiaomi/pipa.config' "$BOARD"; then
    sed -i '/TARGET_KERNEL_CONFIG += vendor\/xiaomi\/pipa.config/a TARGET_KERNEL_CONFIG += vendor/xiaomi/lindroid.config' "$BOARD"
  else
    printf '\nTARGET_KERNEL_CONFIG += vendor/xiaomi/lindroid.config\n' >>"$BOARD"
  fi
fi

# FCM: drop "# CONFIG_SYSVIPC is not set" from android-base.config fragments
while IFS= read -r -d '' f; do
  if grep -q '^# CONFIG_SYSVIPC is not set' "$f"; then
    echo "Stripping CONFIG_SYSVIPC unset from $f"
    sed -i '/^# CONFIG_SYSVIPC is not set/d' "$f"
  fi
done < <(find "$ROOT/kernel/configs" -name 'android-base.config' -print0 2>/dev/null || true)

# --- Device: inherit vendor/lindroid/lindroid.mk ---
cp -f "$PORT_ROOT/device/lindroid_pipa.mk" "$ROOT/device/xiaomi/pipa/lindroid_pipa.mk"
if [[ -f "$DEVICE_MK" ]] && ! grep -q 'vendor/lindroid/lindroid.mk\|lindroid_pipa.mk' "$DEVICE_MK"; then
  {
    echo ''
    echo '# Lindroid (CI — upstream install guide)'
    echo '$(call inherit-product, vendor/lindroid/lindroid.mk)'
  } >>"$DEVICE_MK"
fi

# --- frameworks/native pick (Lineage / LMODroid) ---
NATIVE="$ROOT/frameworks/native"
if [[ -d "$NATIVE/.git" ]]; then
  cd "$NATIVE"
  applied=0
  for url in \
    "${LINDROID_NATIVE_PATCH:-https://github.com/LineageOS/android_frameworks_native/commit/94dd1b1bda79e783b1610470a5284bb6f300340e.patch}" \
    "https://github.com/LMODroid/platform_frameworks_native/commit/51b680f33b66e06b18725fdf9a54fa923c14a10b.patch"
  do
    curl -fsSL "$url" -o /tmp/lindroid-native.patch || continue
    if git apply --check /tmp/lindroid-native.patch 2>/dev/null; then
      git apply /tmp/lindroid-native.patch
      echo "Applied native patch: $url"
      applied=1
      break
    fi
  done
  if [[ "$applied" -eq 0 ]]; then
    echo "WARNING: frameworks/native Lindroid patch did not apply cleanly — pick manually."
  fi
  cd "$ROOT"
fi

# Soft-reboot (A14+) and overlayfs/casefold hacks live in Telegram pin only.
# Documented in README; not auto-applied (no stable public patch URL).
echo "NOTE: For A14+ soft-reboot / casefold overlayfs, apply Telegram pinned hacks if needed."

echo "Prepare done (upstream install checklist)."
