#!/usr/bin/env bash
# 回退到 Android slot A。必须显式传入 --yes。
set -euo pipefail
if [ "${1:-}" != "--yes" ]; then
  echo "usage: $0 --yes"; exit 2
fi
RESCUE="$HOME/下载/pearl-刷机文件/1-Android恢复-slotA"
[ -f "$RESCUE/misc-slot-a.img" ] || { echo "missing $RESCUE/misc-slot-a.img"; exit 1; }
fastboot devices | grep -q . || { echo "no fastboot device"; exit 1; }
fastboot flash boot_a        "$RESCUE/boot_a.img"
fastboot flash vendor_boot_a "$RESCUE/vendor_boot_a.img"
fastboot flash dtbo_a        "$RESCUE/dtbo_a.img"
fastboot flash vbmeta_a      "$RESCUE/vbmeta_a.img"
fastboot flash boot_para     "$RESCUE/boot_para.img"
echo "==> misc slot A active (must be last)"
fastboot flash misc          "$RESCUE/misc-slot-a.img"
echo "==> done. fastboot reboot"
