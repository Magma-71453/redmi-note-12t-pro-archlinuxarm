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

# 外部固件/镜像资源目录：可用同名环境变量覆盖，默认全部相对仓库根。
# 目录内容约定见 README 的「外部固件与镜像资源目录」一节。
PEARL_MEDIA_DIR="${PEARL_MEDIA_DIR:-$DOWNLOADS/pearl-media}"
PEARL_ROM_DIR="${PEARL_ROM_DIR:-$PEARL_MEDIA_DIR/rom}"
PEARL_BACKUP_DIR="${PEARL_BACKUP_DIR:-$PEARL_MEDIA_DIR/backup}"
PEARL_LINUX_MEDIA_DIR="${PEARL_LINUX_MEDIA_DIR:-$PEARL_MEDIA_DIR/linux-slot-b}"
PEARL_ANDROID_A_DIR="${PEARL_ANDROID_A_DIR:-$PEARL_MEDIA_DIR/android-recovery-slot-a}"
PEARL_FASTBOOT_DIR="${PEARL_FASTBOOT_DIR:-$PEARL_MEDIA_DIR/fastboot-lineage}"
export PEARL_MEDIA_DIR PEARL_ROM_DIR PEARL_BACKUP_DIR \
       PEARL_LINUX_MEDIA_DIR PEARL_ANDROID_A_DIR PEARL_FASTBOOT_DIR

mkdir -p "$BUILD" "$OUT" "$ART" "$DOWNLOADS" "$LOGS"
# 外部资源目录缺失不致命：其中的文件由使用者自行提供。
mkdir -p "$PEARL_ROM_DIR" "$PEARL_BACKUP_DIR" "$PEARL_LINUX_MEDIA_DIR" \
         "$PEARL_ANDROID_A_DIR" "$PEARL_FASTBOOT_DIR" 2>/dev/null || true

KERNEL_ASSET_DIR="$ART/${KERNEL_ASSET_DIR_NAME:-kernel-${KERNEL_SERIES}.9+}"

log() { printf '[%s] %s\n' "$(date -u +%H:%M:%S)" "$*"; }
die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }
