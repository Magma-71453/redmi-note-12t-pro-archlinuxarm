#!/usr/bin/env bash
# 构建 Test rootfs 目录（可复现步骤的脚本化版本）。
# 本仓库最终 Test 镜像是按同样步骤实际执行得到的；脚本保留了在线源和
# user-namespace/qemu-user 细节，方便后续重跑。
set -euo pipefail
source "$(dirname "$0")/00-env.sh"
"$REPO/scripts/20-kernel-assets.sh"

# 1. Arch Linux ARM tarball
[ -s "$DOWNLOADS/$ALARM_TARBALL" ] || die "missing $DOWNLOADS/$ALARM_TARBALL"
gzip -t "$DOWNLOADS/$ALARM_TARBALL" || die "bad gzip: $ALARM_TARBALL"

# 2. 解压 rootfs（以普通用户解压；进入 user namespace 后显示为 uid 0）
if [ ! -x "$ROOTFS_DIR/usr/bin/pacman" ]; then
  log "extract $ALARM_TARBALL -> $ROOTFS_DIR"
  rm -rf "$ROOTFS_DIR"
  mkdir -p "$ROOTFS_DIR"
  tar -xpf "$DOWNLOADS/$ALARM_TARBALL" -C "$ROOTFS_DIR" > "$LOGS/alarm-extract.log" 2>&1 || true
  # ALARM tarball 里 cadir 是 0555，普通用户整体解压时其中条目会失败，单独补一次
  if [ -d "$ROOTFS_DIR/etc/ca-certificates/extracted/cadir" ]; then
    chmod u+w "$ROOTFS_DIR/etc/ca-certificates/extracted/cadir"
    tar -xpf "$DOWNLOADS/$ALARM_TARBALL" -C "$ROOTFS_DIR" \
      ./etc/ca-certificates/extracted/cadir >> "$LOGS/alarm-extract.log" 2>&1 || true
  fi
fi
[ -x "$ROOTFS_DIR/usr/bin/pacman" ] || die "pacman not found in rootfs"

# 3. pacman 配置：构建时用 Never 以避开 user namespace 的 gpg chown 问题，
#    安装完成后由 configure/keyring 步骤恢复 Required DatabaseOptional。
cp -n "$ROOTFS_DIR/etc/pacman.conf" "$ROOTFS_DIR/etc/pacman.conf.alarm-orig" 2>/dev/null || true
sed -i 's/^SigLevel[[:space:]]*=.*/SigLevel    = Never/' "$ROOTFS_DIR/etc/pacman.conf"
sed -i 's/^DownloadUser[[:space:]]*=.*/#DownloadUser = alpm/' "$ROOTFS_DIR/etc/pacman.conf"
sed -i 's/^CheckSpace/#CheckSpace/' "$ROOTFS_DIR/etc/pacman.conf"
cat > "$ROOTFS_DIR/etc/pacman.d/mirrorlist" <<'MIRROR'
Server = https://archlinuxarm.org/$arch/$repo
MIRROR
rm -f "$ROOTFS_DIR/etc/resolv.conf"
cat > "$ROOTFS_DIR/etc/resolv.conf" <<'DNS'
nameserver 1.1.1.1
DNS

# 4. 包安装
install -m755 "$REPO/scripts/rootfs-packages.sh" "$ROOTFS_DIR/tmp/rootfs-packages.sh"
"$REPO/scripts/enter-rootfs.sh" "$ROOTFS_DIR" /bin/bash -l /tmp/rootfs-packages.sh

# 5. 复制精确匹配的 7.2.9+ 模块（从新生成的 tar 或已解压目录）
if [ ! -d "$BUILD/kernel-modules/tree/modules/7.2.9+" ]; then
  if [ -s "$BUILD/kernel-modules/pearl-modules-7.2.9.tar" ]; then
    mkdir -p "$BUILD/kernel-modules/tree"
    tar -xf "$BUILD/kernel-modules/pearl-modules-7.2.9.tar" -C "$BUILD/kernel-modules/tree"
  else
    die "missing kernel modules; see docs/TEST-BUILD.md 的模块恢复步骤"
  fi
fi
rm -rf "$ROOTFS_DIR/usr/lib/modules"
mkdir -p "$ROOTFS_DIR/usr/lib/modules"
cp -a "$BUILD/kernel-modules/tree/modules/7.2.9+" "$ROOTFS_DIR/usr/lib/modules/"
"$REPO/scripts/enter-rootfs.sh" "$ROOTFS_DIR" depmod -a 7.2.9+

# 6. 系统配置
install -m755 "$REPO/scripts/rootfs-configure.sh" "$ROOTFS_DIR/tmp/rootfs-configure.sh"
"$REPO/scripts/enter-rootfs.sh" "$ROOTFS_DIR" /bin/bash -l /tmp/rootfs-configure.sh

# 7. 初始化并填充 pacman keyring，然后恢复安全的签名级别
"$REPO/scripts/enter-rootfs.sh" "$ROOTFS_DIR" /bin/bash -lc 'pacman-key --init && pacman-key --populate archlinuxarm'
sed -i 's/^SigLevel[[:space:]]*=.*/SigLevel = Required DatabaseOptional/' "$ROOTFS_DIR/etc/pacman.conf"
sed -i 's/^#CheckSpace/CheckSpace/' "$ROOTFS_DIR/etc/pacman.conf"
sed -i 's/^#DownloadUser = alpm/DownloadUser = alpm/' "$ROOTFS_DIR/etc/pacman.conf"
log "rootfs tree ready: $ROOTFS_DIR"
