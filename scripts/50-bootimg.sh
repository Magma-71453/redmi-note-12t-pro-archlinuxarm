#!/usr/bin/env bash
# 从仓库内固化的 7.2.9+ 内核资产重新打包 boot_b / vendor_boot_b。
# 结果与上一轮已验证的 boot-pearl-linux-final-v4.img / vendor_boot-pearl-linux-final.img
# 字节级一致（脚本会校验）。
set -euo pipefail
source "$(dirname "$0")/00-env.sh"

A="$KERNEL_ASSET_DIR"
K="$A/Image.gz"
R="$A/initramfs-final.cpio.lz4"
D="$A/pearl.dtb"
[ -f "$K" ] && [ -f "$R" ] && [ -f "$D" ] || die "kernel assets missing in $A"

mkdir -p "$OUT"
: > "$BUILD/empty-bootconfig"

log "build boot_b-Test.img (header v4)"
mkbootimg --header_version 4 \
  --kernel "$K" --ramdisk "$R" --cmdline '' \
  -o "$OUT/boot_b-Test.img"

log "build vendor_boot_b-Test.img (header v4, ramdisk fragment)"
mkbootimg --header_version 4 --pagesize 0x1000 --base 0x00000000 \
  --kernel_offset 0x40000000 --ramdisk_offset 0x66f00000 \
  --tags_offset 0x47c80000 --dtb_offset 0x0000000047c80000 \
  --vendor_cmdline 'bootopt=64S3,32N2,64N2 androidboot.selinux=permissive' \
  --board '' --dtb "$D" --vendor_bootconfig "$BUILD/empty-bootconfig" \
  --ramdisk_type 1 --ramdisk_name '' --vendor_ramdisk_fragment "$R" \
  --vendor_boot "$OUT/vendor_boot_b-Test.img"

log "validate output"
unpack_bootimg --boot_img "$OUT/boot_b-Test.img" --format info > "$OUT/boot_b-Test.info.txt"
unpack_bootimg --boot_img "$OUT/vendor_boot_b-Test.img" --format info > "$OUT/vendor_boot_b-Test.info.txt"

ref_boot="$HOME/下载/pearl-刷机文件/2-Linux启动-slotB/boot-pearl-linux-final-v4.img"
ref_vendor="$HOME/下载/pearl-刷机文件/2-Linux启动-slotB/vendor_boot-pearl-linux-final.img"
if [ -f "$ref_boot" ]; then
  cmp -s "$OUT/boot_b-Test.img" "$ref_boot" && log "boot_b-Test == known-good final-v4" || die "boot_b-Test differs from known-good reference"
fi
if [ -f "$ref_vendor" ]; then
  cmp -s "$OUT/vendor_boot_b-Test.img" "$ref_vendor" && log "vendor_boot_b-Test == known-good final" || die "vendor_boot_b-Test differs from known-good reference"
fi

sha256sum "$OUT/boot_b-Test.img" "$OUT/vendor_boot_b-Test.img" > "$OUT/boot-SHA256SUMS"
cat "$OUT/boot-SHA256SUMS"
