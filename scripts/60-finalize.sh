#!/usr/bin/env bash
# 汇总 Test 产物：manifest、包清单、SHA256SUMS、git 提交提示。
set -euo pipefail
source "$(dirname "$0")/00-env.sh"

[ -f "$OUT/rootfs-SHA256SUMS" ] || die "run 40-image.sh first"
[ -f "$OUT/boot-SHA256SUMS" ] || die "run 50-bootimg.sh first"

log "collect rootfs package manifest"
if [ -f "$ROOTFS_DIR/var/lib/pacman/local/ALPM_DB_VERSION" ] || [ -d "$ROOTFS_DIR/var/lib/pacman/local" ]; then
  ls "$ROOTFS_DIR/var/lib/pacman/local" | sed '/^ALPM_DB_VERSION$/d' | sort > "$OUT/packages-Test.list"
fi
"$REPO/scripts/enter-rootfs.sh" "$ROOTFS_DIR" /bin/sh -c 'pacman -Q' > "$OUT/packages-pacmanQ-Test.txt" 2>/dev/null || true

log "write manifest"
{
  echo "# pearl-linux Test manifest"
  echo "version_title=$VERSION_TITLE"
  echo "build_date_utc=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "device=$TARGET_DEVICE"
  echo "model=$TARGET_MODEL"
  echo "soc=$TARGET_SOC"
  echo "arch=$TARGET_ARCH"
  echo "kernel_release=${KERNEL_ACTUAL_RELEASE:-${KERNEL_VERSION}${KERNEL_RELEASE_SUFFIX}}"
  echo "kernel_asset=$KERNEL_ASSET_DIR"
  echo "rootfs_image=$ROOTFS_IMAGE_NAME"
  echo "rootfs_image_size=$ROOTFS_IMAGE_SIZE"
  echo "boot_image=boot_b-Test.img"
  echo "vendor_boot_image=vendor_boot_b-Test.img"
  echo "linux_partition=$PART_LINUX"
  echo "boot_b_partition=$PART_BOOT_B"
  echo "userdata_partition=$PART_USERDATA (READ-ONLY for Linux)"
  echo "desktop=labwc"
  echo "terminal=kitty"
  echo "editor=neovim"
  echo "containers=docker"
} > "$OUT/MANIFEST.txt"

cat "$OUT/MANIFEST.txt"
cat "$OUT"/*SHA256SUMS > "$OUT/SHA256SUMS-ALL"
sha256sum "$OUT/MANIFEST.txt" >> "$OUT/SHA256SUMS-ALL"

log "done. outputs in $OUT"
