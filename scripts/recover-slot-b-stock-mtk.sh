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
PRELOADER="${PRELOADER:-$PEARL_ROM_DIR/images/preloader_pearl.bin}"
LOADER="${LOADER:-$PEARL_ROM_DIR/images/DA_BR.bin}"
SRC="${SRC:-$PEARL_BACKUP_DIR}"
for f in "$MTK" "$PRELOADER" "$LOADER"; do [ -f "$f" ] || { echo "missing $f"; exit 1; }; done
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
  img="$SRC/$p.img"
  [ -f "$img" ] || { echo "skip missing $img"; continue; }
  echo "==> write $p from $img"
  "$MTK" w "$p" "$img" --preloader "$PRELOADER" --loader "$LOADER"
done
echo "slot B stock restore done"
