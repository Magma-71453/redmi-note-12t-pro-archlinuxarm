#!/usr/bin/env bash
# 短 preloader 窗口下反复尝试：只写 misc-slot-a.img，让设备回到 Android A 槽。
# 不碰 lk/md1img/nv/nvdata/userdata/preloader。
set -uo pipefail
REPO="$(cd "$(dirname "$0")/.." && pwd)"
MTK="${MTK:-$REPO/build/mtk-venv/bin/mtk}"
# 外部固件/镜像资源目录（可用同名环境变量覆盖；默认相对仓库根）。
# 目录内容约定见 README 的「外部固件与镜像资源目录」一节。
MEDIA="${PEARL_MEDIA_DIR:-$REPO/downloads/pearl-media}"
ROM_DIR="${PEARL_ROM_DIR:-$MEDIA/rom}"
ANDROID_A_DIR="${PEARL_ANDROID_A_DIR:-$MEDIA/android-recovery-slot-a}"
PRE="${PRE:-$ROM_DIR/images/preloader_pearl.bin}"
DA="${DA:-$ROM_DIR/images/download_agent/DA_BR.bin}"
MISC_A="${MISC_A:-$ANDROID_A_DIR/misc-slot-a.img}"

need_media() {
  [ -f "$1" ] && return 0
  echo "ERROR: 缺少外部固件/镜像资源: $1" >&2
  echo "       需先准备外部固件/镜像资源目录，见 README 的外部固件与镜像资源目录一节" >&2
  exit 1
}
WAIT="${1:-300}"
python3 "$REPO/scripts/patch-mtkclient-v6.py" >/dev/null 2>&1 || true
[ -f "$MTK" ] || { echo "ERROR: 缺少 mtkclient: $MTK" >&2; exit 1; }
need_media "$PRE"
need_media "$DA"
need_media "$MISC_A"
echo "目标：只写 misc <- $MISC_A"
echo "等待窗口：${WAIT}s；现在请拔线 -> 长按电源 20 秒 -> 不按任何键插 USB"
end=$((SECONDS+WAIT)); attempt=0
while [ "$SECONDS" -lt "$end" ]; do
  if lsusb 2>/dev/null | grep -q '0e8d:2000'; then
    attempt=$((attempt+1))
    echo "[$(date -u +%H:%M:%S)] preloader detected attempt=$attempt, write misc-slot-a"
    timeout 60 "$MTK" w misc "$MISC_A" --preloader "$PRE" --loader "$DA" > "$REPO/logs/recover-a-loop-attempt.log" 2>&1
    rc=$?
    if [ "$rc" -eq 0 ] && grep -qE 'Wrote .*misc|sector count 1024' "$REPO/logs/recover-a-loop-attempt.log"; then
      echo "[$(date -u +%H:%M:%S)] misc-slot-a 写入成功"
      echo "接下来：拔线，长按电源20秒，正常开机（不要按音量键），应回 Android A。"
      exit 0
    fi
    echo "[$(date -u +%H:%M:%S)] attempt=$attempt 失败 rc=$rc，继续等下一个窗口"
    sleep 0.3
  else
    sleep 0.2
  fi
done
echo "TIMEOUT: 没抓到可写窗口"
exit 1
