#!/usr/bin/env bash
# 把 pearl 的 misc 槽位元数据写回 Android slot A。
# 仅使用本机已实测可过 DAA 的官方 DA_BR.bin + preloader_pearl.bin。
# 目标设备状态：preloader 模式（lsusb 显示 0e8d:2000）。
#
# 用法:
#   scripts/recover-slot-a-mtk.sh          # 已处于 preloader 时直接写
#   scripts/recover-slot-a-mtk.sh --wait   # 先等待 preloader，再写（推荐：先运行，再插线）
set -uo pipefail
REPO="$(cd "$(dirname "$0")/.." && pwd)"
MTK="${MTK:-$REPO/build/mtk-venv/bin/mtk}"
PRELOADER="${PRELOADER:-$HOME/下载/pearl-MTK验证文件/1-官方ROM提取/preloader_pearl.bin}"
LOADER="${LOADER:-$HOME/下载/pearl-MTK验证文件/1-官方ROM提取/DA_BR.bin}"
MISC_A="${MISC_A:-$HOME/下载/pearl-刷机文件/1-Android恢复-slotA/misc-slot-a.img}"
MISC_STOCK="${MISC_STOCK:-$HOME/下载/pearl-刷机文件/3-原厂分区备份/misc.img}"
WAIT=0
[ "${1:-}" = "--wait" ] && WAIT=1

is_preloader() { lsusb 2>/dev/null | grep -q '0e8d:2000'; }
is_brom()      { lsusb 2>/dev/null | grep -q '0e8d:0003'; }

echo "== pearl slot A recovery (misc only) =="
echo "mtk       : $MTK"
echo "preloader : $PRELOADER"
echo "loader    : $LOADER"
echo "misc image: $MISC_A"
echo

for f in "$MTK" "$PRELOADER" "$LOADER" "$MISC_A"; do
  [ -f "$f" ] || { echo "ERROR: missing $f"; exit 1; }
done

if ! is_preloader; then
  if [ "$WAIT" -eq 1 ]; then
    echo "等待 preloader 模式（0e8d:2000）..."
    echo "现在请保持插线/重新插线，注意不要按任何音量键。"
    while ! is_preloader; do
      if is_brom; then
        echo "检测到 0e8d:0003 (BROM)；请拔线，长按电源 20 秒，然后不按键插线。"
      fi
      sleep 1
    done
    echo "检测到 preloader 模式，继续。"
  else
    cat <<'TXT'
当前没有检测到 preloader 模式（0e8d:2000）。

物理步骤：
  1) 拔掉 USB
  2) 长按电源键约 20 秒强制关机
  3) 松开电源，确认所有音量键都松开
  4) 插 USB，不要按任何键
  5) lsusb 应出现 0e8d:2000 MediaTek Preloader
  6) 立刻执行: scripts/recover-slot-a-mtk.sh

如果出现 0e8d:0003，说明进的是 BROM。BROM 有 SLA，公开 DA 过不了；
请强制关机后重新以“不按键”的方式插线，目标是 0e8d:2000。
TXT
    exit 2
  fi
fi

echo "==> 写入 misc-slot-a.img（强制 A 槽 active+successful）"
"$MTK" w misc "$MISC_A" --preloader "$PRELOADER" --loader "$LOADER"
rc=$?
echo "mtk_write_rc=$rc"

if [ "$rc" -ne 0 ] && [ -f "$MISC_STOCK" ]; then
  echo "首次写入失败，尝试 stock misc.img ..."
  "$MTK" w misc "$MISC_STOCK" --preloader "$PRELOADER" --loader "$LOADER"
  rc=$?
  echo "mtk_write_stock_rc=$rc"
fi

if [ "$rc" -eq 0 ]; then
  cat <<'TXT'

写入完成。接下来：
  1) 拔掉 USB
  2) 长按电源 20 秒强制关机
  3) 正常开机（不要按音量键）
  4) Android 应该从 A 槽启动

如果仍然黑屏/Preloader 循环，再用同一流程写回原厂 slot B：
  scripts/recover-slot-b-stock-mtk.sh --wait
TXT
  exit 0
else
  echo "恢复写入未成功；先停止反复写分区，保留现场。" >&2
  exit 1
fi
