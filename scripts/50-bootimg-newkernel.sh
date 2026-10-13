#!/usr/bin/env bash
# 用 MT6895-Mainline/linux (7.2-mt6895-xiaomi-pearl) 新编的 Image.gz
# 重新生成 out/Test/avb/boot_b-Test-avb.img 与 vendor_boot_b-Test-avb.img。
set -euo pipefail
source "$(dirname "$0")/00-env.sh"
K="$REPO/build/linux-mt6895/arch/arm64/boot/Image.gz"
R="$KERNEL_ASSET_DIR/initramfs-final.cpio.lz4"
D="$KERNEL_ASSET_DIR/pearl.dtb"
[ -f "$K" ] || die "new kernel missing: $K"
[ -f "$R" ] || die "initramfs missing: $R"
[ -f "$D" ] || die "dtb missing: $D"
OUTDIR="$OUT/avb"; mkdir -p "$OUTDIR" "$OUT"
: > "$BUILD/empty-bootconfig"

log "build boot_b-Test.img (new pearl kernel)"
mkbootimg --header_version 4 \
  --kernel "$K" --ramdisk "$R" --cmdline '' \
  --os_version 16.0.0 --os_patch_level 2025-10 \
  -o "$OUT/boot_b-Test.img"

log "build vendor_boot_b-Test.img (new pearl kernel + existing pearl.dtb)"
mkbootimg --header_version 4 --pagesize 0x1000 --base 0x00000000 \
  --kernel_offset 0x40000000 --ramdisk_offset 0x66f00000 \
  --tags_offset 0x47c80000 --dtb_offset 0x0000000047c80000 \
  --vendor_cmdline 'bootopt=64S3,32N2,64N2 androidboot.selinux=permissive' \
  --board '' --dtb "$D" --vendor_bootconfig "$BUILD/empty-bootconfig" \
  --ramdisk_type 1 --ramdisk_name '' --vendor_ramdisk_fragment "$R" \
  --vendor_boot "$OUT/vendor_boot_b-Test.img"

log "add AVB hash footer: boot_b"
cp -f "$OUT/boot_b-Test.img" "$OUTDIR/boot_b-Test-avb.img"
avbtool add_hash_footer --image "$OUTDIR/boot_b-Test-avb.img" \
  --partition_size 0x4000000 --partition_name boot \
  --hash_algorithm sha256 --algorithm NONE \
  --salt 00112233445566778899aabbccddeeff \
  --prop com.android.build.boot.os_version:16

log "add AVB hash footer: vendor_boot_b"
cp -f "$OUT/vendor_boot_b-Test.img" "$OUTDIR/vendor_boot_b-Test-avb.img"
avbtool add_hash_footer --image "$OUTDIR/vendor_boot_b-Test-avb.img" \
  --partition_size 0x4000000 --partition_name vendor_boot \
  --hash_algorithm sha256 --algorithm NONE \
  --salt ffeeddccbbaa99887766554433221100

log "verify"
for f in "$OUTDIR/boot_b-Test-avb.img" "$OUTDIR/vendor_boot_b-Test-avb.img"; do
  avbtool info_image --image "$f" | sed -n '1,12p'
  unpack_bootimg --boot_img "$f" --format info | sed -n '1,8p'
done
sha256sum "$OUTDIR/boot_b-Test-avb.img" "$OUTDIR/vendor_boot_b-Test-avb.img" > "$OUTDIR/SHA256SUMS"
cat "$OUTDIR/SHA256SUMS"
