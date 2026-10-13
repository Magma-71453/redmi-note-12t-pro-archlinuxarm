#!/usr/bin/env bash
# 危险操作：把 Test 镜像写入真机。必须显式传入 --yes。
# 保留 Android slot A 不动；最后刷 misc 把 slot B 设为 active。
set -euo pipefail
source "$(dirname "$0")/00-env.sh"

if [ "${1:-}" != "--yes" ]; then
  cat <<'TXT'
用法: scripts/flash-test.sh --yes

会影响的分区:
  linux          <- out/Test/rootfs-...img
  boot_b         <- out/Test/boot_b-Test.img
  vendor_boot_b  <- out/Test/vendor_boot_b-Test.img
  dtbo_b         <- 原厂 dtbo_b（不使用 Linux 版 dtbo）
  vbmeta_b       <- 上一轮已验证的 disabled vbmeta
  misc           <- misc-slot-b.img (必须最后刷)

不会触碰:
  boot_a / vendor_boot_a / dtbo_a / vbmeta_a / super / userdata
TXT
  exit 2
fi

FLASH_DIR="$HOME/下载/pearl-刷机文件"
REF_BOOT="$FLASH_DIR/2-Linux启动-slotB"
REF_RESCUE="$FLASH_DIR/1-Android恢复-slotA"
for f in "$OUT/rootfs-$VERSION_TITLE.img" "$OUT/boot_b-Test.img" "$OUT/vendor_boot_b-Test.img" \
         "$REF_BOOT/misc-slot-b.img" "$REF_BOOT/vbmeta_b-disabled.img" "$REF_BOOT/dtbo_b-stock.img"; do
  [ -f "$f" ] || die "missing $f"
done
fastboot devices | grep -q . || die "no fastboot device"

echo "==> flashing rootfs (large, takes minutes)"
fastboot flash linux "$OUT/rootfs-$VERSION_TITLE.img"
echo "==> flashing boot_b / vendor_boot_b / dtbo_b / vbmeta_b"
fastboot flash boot_b "$OUT/boot_b-Test.img"
fastboot flash vendor_boot_b "$OUT/vendor_boot_b-Test.img"
fastboot flash dtbo_b "$REF_BOOT/dtbo_b-stock.img"
fastboot flash vbmeta_b "$REF_BOOT/vbmeta_b-disabled.img"
echo "==> misc: force slot B active+successful (must be last)"
fastboot flash misc "$REF_BOOT/misc-slot-b.img"
echo "==> done. reboot: fastboot reboot"

cat <<'TIP'
回 Android:
  fastboot flash misc "$HOME/下载/pearl-刷机文件/1-Android恢复-slotA/misc-slot-a.img"
  fastboot reboot
TIP
