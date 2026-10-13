#!/usr/bin/env bash
# preloader 模式下只读抓取：
#   - GPT 分区表
#   - expdb / oops / boot_para / misc / vbmeta_b
# 用官方 DA_BR.bin + preloader_pearl.bin；不写任何分区。
# 用法: scripts/read-mtk-debug.sh [--wait]
set -uo pipefail
REPO="$(cd "$(dirname "$0")/.." && pwd)"
MTK="${MTK:-$REPO/build/mtk-venv/bin/mtk}"
PRE="${PRE:-$HOME/下载/pearl-MTK验证文件/1-官方ROM提取/preloader_pearl.bin}"
DA="${DA:-$HOME/下载/pearl-MTK验证文件/1-官方ROM提取/DA_BR.bin}"
DIR="$REPO/logs/mtk-debug-$(date -u +%Y%m%d-%H%M%S)"
WAIT=0
[ "${1:-}" = "--wait" ] && WAIT=1

python3 "$REPO/scripts/patch-mtkclient-v6.py" >/dev/null 2>&1 || true
mkdir -p "$DIR"
for f in "$MTK" "$PRE" "$DA"; do [ -f "$f" ] || { echo "missing $f"; exit 1; }; done

if ! lsusb | grep -q '0e8d:2000'; then
  if [ "$WAIT" -eq 1 ]; then
    echo "等待 preloader 模式（0e8d:2000）... 关机后不按键插线"
    while ! lsusb | grep -q '0e8d:2000'; do sleep 1; done
  else
    echo "设备不在 preloader 模式 0e8d:2000"; exit 2
  fi
fi
echo "saving to $DIR"

echo "== GPT =="
"$MTK" printgpt --preloader "$PRE" --loader "$DA" > "$DIR/gpt.txt" 2>&1 || true
sed -n '1,120p' "$DIR/gpt.txt"

for p in expdb oops boot_para misc vbmeta_b; do
  echo "== read $p =="
  "$MTK" r "$p" "$DIR/$p.img" --preloader "$PRE" --loader "$DA" || echo "read $p failed"
done
echo "== files =="
ls -lh "$DIR"
cat <<'TIP'

把以上输出和 $DIR 里的 gpt.txt 发出来即可。重点看：
  - gpt.txt 里各分区名/偏移是否正常
  - expdb.img 开头的异常日志（LK/AVB/DTB 错误）
  - oops.img 里的 kernel oops / 启动日志
TIP
