#!/usr/bin/env bash
# Integrate lindroid-drm-loopback into an Android kernel tree (CI only).
set -euo pipefail

KERNEL_ROOT="${1:-${KERNEL_ROOT:-}}"
if [[ -z "$KERNEL_ROOT" || ! -d "$KERNEL_ROOT" ]]; then
  echo "usage: $0 /path/to/kernel/xiaomi/sm8250" >&2
  exit 1
fi

DRM_DIR="$KERNEL_ROOT/drivers/lindroid-drm"
BRANCH="${LINDROID_DRM_REF:-master}"

if [[ ! -d "$DRM_DIR/.git" ]]; then
  rm -rf "$DRM_DIR"
  git clone --depth 1 --branch "$BRANCH" \
    https://github.com/Linux-on-droid/lindroid-drm-loopback.git "$DRM_DIR"
fi

# drivers/Makefile
if ! grep -q 'lindroid-drm' "$KERNEL_ROOT/drivers/Makefile"; then
  printf '\nobj-y += lindroid-drm/\n' >>"$KERNEL_ROOT/drivers/Makefile"
fi

# drivers/Kconfig
if ! grep -q 'lindroid-drm' "$KERNEL_ROOT/drivers/Kconfig"; then
  # Insert before endmenu if present, else append
  if grep -q '^endmenu' "$KERNEL_ROOT/drivers/Kconfig"; then
    sed -i '/^endmenu/i source "drivers/lindroid-drm/Kconfig"' "$KERNEL_ROOT/drivers/Kconfig"
  else
    printf '\nsource "drivers/lindroid-drm/Kconfig"\n' >>"$KERNEL_ROOT/drivers/Kconfig"
  fi
fi

# In-tree build: lindroid Makefile expects non-DKMS path with obj-y
# Ensure the upstream Makefile's else branch is used (default).

echo "Lindroid EVDI integrated at $DRM_DIR"
