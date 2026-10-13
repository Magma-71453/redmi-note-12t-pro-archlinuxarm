#!/usr/bin/env bash
# 统一路径与环境变量。所有脚本 source 本文件。
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG="$REPO/config/build.conf"
# shellcheck source=/dev/null
source "$CONFIG"

BUILD="$REPO/build"
OUT="$REPO/out/$VERSION_TITLE"
ART="$REPO/artifacts"
DOWNLOADS="$REPO/downloads"
LOGS="$REPO/logs"
ROOTFS_DIR="$BUILD/rootfs-$VERSION_TITLE"

mkdir -p "$BUILD" "$OUT" "$ART" "$DOWNLOADS" "$LOGS"

KERNEL_ASSET_DIR="$ART/${KERNEL_ASSET_DIR_NAME:-kernel-${KERNEL_SERIES}.9+}"

log() { printf '[%s] %s\n' "$(date -u +%H:%M:%S)" "$*"; }
die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }
