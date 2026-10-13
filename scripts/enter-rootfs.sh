#!/usr/bin/env bash
# 用法: scripts/enter-rootfs.sh <rootfs-dir> [命令...]
# 默认进入交互 bash。自动安装 qemu-aarch64-static 到 rootfs。
set -euo pipefail
repo="$(cd "$(dirname "$0")/.." && pwd)"
root="$(realpath "${1:?usage: $0 <rootfs> [cmd...]}")"
shift || true
[ -d "$root/usr" ] || { echo "rootfs not found: $root" >&2; exit 1; }
install -d -m755 "$root/usr/bin"
install -m755 /usr/bin/qemu-aarch64-static "$root/usr/bin/qemu-aarch64-static"
exec unshare -r -m --fork --kill-child "$repo/scripts/_enter-rootfs-inner.sh" "$root" "$@"
