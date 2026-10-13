#!/usr/bin/env bash
# 生成 Test ext4 rootfs 镜像。
# 依赖：30-rootfs 已完成，rootfs 目录里已配置好系统；内核模块已经复制进去。
set -euo pipefail
source "$(dirname "$0")/00-env.sh"

[ -x "$ROOTFS_DIR/usr/bin/pacman" ] || die "rootfs not built: $ROOTFS_DIR"
[ -d "$ROOTFS_DIR/etc" ] || die "rootfs incomplete"
[ -f "$ROOTFS_DIR/etc/mt6895-rootfs" ] || die "missing /etc/mt6895-rootfs marker (initramfs 找不到 rootfs)"
[ -d "$ROOTFS_DIR/usr/lib/modules/${KERNEL_VERSION}${KERNEL_RELEASE_SUFFIX}" ] || \
  die "missing kernel modules ${KERNEL_VERSION}${KERNEL_RELEASE_SUFFIX}"

log "clean build-only files from rootfs"
rm -f "$ROOTFS_DIR/usr/bin/qemu-aarch64-static"
rm -f "$ROOTFS_DIR/tmp/rootfs-install-cmd.sh" "$ROOTFS_DIR/tmp/rootfs-packages.sh" "$ROOTFS_DIR/tmp/rootfs-configure.sh"
rm -f "$ROOTFS_DIR/tmp/installed-test-build.txt" "$ROOTFS_DIR/tmp/installed-packages.txt"
rm -rf "$ROOTFS_DIR/var/cache/pacman/pkg"/*
rm -f "$ROOTFS_DIR/etc/pacman.conf.alarm-orig"
find "$ROOTFS_DIR/run" -mindepth 1 -delete 2>/dev/null || true
find "$ROOTFS_DIR/tmp" -mindepth 1 -delete 2>/dev/null || true
# 启动后由 systemd-resolved 接管 /etc/resolv.conf
ln -sfn /run/systemd/resolve/stub-resolv.conf "$ROOTFS_DIR/etc/resolv.conf"

img="$OUT/$ROOTFS_IMAGE_NAME"
log "create sparse image $img size=$ROOTFS_IMAGE_SIZE"
rm -f "$img" "$img.zst"
truncate -s "$ROOTFS_IMAGE_SIZE" "$img"
log "mkfs.ext4 -L $LINUX_FS_LABEL -d rootfs"
# 在 user namespace 内运行：rootfs 目录在宿主机属于 magma，在 ns 内显示 uid/gid=0，
# 这样 mkfs.ext4 写入的 inode 属主才是真正的 0。
unshare -r -m --fork mkfs.ext4 -q -F -L "$LINUX_FS_LABEL" -m 0 -d "$ROOTFS_DIR" "$img"
log "verify inode ownership and label"
debugfs -R 'stat /etc/passwd' "$img" 2>/dev/null | grep -q 'User: *0' || die "rootfs /etc/passwd is not uid 0"
dumpe2fs -h "$img" 2>/dev/null | grep -q "Filesystem volume name: *$LINUX_FS_LABEL" || die "ext4 label mismatch"
e2fsck -f -n "$img" >/dev/null 2>&1 || log "WARN: e2fsck reported issues (see 60-finalize logs)"

log "compress rootfs image -> $img.zst"
zstd -T0 -19 -f "$img" -o "$img.zst"

log "images ready:"
ls -lh "$img" "$img.zst"
( cd "$REPO" && sha256sum "${img#"$REPO"/}" "${img.zst#"$REPO"/}" > "${OUT#"$REPO"/}/rootfs-SHA256SUMS" )
cat "$OUT/rootfs-SHA256SUMS"
