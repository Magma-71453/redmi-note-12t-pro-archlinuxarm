#!/usr/bin/env bash
# 把 pearl 的 misc 槽位元数据写回 Android slot A。
# 仅使用已实测可过 DAA 的官方 DA_BR.bin + preloader_pearl.bin。
# 目标设备状态：preloader 模式（lsusb 显示 0e8d:2000）。
#
# 用法:
#   scripts/recover-slot-a-mtk.sh          # 已处于 preloader 时直接写
#   scripts/recover-slot-a-mtk.sh --wait   # 先等待 preloader，再写（推荐：先运行，再插线）
set -uo pipefail
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
MISC_A="${MISC_A:-$ANDROID_A_DIR/misc-slot-a.img}"
MISC_STOCK="${MISC_STOCK:-$BACKUP_DIR/misc.img}"

need_media() {
  [ -f "$1" ] && return 0
  echo "ERROR: 缺少外部固件/镜像资源: $1" >&2
  echo "       需先准备外部固件/镜像资源目录，见 README 的外部固件与镜像资源目录一节" >&2
  exit 1
}
WAIT=0
[ "${1:-}" = "--wait" ] && WAIT=1

is_preloader() { lsusb 2>/dev/null | grep -q '0e8d:2000'; }
is_brom()      { lsusb 2>/dev/null | grep -q '0e8d:0003'; }

# mtkclient 2.1.4/v6 DA patch：纯 UFS DA 没有 mmc_switch_part 符号会崩。
if [ -f "$REPO/build/mtk-venv" ]; then
  python3 "$REPO/scripts/patch-mtkclient-v6.py" >/dev/null 2>&1 || true
fi

echo "== pearl slot A recovery (misc only) =="
echo "mtk       : $MTK"
echo "preloader : $PRELOADER"
echo "loader    : $LOADER"
echo "misc image: $MISC_A"
echo

[ -f "$MTK" ] || { echo "ERROR: 缺少 mtkclient: $MTK" >&2; exit 1; }
need_media "$PRELOADER"
need_media "$LOADER"
need_media "$MISC_A"

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
"$MTK" w misc "$MISC_A" --preloader $PRELOADER --loader "$LOADER"
rc=$?
echo "mtk_write_rc=$rc"

if [ "$rc" -ne 0 ]; then
  if [ -f "$MISC_STOCK" ]; then
    echo "首次写入失败，尝试 stock misc.img ..."
    "$MTK" w misc "$MISC_STOCK" --preloader $PRELOADER --loader "$LOADER"
    rc=$?
    echo "mtk_write_stock_rc=$rc"
  else
    echo "首次写入失败，且未找到备用镜像 $MISC_STOCK" >&2
    echo "       需先准备外部固件/镜像资源目录，见 README 的外部固件与镜像资源目录一节" >&2
  fi
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
