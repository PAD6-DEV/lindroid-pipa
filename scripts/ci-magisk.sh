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
# Continue if a single project (e.g. hikey-kernel) fails checkout
set +e
repo sync -c -j"$JOBS" --no-tags --optimized-fetch --prune --current-branch
SYNC_RC=$?
if [[ "$SYNC_RC" -ne 0 ]]; then
  echo "repo sync returned $SYNC_RC — retry force-sync"
  repo sync -c -j4 --no-tags --optimized-fetch --force-sync --current-branch
  SYNC_RC=$?
fi
set -e
# Critical paths must exist even if some device trees failed
for must in build/make build/soong frameworks/base prebuilts/build-tools; do
  if [[ ! -d "$must" ]]; then
    echo "ERROR: core path missing after sync: $must (sync rc=$SYNC_RC)" >&2
    exit 1
  fi
done
# kernel/configs is a separate project — sync it explicitly if missing
if [[ ! -d kernel/configs ]]; then
  echo "==> syncing kernel/configs explicitly"
  repo sync -c -j4 kernel/configs || \
    git clone --depth 1 --branch "$AOSP_TAG" \
      https://android.googlesource.com/kernel/configs kernel/configs
fi
if [[ ! -d cts ]]; then
  echo "==> syncing cts explicitly"
  repo sync -c -j4 cts || true
fi

# Drop bulky unused trees (need headroom for out/).
# Keep: prebuilts/bazel, kernel/configs/, cts.
# Soong parses the WHOLE tree — deleting test harnesses leaves their defaults /
# module types undefined unless we strip dependents and/or stub the defaults.
for d in \
  device/google \
  device/linaro \
  prebuilts/clang/host/darwin-x86 \
  prebuilts/gcc/darwin-x86 prebuilts/qemu-kernel \
  external/webrtc toolchain/pyston \
  art/test development/samples development/apps \
  external/chromium-webview external/deqp external/deqp-deps \
  prebuilts/asuite prebuilts/android-emulator \
  prebuilts/remoteexecution-client \
  tools/ndkports tools/vendor \
  kernel/common kernel/build kernel/tests \
  kernel/prebuilts kernel/hikey-modules \
  test platform_testing
do
  [[ -d "$d" ]] && rm -rf "$d" && echo "removed $d" || true
done
# Drop module test trees (optional disk reclaim)
if [[ -d packages/modules ]]; then
  find packages/modules -type d \( -name tests -o -name unittest -o -name unit_tests \) -prune -print 2>/dev/null \
    | while read -r t; do rm -rf "$t" && echo "removed $t"; done || true
fi
# Neutralize Android.bp that need module types from deleted trees (csuite_test, etc.)
echo "==> Stripping Android.bp that reference removed test harnesses"
# Only strip BPs that use deleted *module types* (cannot stub). Defaults gaps
# are handled by ci_soong_stubs / art/test stubs below — do not delete mixed
# production+test Android.bp files that merely reference those defaults.
find frameworks packages device cts hardware system -name Android.bp -type f 2>/dev/null \
  | while read -r bp; do
      if grep -qE '\bcsuite_test\b|\bvts_config\b|\btradefed_binary\b' "$bp" 2>/dev/null; then
        rm -f "$bp" && echo "removed bp $bp"
      fi
    done || true
# Common large test trees under frameworks that pull deleted harnesses
for d in \
  frameworks/base/libs/WindowManager/Shell/tests \
  frameworks/base/tests \
  frameworks/base/core/tests \
  frameworks/base/services/tests \
  frameworks/base/apex/jobscheduler/framework/tests \
  frameworks/opt/telephony/tests
do
  [[ -d "$d" ]] && rm -rf "$d" && echo "removed $d" || true
done

# sepolicy's fuzzer_bindings_test panics if any bound cc_fuzz is missing
# (e.g. resolv_service_fuzzer after Connectivity test prune). Not needed for LindroidUI.
if [[ -f system/sepolicy/Android.bp ]]; then
  echo "==> Disabling fuzzer_bindings_test (missing fuzzers after disk prune)"
  python3 - <<'PY'
from pathlib import Path
p = Path("system/sepolicy/Android.bp")
text = p.read_text()
out, i, n = [], 0, len(text)
while i < n:
    j = text.find("fuzzer_bindings_test", i)
    if j < 0:
        out.append(text[i:])
        break
    out.append(text[i:j])
    k = text.find("{", j)
    if k < 0:
        out.append(text[j:])
        break
    depth, m = 1, k + 1
    while m < n and depth:
        if text[m] == "{":
            depth += 1
        elif text[m] == "}":
            depth -= 1
        m += 1
    # drop the module; skip trailing newline
    if m < n and text[m] == "\n":
        m += 1
    i = m
p.write_text("".join(out))
print("removed fuzzer_bindings_test from system/sepolicy/Android.bp")
PY
fi

# Re-create minimal defaults so remaining Android.bp (esp. art/*, tools/tradefederation)
# can still be analyzed after we deleted the trees that owned these modules.
echo "==> Installing soong stubs for deleted test defaults"
mkdir -p art/test ci_soong_stubs
cat >art/test/Android.bp <<'EOF'
// CI stub: real art/test tree deleted for disk. Enough for soong to resolve
// defaults:[] references from art/*/Android.bp without building tests.
package {
    default_applicable_licenses: ["art_license"],
}

cc_defaults {
    name: "art_test_common_defaults",
    defaults: ["art_defaults"],
}

cc_defaults {
    name: "art_test_defaults",
    defaults: ["art_test_common_defaults"],
    host_supported: true,
}

art_cc_defaults {
    name: "art_standalone_test_defaults",
    defaults: ["art_test_common_defaults"],
    host_supported: false,
}

art_cc_defaults {
    name: "art_gtest_common_defaults",
    gtest: false,
}

art_cc_defaults {
    name: "art_gtest_defaults",
    defaults: [
        "art_test_defaults",
        "art_gtest_common_defaults",
    ],
    host_supported: true,
}

art_cc_defaults {
    name: "art_standalone_gtest_defaults",
    defaults: [
        "art_standalone_test_defaults",
        "art_gtest_common_defaults",
    ],
}

art_cc_defaults {
    name: "libart-gtest-defaults",
    defaults: ["art_defaults"],
    host_supported: true,
}
EOF

cat >ci_soong_stubs/Android.bp <<'EOF'
// CI stubs for defaults modules owned by trees removed for disk reclaim.
// LindroidUI does not build these test targets; stubs only satisfy soong analysis.
package {
    default_applicable_licenses: ["Android-Apache-2.0"],
}

java_defaults {
    name: "tradefed_defaults",
}

java_defaults {
    name: "tradefed_errorprone_defaults",
}

java_defaults {
    name: "framework-connectivity-test-defaults",
}

java_defaults {
    name: "adservices-extended-mockito-defaults",
}

cc_defaults {
    name: "sts_defaults",
}

cc_defaults {
    name: "deqp_and_deps_defaults",
}

cc_defaults {
    name: "cuttlefish_buildhost_only",
    host_supported: true,
    device_supported: false,
}

rust_defaults {
    name: "rdroidtest.defaults",
}
EOF

for must in kernel/configs cts prebuilts/bazel; do
  if [[ ! -d "$must" ]]; then
    echo "ERROR: required path missing after sync: $must" >&2
    exit 1
  fi
done
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

# Ensure soong can analyze before a long compile
echo "==> soong smoke (nothing)"
if ! m nothing -j"$JOBS"; then
  echo "soong still broken after cleanup — see errors above" >&2
  exit 1
fi

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
