#!/usr/bin/env bash
# Entrypoint used by CI or a fat Docker/self-hosted runner.
set -euo pipefail
PORT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
chmod +x "$PORT_ROOT"/scripts/*.sh "$PORT_ROOT"/kernel/*.sh

export ANDROID_BUILD_TOP="${ANDROID_BUILD_TOP:-$PORT_ROOT/android}"
export ARTIFACT_DIR="${ARTIFACT_DIR:-$PORT_ROOT/artifacts}"

mode="${1:-all}"
case "$mode" in
  kernel)
    "$PORT_ROOT/scripts/ci-kernel.sh"
    ;;
  sync)
    "$PORT_ROOT/scripts/ci-sync.sh"
    ;;
  prepare)
    "$PORT_ROOT/scripts/ci-prepare.sh"
    ;;
  build)
    "$PORT_ROOT/scripts/ci-build.sh"
    ;;
  all)
    "$PORT_ROOT/scripts/ci-sync.sh"
    "$PORT_ROOT/scripts/ci-prepare.sh"
    "$PORT_ROOT/scripts/ci-build.sh"
    ;;
  *)
    echo "usage: $0 [kernel|sync|prepare|build|all]" >&2
    exit 1
    ;;
esac
