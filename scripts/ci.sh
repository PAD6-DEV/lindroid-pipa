#!/usr/bin/env bash
set -euo pipefail
PORT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
chmod +x "$PORT_ROOT"/scripts/*.sh "$PORT_ROOT"/kernel/*.sh 2>/dev/null || true

mode="${1:-all}"
case "$mode" in
  kernel)  "$PORT_ROOT/scripts/ci-kernel.sh" ;;
  magisk)  "$PORT_ROOT/scripts/ci-magisk.sh" ;;
  all)
    "$PORT_ROOT/scripts/ci-kernel.sh"
    "$PORT_ROOT/scripts/ci-magisk.sh"
    ;;
  *)
    echo "usage: $0 [kernel|magisk|all]" >&2
    exit 1
    ;;
esac
