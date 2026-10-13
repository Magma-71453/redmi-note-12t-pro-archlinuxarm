#!/usr/bin/env bash
# 在用户命名空间 + 挂载命名空间内 chroot 到 Arch Linux ARM rootfs。
# 由 enter-rootfs.sh 调用；不要直接从宿主机运行。
set -euo pipefail
root="${1:?rootfs path required}"
shift
root="$(realpath "$root")"
[ -d "$root/usr" ] || { echo "not a rootfs: $root" >&2; exit 1; }

if [ "$#" -eq 0 ]; then
  set -- /bin/bash -l
fi

# 挂载点
mkdir -p "$root/proc" "$root/sys" "$root/dev" "$root/dev/pts" "$root/run" "$root/tmp"

# /proc：优先 proc，失败则 bind host /proc
mount -t proc proc "$root/proc" 2>/dev/null || mount --rbind /proc "$root/proc" 2>/dev/null || true
# /sys、/dev：允许失败，pacman 核心功能不依赖它们
mount --rbind /sys "$root/sys" 2>/dev/null || true
if ! mount --rbind /dev "$root/dev" 2>/dev/null; then
  for d in null zero full random urandom tty; do
    if [ -e "/dev/$d" ] && [ ! -e "$root/dev/$d" ]; then
      touch "$root/dev/$d"
      mount --bind "/dev/$d" "$root/dev/$d" 2>/dev/null || true
    fi
  done
fi

# DNS 配置（宿主机若为 systemd-resolved，跟随符号链接复制）
rm -f "$root/etc/resolv.conf"
cp -fL /etc/resolv.conf "$root/etc/resolv.conf" 2>/dev/null || true

# binfmt_misc：注册 qemu-aarch64，让 chroot 内的 aarch64 ELF 可直接执行
mkdir -p /tmp/arm-binfmt
mount -t binfmt_misc binfmt_misc /tmp/arm-binfmt
printf '%s\n' ':qemu-aarch64:M::\x7fELF\x02\x01\x01\x00\x00\x00\x00\x00\x00\x00\x00\x00\x02\x00\xb7\x00:\xff\xff\xff\xff\xff\xff\xff\x00\xff\xff\xff\xff\xff\xff\xff\xff\xfe\xff\xff\xff:/usr/bin/qemu-aarch64-static:C' > /tmp/arm-binfmt/register

chroot "$root" /usr/bin/env -i \
  HOME=/root PATH=/usr/local/sbin:/usr/local/bin:/usr/bin:/usr/sbin:/bin:/sbin \
  TERM=xterm-256color LANG=C.UTF-8 SOURCE_DATE_EPOCH="${SOURCE_DATE_EPOCH:-}" \
  "$@"
