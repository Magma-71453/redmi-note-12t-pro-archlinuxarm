#!/usr/bin/env bash
# 可选项：当只回 misc 还不够时，把原厂 slot B 的 boot/vendor_boot/dtbo/vbmeta 写回。
# 需要设备处于 preloader 模式（0e8d:2000）。
set -uo pipefail
REPO="$(cd "$(dirname "$0")/.." && pwd)"
if [ -f "$REPO/build/mtk-venv" ]; then
  python3 "$REPO/scripts/patch-mtkclient-v6.py" >/dev/null 2>&1 || true
fi
REPO="$(cd "$(dirname "$0")/.." && pwd)"
MTK="${MTK:-$REPO/build/mtk-venv/bin/mtk}"
# 外部固件/镜像资源目录（可用同名环境变量覆盖；默认相对仓库根）。
# 目录内容约定见 README 的「外部固件与镜像资源目录」一节。
MEDIA="${PEARL_MEDIA_DIR:-$REPO/downloads/pearl-media}"
ROM_DIR="${PEARL_ROM_DIR:-$MEDIA/rom}"
BACKUP_DIR="${PEARL_BACKUP_DIR:-$MEDIA/backup}"
ANDROID_A_DIR="${PEARL_ANDROID_A_DIR:-$MEDIA/android-recovery-slot-a}"
PRELOADER="${PRELOADER:-$ROM_DIR/images/preloader_pearl.bin}"
LOADER="${LOADER:-$ROM_DIR/images/download_agent/DA_BR.bin}"
SRC="${SRC:-$BACKUP_DIR}"

need_media() {
  [ -f "$1" ] && return 0
  echo "ERROR: 缺少外部固件/镜像资源: $1" >&2
  echo "       需先准备外部固件/镜像资源目录，见 README 的外部固件与镜像资源目录一节" >&2
  exit 1
}
[ -f "$MTK" ] || { echo "ERROR: 缺少 mtkclient: $MTK" >&2; exit 1; }
need_media "$PRELOADER"
need_media "$LOADER"
if ! lsusb | grep -q '0e8d:2000'; then
  if [ "${1:-}" = "--wait" ]; then
    echo "waiting for preloader mode 0e8d:2000 ..."
    while ! lsusb | grep -q '0e8d:2000'; do sleep 1; done
  else
    echo "device is not in 0e8d:2000 preloader mode"; exit 2
  fi
fi
set -e
for p in boot_b vendor_boot_b dtbo_b vbmeta_b boot_para; do
  case "$p" in
    boot_para) img="$ANDROID_A_DIR/$p.img" ;;
    *)         img="$SRC/$p.img" ;;
  esac
  if [ ! -f "$img" ]; then
    echo "SKIP 缺少镜像: $img"
    echo "     需先准备外部固件/镜像资源目录，见 README 的外部固件与镜像资源目录一节"
    continue
  fi
  echo "==> write $p from $img"
  "$MTK" w "$p" "$img" --preloader "$PRELOADER" --loader "$LOADER"
done
echo "slot B stock restore done"
