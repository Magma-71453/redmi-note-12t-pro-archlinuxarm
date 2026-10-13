#!/usr/bin/env bash
# 只读验证 Test 产物；不会访问/修改真机分区，也不会执行 fastboot。
set -uo pipefail
source "$(dirname "$0")/00-env.sh"

FAIL=0
ok()  { printf 'OK   %s\n' "$*"; }
bad() { printf 'FAIL %s\n' "$*"; FAIL=1; }
need(){ [ -e "$1" ] && ok "$1" || bad "missing: $1"; }

echo "== git =="
git -C "$REPO" rev-parse --short HEAD || bad "git HEAD"
git -C "$REPO" rev-parse -q --verify Test >/dev/null && ok "git tag Test" || bad "git tag Test"
[ -z "$(git -C "$REPO" status --porcelain)" ] && ok "git worktree clean" || bad "git worktree dirty"

echo "== artifact files =="
for f in \
  "$OUT/$ROOTFS_IMAGE_NAME" \
  "$OUT/$ROOTFS_IMAGE_NAME.zst" \
  "$OUT/boot_b-Test.img" \
  "$OUT/vendor_boot_b-Test.img" \
  "$ART/kernel-7.2.9+/Image.gz" \
  "$ART/kernel-7.2.9+/initramfs-final.cpio.lz4" \
  "$ART/kernel-7.2.9+/pearl.dtb" \
  "$ART/kernel-7.2.9+/config" \
  "$ART/Test/MANIFEST.txt" \
  "$ART/Test/packages-pacmanQ-Test.txt"; do
  need "$f"
done

echo "== sha256 =="
( cd "$REPO" && sha256sum -c "$ART/Test/rootfs-image-SHA256SUMS" ) || bad "rootfs checksum"
( cd "$REPO" && sha256sum -c "$ART/Test/boot-SHA256SUMS" ) || bad "boot checksum"

echo "== ext4 image =="
dumpe2fs -h "$OUT/$ROOTFS_IMAGE_NAME" 2>/dev/null | grep -q "Filesystem volume name: *$LINUX_FS_LABEL" \
  && ok "label=$LINUX_FS_LABEL" || bad "ext4 label"
dumpe2fs -h "$OUT/$ROOTFS_IMAGE_NAME" 2>/dev/null | grep -q "Filesystem state: *clean" \
  && ok "filesystem clean" || bad "filesystem not clean"
e2fsck -f -n "$OUT/$ROOTFS_IMAGE_NAME" >/dev/null 2>&1 && ok "e2fsck clean" || bad "e2fsck"

echo "== image key paths (debugfs) =="
for p in \
  /etc/mt6895-rootfs /etc/os-release /etc/fstab /etc/pacman.conf \
  /etc/pacman.d/gnupg/pubring.gpg \
  /usr/lib/modules/7.2.9+/modules.dep \
  /usr/bin/docker /usr/bin/dockerd /usr/bin/containerd \
  /usr/bin/labwc /usr/bin/kitty /usr/bin/nvim \
  /home/alarm/.config/labwc/autostart \
  /home/alarm/.config/kitty/kitty.conf \
  /home/alarm/.config/nvim/init.lua \
  /etc/systemd/system/pearl-firstboot.service \
  /etc/systemd/system/getty@tty1.service.d/autologin.conf \
  /etc/systemd/system/multi-user.target.wants/docker.service \
  /etc/systemd/system/multi-user.target.wants/sshd.service \
  /etc/systemd/system/multi-user.target.wants/NetworkManager.service \
  /etc/systemd/system/multi-user.target.wants/systemd-resolved.service; do
  debugfs -R "stat $p" "$OUT/$ROOTFS_IMAGE_NAME" >/dev/null 2>&1 \
    && ok "image $p" || bad "image missing: $p"
done

echo "== package list =="
for p in docker docker-compose labwc kitty neovim networkmanager openssh systemd zram-generator earlyoom; do
  grep -q "^$p " "$ART/Test/packages-pacmanQ-Test.txt" \
    && ok "package $p" || bad "package missing: $p"
done

echo "== runtime versions / unit syntax (chroot, qemu-user) =="
"$REPO/scripts/enter-rootfs.sh" "$ROOTFS_DIR" /bin/bash -lc '
  set -e
  uname -m
  docker --version
  docker compose version 2>/dev/null || true
  dockerd --version
  labwc --version
  kitty --version
  nvim --version | head -1
  systemd-analyze verify \
    /etc/systemd/system/pearl-firstboot.service \
    /etc/systemd/system/getty@tty1.service.d/autologin.conf \
    /etc/systemd/system/multi-user.target.wants/docker.service >/tmp/verify-systemd.log 2>&1 || true
  echo systemd-verify-log-lines=$(wc -l </tmp/verify-systemd.log)
' || bad "chroot verification"

echo "== boot images =="
unpack_bootimg --boot_img "$OUT/boot_b-Test.img" --format info | sed 's/^/  /'
unpack_bootimg --boot_img "$OUT/vendor_boot_b-Test.img" --format info | sed 's/^/  /'

echo
if [ "$FAIL" -eq 0 ]; then
  echo "VERIFY_RESULT=PASS"
  exit 0
else
  echo "VERIFY_RESULT=FAIL"
  exit 1
fi
