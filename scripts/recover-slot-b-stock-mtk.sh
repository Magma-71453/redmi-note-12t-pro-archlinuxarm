#!/usr/bin/env bash
# 可选项：当只回 misc 还不够时，把原厂 slot B 的 boot/vendor_boot/dtbo/vbmeta 写回。
# 需要设备处于 preloader 模式（0e8d:2000）。
set -uo pipefail
REPO="$(cd "$(dirname "$0")/.." && pwd)"
MTK="${MTK:-$REPO/build/mtk-venv/bin/mtk}"
PRELOADER="${PRELOADER:-$HOME/下载/pearl-MTK验证文件/1-官方ROM提取/preloader_pearl.bin}"
LOADER="${LOADER:-$HOME/下载/pearl-MTK验证文件/1-官方ROM提取/DA_BR.bin}"
SRC="${SRC:-$HOME/下载/pearl-刷机文件/3-原厂分区备份}"
for f in "$MTK" "$PRELOADER" "$LOADER"; do [ -f "$f" ] || { echo "missing $f"; exit 1; }; done
lsusb | grep -q '0e8d:2000' || { echo "device is not in 0e8d:2000 preloader mode"; exit 2; }
set -e
for p in boot_b vendor_boot_b dtbo_b vbmeta_b boot_para; do
  img="$SRC/$p.img"
  [ -f "$img" ] || { echo "skip missing $img"; continue; }
  echo "==> write $p from $img"
  "$MTK" w "$p" "$img" --preloader "$PRELOADER" --loader "$LOADER"
done
echo "slot B stock restore done"
