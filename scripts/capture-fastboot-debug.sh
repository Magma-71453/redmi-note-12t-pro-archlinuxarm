#!/usr/bin/env bash
# 在 fastboot 模式下抓取诊断信息（不清分区、不写分区）。
set -uo pipefail
source "$(dirname "$0")/00-env.sh"
DIR="$LOGS/fastboot-debug-$(date -u +%Y%m%d-%H%M%S)"
mkdir -p "$DIR"
fastboot devices | grep -q . || { echo "no fastboot device"; exit 1; }
echo "saving to $DIR"

fastboot getvar all > "$DIR/getvar-all.txt" 2>&1 || true
for v in current-slot slot-unbootable:a slot-unbootable:b slot-retry-count:a slot-retry-count:b \
         partition-size:boot_b partition-size:vendor_boot_b partition-size:dtbo_b \
         partition-size:vbmeta_b partition-size:vbmeta_system_b partition-size:vbmeta_vendor_b \
         partition-size:misc partition-size:linux; do
  { echo "### $v"; fastboot getvar "$v" 2>&1; } >> "$DIR/getvars.txt"
done
fastboot oem dump_pllk_log > "$DIR/pllk-log.bin" 2>&1 || true
# 抓当前 B 槽和日志相关分区；fetch 不支持则跳过
for p in boot_b vendor_boot_b dtbo_b vbmeta_b vbmeta_system_b vbmeta_vendor_b misc boot_para expdb oops; do
  echo "### fetch $p"
  fastboot fetch "$p" "$DIR/$p.img" || echo "fetch $p failed"
done
echo "done: $DIR"
ls -lh "$DIR"
