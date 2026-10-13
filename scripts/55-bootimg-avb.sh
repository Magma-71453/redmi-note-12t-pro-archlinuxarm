#!/usr/bin/env bash
# 生成与原厂结构一致的 Test boot/vendor_boot 镜像：
#   - header v4，os_version/os_patch_level 取原厂值
#   - 尾部带 AVB hash footer，Algorithm NONE（与原厂 boot_b/vendor_boot_b 一致）
#   - 自动 pad 到 64MiB 分区大小
set -euo pipefail
source "$(dirname "$0")/00-env.sh"
A="$KERNEL_ASSET_DIR"
OUTDIR="$OUT/avb"
mkdir -p "$OUTDIR"

K="$A/Image.gz"; R="$A/initramfs-final.cpio.lz4"
[ -f "$K" ] && [ -f "$R" ] || die "kernel assets missing"

log "build boot_b header v4 with stock os_version/os_patch_level"
mkbootimg --header_version 4 \
  --kernel "$K" --ramdisk "$R" --cmdline '' \
  --os_version 16.0.0 --os_patch_level 2025-10 \
  -o "$OUTDIR/boot_b-Test-osver.img"

log "add AVB hash footer: boot_b"
cp -f "$OUTDIR/boot_b-Test-osver.img" "$OUTDIR/boot_b-Test-avb.img"
avbtool add_hash_footer --image "$OUTDIR/boot_b-Test-avb.img" \
  --partition_size 0x4000000 --partition_name boot \
  --hash_algorithm sha256 --algorithm NONE \
  --prop com.android.build.boot.os_version:16

log "add AVB hash footer: vendor_boot_b"
cp -f "$OUT/vendor_boot_b-Test.img" "$OUTDIR/vendor_boot_b-Test-avb.img"
avbtool add_hash_footer --image "$OUTDIR/vendor_boot_b-Test-avb.img" \
  --partition_size 0x4000000 --partition_name vendor_boot \
  --hash_algorithm sha256 --algorithm NONE

log "verify images"
for f in "$OUTDIR/boot_b-Test-avb.img" "$OUTDIR/vendor_boot_b-Test-avb.img"; do
  avbtool info_image --image "$f" | sed -n '1,16p'
  unpack_bootimg --boot_img "$f" --format info | sed -n '1,8p'
done
sha256sum "$OUTDIR"/*.img > "$OUTDIR/SHA256SUMS"
cat "$OUTDIR/SHA256SUMS"
log "done: $OUTDIR"
