#!/usr/bin/env bash
# 短 preloader 窗口下反复尝试：只写 misc-slot-a.img，让设备回到 Android A 槽。
# 不碰 lk/md1img/nv/nvdata/userdata/preloader。
set -uo pipefail
REPO="$(cd "$(dirname "$0")/.." && pwd)"
MTK="${MTK:-$REPO/build/mtk-venv/bin/mtk}"
PRE="${PRE:-/mnt/Users/magma/Downloads/pearl_images_OS2.0.207.0.VLHCNXM_15.0/images/preloader_pearl.bin}"
DA="${DA:-/mnt/Users/magma/Downloads/pearl_images_OS2.0.207.0.VLHCNXM_15.0/images/download_agent/DA_BR.bin}"
MISC_A="${MISC_A:-$HOME/下载/pearl-刷机文件/1-Android恢复-slotA/misc-slot-a.img}"
WAIT="${1:-300}"
python3 "$REPO/scripts/patch-mtkclient-v6.py" >/dev/null 2>&1 || true
for f in "$MTK" "$PRE" "$DA" "$MISC_A"; do [ -f "$f" ] || { echo "missing $f"; exit 1; }; done
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
