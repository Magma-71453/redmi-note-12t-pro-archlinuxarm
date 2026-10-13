#!/usr/bin/env bash
# 把 pearl 的 misc 槽位元数据写回 Android slot A。
# 仅使用已在本机实测可过 DAA 的官方 DA_BR.bin + preloader_pearl.bin。
# 需求：设备处于 preloader 模式（lsusb 显示 0e8d:2000），关机后不按任何键插线。
set -uo pipefail
REPO="$(cd "$(dirname "$0")/.." && pwd)"
MTK="${MTK:-$REPO/build/mtk-venv/bin/mtk}"
PRELOADER="${PRELOADER:-$HOME/下载/pearl-MTK验证文件/1-官方ROM提取/preloader_pearl.bin}"
LOADER="${LOADER:-$HOME/下载/pearl-MTK验证文件/1-官方ROM提取/DA_BR.bin}"
MISC_A="${MISC_A:-$HOME/下载/pearl-刷机文件/1-Android恢复-slotA/misc-slot-a.img}"
MISC_STOCK="${MISC_STOCK:-$HOME/下载/pearl-刷机文件/3-原厂分区备份/misc.img}"

echo "== pearl slot A recovery via mtkclient =="
echo "mtk       : $MTK"
echo "preloader : $PRELOADER"
echo "loader    : $LOADER"
echo "misc image: $MISC_A"
echo

for f in "$MTK" "$PRELOADER" "$LOADER" "$MISC_A"; do
  [ -f "$f" ] || { echo "ERROR: missing $f"; exit 1; }
done

if ! lsusb | grep -q '0e8d:2000'; then
  cat <<'TXT'
当前没有检测到 preloader 模式（0e8d:2000）。

物理步骤：
  1) 拔掉 USB
  2) 长按电源键约 20 秒强制关机
  3) 松开电源键，确认所有音量键都松开
  4) 插 USB，不要按任何键
  5) lsusb 应出现 0e8d:2000 MediaTek Preloader
  6) 立刻回来执行本脚本（preloader 窗口可能只有几秒）

注意：如果出现的是 0e8d:0003，说明进的是 BROM。BROM 需要 SLA，公开 DA
无法通过；请强制关机后重新以“不按键”的方式插线，目标是 0e8d:2000。
TXT
  exit 2
fi

set -e
# 先读一份当前 misc 作为现场备份，再写入 slot A。
if [ -n "${BACKUP_DIR:-}" ]; then
  mkdir -p "$BACKUP_DIR"
  echo "==> backup current misc to $BACKUP_DIR/misc-before-recovery.img"
  "$MTK" r misc "$BACKUP_DIR/misc-before-recovery.img" \
    --preloader "$PRELOADER" --loader "$LOADER" || true
fi

echo "==> write misc-slot-a (force slot A active+successful)"
"$MTK" w misc "$MISC_A" --preloader "$PRELOADER" --loader "$LOADER"
rc=$?
echo "mtk_write_rc=$rc"

if [ "$rc" -ne 0 ]; then
  echo "首次写入失败，尝试 stock misc.img ..."
  [ -f "$MISC_STOCK" ] && "$MTK" w misc "$MISC_STOCK" --preloader "$PRELOADER" --loader "$LOADER"
  rc=$?
fi

if [ "$rc" -eq 0 ]; then
  cat <<'TXT'

写入完成。接下来：
  1) 拔掉 USB
  2) 长按电源 20 秒强制关机
  3) 正常开机（不要按音量键）
  4) Android 应该从 A 槽启动

如果仍然黑屏/Preloader 循环，说明不只要改 misc：
  优先尝试用同一套 mtkclient 写回原厂 slot B 备份：
    scripts/recover-slot-b-stock-mtk.sh
TXT
else
  echo "恢复未成功，保留当前状态，先不要反复写分区。" >&2
  exit 1
fi
