#!/usr/bin/env bash
# 在 preloader 窗口很短/反复重启时，轮询抓取 expdb/oops 等日志。
# 用法: scripts/capture-mtk-loop.sh [等待秒数]
set -uo pipefail
REPO="$(cd "$(dirname "$0")/.." && pwd)"
MTK="${MTK:-$REPO/build/mtk-venv/bin/mtk}"
PRE="${PRE:-$HOME/下载/pearl-MTK验证文件/1-官方ROM提取/preloader_pearl.bin}"
DA="${DA:-$HOME/下载/pearl-MTK验证文件/1-官方ROM提取/DA_BR.bin}"
OUT="$REPO/logs/mtk-loop-$(date -u +%Y%m%d-%H%M%S)"
WAIT="${1:-300}"
mkdir -p "$OUT"

python3 "$REPO/scripts/patch-mtkclient-v6.py" >/dev/null 2>&1 || true
for f in "$MTK" "$PRE" "$DA"; do [ -f "$f" ] || { echo "missing $f"; exit 1; }; done

echo "输出目录: $OUT"
echo "等待窗口: ${WAIT}s"
echo "请现在: 拔 USB -> 长按电源 20 秒 -> 松开 -> 不按任何键插 USB。"
echo "如果设备自己反复重启进 preloader，也可以保持连接。"

end=$((SECONDS + WAIT)); attempt=0
while [ "$SECONDS" -lt "$end" ]; do
  if lsusb 2>/dev/null | grep -q '0e8d:2000'; then
    attempt=$((attempt+1))
    echo "[$(date -u +%H:%M:%S)] 检测到 preloader，attempt=$attempt，开始读 misc/expdb"
    # 先读小的 misc 验证 DA/握手；成功后再读 expdb
    timeout 90 "$MTK" r misc "$OUT/misc-$attempt.img" \
      --preloader "$PRE" --loader "$DA" >> "$OUT/mtk.log" 2>&1
    if [ -s "$OUT/misc-$attempt.img" ] && [ "$(stat -c %s "$OUT/misc-$attempt.img")" -ge 4194304 ]; then
      echo "[$(date -u +%H:%M:%S)] 握手成功，读取 expdb"
      timeout 180 "$MTK" r expdb "$OUT/expdb.img" \
        --preloader "$PRE" --loader "$DA" >> "$OUT/mtk.log" 2>&1
      if [ -s "$OUT/expdb.img" ] && [ "$(stat -c %s "$OUT/expdb.img")" -ge 8388608 ]; then
        echo "[$(date -u +%H:%M:%S)] expdb 读取成功"
        for p in oops boot_para; do
          timeout 90 "$MTK" r "$p" "$OUT/$p.img" \
            --preloader "$PRE" --loader "$DA" >> "$OUT/mtk.log" 2>&1 || true
        done
        echo "DONE $OUT"
        exit 0
      fi
    fi
    echo "[$(date -u +%H:%M:%S)] attempt=$attempt 失败，继续等下一个 preloader 窗口"
    sleep 0.5
  else
    sleep 0.2
  fi
done
echo "TIMEOUT: 没有抓到完整日志，最后输出目录: $OUT"
exit 1
