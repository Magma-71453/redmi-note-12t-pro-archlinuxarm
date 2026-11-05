#!/usr/bin/env bash
# 回退到 Android slot A。必须显式传入 --yes。
set -euo pipefail
if [ "${1:-}" != "--yes" ]; then
  echo "usage: $0 --yes"; exit 2
fi
REPO="$(cd "$(dirname "$0")/.." && pwd)"
# 外部固件/镜像资源目录（可用同名环境变量覆盖；默认相对仓库根）。
# 目录内容约定见 README 的「外部固件与镜像资源目录」一节。
MEDIA="${PEARL_MEDIA_DIR:-$REPO/downloads/pearl-media}"
ANDROID_A_DIR="${PEARL_ANDROID_A_DIR:-$MEDIA/android-recovery-slot-a}"
RESCUE="${RESCUE:-$ANDROID_A_DIR}"

need_media() {
  [ -f "$1" ] && return 0
  echo "ERROR: 缺少外部固件/镜像资源: $1" >&2
  echo "       需先准备外部固件/镜像资源目录，见 README 的外部固件与镜像资源目录一节" >&2
  exit 1
}
for f in boot_a.img vendor_boot_a.img dtbo_a.img vbmeta_a.img boot_para.img misc-slot-a.img; do
  need_media "$RESCUE/$f"
done
fastboot devices | grep -q . || { echo "no fastboot device"; exit 1; }
fastboot flash boot_a        "$RESCUE/boot_a.img"
fastboot flash vendor_boot_a "$RESCUE/vendor_boot_a.img"
fastboot flash dtbo_a        "$RESCUE/dtbo_a.img"
fastboot flash vbmeta_a      "$RESCUE/vbmeta_a.img"
fastboot flash boot_para     "$RESCUE/boot_para.img"
echo "==> misc slot A active (must be last)"
fastboot flash misc          "$RESCUE/misc-slot-a.img"
echo "==> done. fastboot reboot"
