#!/usr/bin/env bash
# CI: init/sync LineageOS 21 + Lindroid local manifest for pipa.
set -euo pipefail

ROOT="${ANDROID_BUILD_TOP:-${PWD}/android}"
BRANCH="${LINEAGE_BRANCH:-lineage-21.0}"
MANIFEST_URL="${LINEAGE_MANIFEST:-https://github.com/LineageOS/android.git}"
JOBS="${SYNC_JOBS:-$(nproc)}"
PORT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

mkdir -p "$ROOT"
cd "$ROOT"

if [[ ! -d .repo ]]; then
  repo init -u "$MANIFEST_URL" -b "$BRANCH" --git-lfs
fi

mkdir -p .repo/local_manifests
cp -f "$PORT_ROOT/manifests/lindroid-pipa.xml" .repo/local_manifests/lindroid-pipa.xml

# Ensure github remote exists for Linux-on-droid projects
if [[ -f .repo/manifests/default.xml ]] && ! grep -q 'remote name="github"' .repo/manifest.xml .repo/manifests/*.xml 2>/dev/null; then
  cat >.repo/local_manifests/00-github-remote.xml <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<manifest>
  <remote name="github" fetch="https://github.com/" />
</manifest>
EOF
fi

repo sync -c -j"$JOBS" --force-sync --no-clone-bundle --no-tags

# Pull device deps (roomservice-style)
# shellcheck disable=SC1091
source build/envsetup.sh
breakfast lineage_pipa || true
repo sync -c -j"$JOBS" --force-sync --no-clone-bundle --no-tags

echo "Sync complete in $ROOT"
