#!/usr/bin/env bash
# 从真机现有 linux 分区恢复 7.2.9+ 模块 tar（需要 adb + Magisk/root）。
# 这是给“原始模块 tar 丢失时”用的恢复脚本；当前仓库的 out 镜像已包含模块。
set -euo pipefail
source "$(dirname "$0")/00-env.sh"
adb shell "su -c 'command -v su >/dev/null && echo root_ok'" | grep -q root_ok || die "adb root/su unavailable"
mkdir -p "$BUILD/kernel-modules"
log "mount old rootfs read-only and tar modules"
adb shell "su -c 'umount /mnt/linuxro 2>/dev/null; mkdir -p /mnt/linuxro; mount -t ext4 -o ro /dev/block/sdc88 /mnt/linuxro; cd /mnt/linuxro/usr/lib; tar -cf /data/local/tmp/pearl-modules-7.2.9.tar modules/7.2.9+; sync; cd /; umount /mnt/linuxro; ls -l /data/local/tmp/pearl-modules-7.2.9.tar'"
adb pull /data/local/tmp/pearl-modules-7.2.9.tar "$BUILD/kernel-modules/pearl-modules-7.2.9.tar"
adb shell "su -c 'rm -f /data/local/tmp/pearl-modules-7.2.9.tar'"
sha256sum "$BUILD/kernel-modules/pearl-modules-7.2.9.tar" | tee "$LOGS/modules.tar.sha256"
mkdir -p "$BUILD/kernel-modules/tree"
tar -xf "$BUILD/kernel-modules/pearl-modules-7.2.9.tar" -C "$BUILD/kernel-modules/tree"
log "modules ready under $BUILD/kernel-modules/tree/modules/7.2.9+"
