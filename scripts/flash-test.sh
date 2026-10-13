#!/usr/bin/env bash
# Test Linux B 槽刷写（默认：先清 B 槽启动相关分区，再写全尺寸/AVB 镜像）。
#
# 用法:
#   scripts/flash-test.sh --yes               # 刷 Test Linux（默认）
#   scripts/flash-test.sh --yes --stock-b     # 只刷原厂 B 启动链，用于验证 B 槽是否健康
#   scripts/flash-test.sh --yes --stock-vendor-boot  # 用原厂 vendor_boot_b(DTBO table)+我们的 kernel
#   scripts/flash-test.sh --yes --lineage-dtbo       # 用 A 槽正在使用的 LineageOS dtbo.img
#   scripts/flash-test.sh --yes --no-erase    # 不执行 fastboot erase（不推荐）
#   scripts/flash-test.sh --yes --no-avb      # 使用小镜像（旧行为，不推荐）
#   scripts/flash-test.sh --yes --skip-rootfs # 只刷 boot 链，不写 linux rootfs
#   scripts/flash-test.sh --yes --skip-misc   # 不切 B 槽，保持 A active
set -uo pipefail
source "$(dirname "$0")/00-env.sh"

ASSUME_YES=0
STOCK_B=0
STOCK_VENDOR_BOOT=0
LINEAGE_DTBO=0
DO_ERASE=1
USE_AVB=1
DO_ROOTFS=1
DO_MISC=1
DO_REBOOT=1
WIPE_LINUX=0

while [ $# -gt 0 ]; do
  case "$1" in
    --yes) ASSUME_YES=1 ;;
    --stock-b) STOCK_B=1 ;;
    --stock-vendor-boot) STOCK_VENDOR_BOOT=1 ;;
    --lineage-dtbo) LINEAGE_DTBO=1 ;;
    --no-erase) DO_ERASE=0 ;;
    --no-avb) USE_AVB=0 ;;
    --skip-rootfs) DO_ROOTFS=0 ;;
    --skip-misc) DO_MISC=0 ;;
    --skip-reboot) DO_REBOOT=0 ;;
    --wipe-linux) WIPE_LINUX=1 ;;
    -h|--help) sed -n '2,14p' "$0"; exit 0 ;;
    *) echo "unknown arg: $1" >&2; exit 2 ;;
  esac
  shift
done

if [ "$STOCK_B" -eq 1 ]; then
  DO_ROOTFS=0
fi

if [ "$ASSUME_YES" -ne 1 ]; then
  sed -n '2,14p' "$0"
  echo
  echo "未指定 --yes，已拒绝执行。"
  exit 2
fi

FLASH_DIR="$HOME/下载/pearl-刷机文件"
REF_BOOT="$FLASH_DIR/2-Linux启动-slotB"
REF_RECOVERY="$FLASH_DIR/3-原厂分区备份"
LOG="$LOGS/flash-test-$(date -u +%Y%m%d-%H%M%S).log"
mkdir -p "$LOGS"
exec > >(tee -a "$LOG") 2>&1

echo "== pearl B slot flash =="
echo "mode=$([ "$STOCK_B" -eq 1 ] && echo stock-b || echo linux) erase=$DO_ERASE avb=$USE_AVB rootfs=$DO_ROOTFS misc=$DO_MISC"
echo "log=$LOG"

fastboot devices | grep -q . || { echo "ERROR: no fastboot device"; exit 1; }
echo "允许操作: boot_b vendor_boot_b dtbo_b vbmeta_b vbmeta_system_b vbmeta_vendor_b misc linux"
echo "明确不碰 : preloader/lk/md1img/nv/nvdata/nvram/persist/userdata/super/A槽"


# 保护分区黑名单：脚本只允许动 B 槽启动链 + linux/log 分区。
guard_part() {
  local p="$1"
  case "$p" in
    preloader|preloader_*|preloader_raw*|lk|lk_*|md1img|md1img_*|nv|nvdata|nvram|nvcfg|persist|userdata|super|    boot_a|vendor_boot_a|dtbo_a|vbmeta_a|vbmeta_system_a|vbmeta_vendor_a|    proinfo|seccfg|frp|metadata|boot_para|para|expdb|oops|logo*|tee*|gz*|sspm*|mcupm*|gpueb*|apusys*|vcp*|ccu*|dpm*|scp*|pi_img*|mcf_ota*|spmfw*|audio_dsp*|connsys_*|dram_para|backup*|protect*|nvram)
      echo "ERROR: 保护分区禁止操作: $p" >&2
      exit 3
      ;;
  esac
}

# 生成全尺寸 / VBmeta 镜像的工具
part_size_bytes() {
  local p="$1" out hex
  case "$p" in
    boot_b|vendor_boot_b)       echo $((64*1024*1024)); return 0 ;;
    dtbo_b)                     echo $((32*1024*1024)); return 0 ;;
    vbmeta_b|vbmeta_system_b|vbmeta_vendor_b) echo $((8*1024*1024)); return 0 ;;
    misc)                       echo $((4*1024*1024)); return 0 ;;
  esac
  out="$(fastboot getvar "partition-size:$p" 2>&1 | tr -d '\r')"
  hex="$(printf '%s\n' "$out" | grep -oE '0x[0-9a-fA-F]+' | tail -1)"
  [ -n "$hex" ] && printf '%d' "$hex" || echo 0
}
make_fullsize() { # src part dst
  local src="$1" part="$2" dst="$3" size srcsize
  size="$(part_size_bytes "$part")"
  srcsize="$(stat -c %s "$src")"
  if [ "$size" -le 0 ]; then
    echo "WARN: cannot read partition-size:$part, use source as-is"
    cp -f "$src" "$dst"
    return 0
  fi
  if [ "$srcsize" -gt "$size" ]; then
    echo "ERROR: $src ($srcsize) > $part ($size)" >&2
    return 1
  fi
  cp -f "$src" "$dst"
  truncate -s "$size" "$dst"
}

erase_part() {
  local p="$1"
  guard_part "$p"
  echo "==> erase $p"
  fastboot erase "$p" || echo "WARN: erase $p failed (will rely on full-size image)"
}

flash_part() {
  local p="$1" img="$2"
  guard_part "$p"
  echo "==> flash $p <- $img"
  fastboot flash "$p" "$img" || { echo "ERROR: flash $p failed" >&2; exit 1; }
}

# 准备镜像
if [ "$STOCK_B" -eq 0 ] && [ "$USE_AVB" -eq 1 ] && [ ! -f "$OUT/avb/boot_b-Test-avb.img" ]; then
  "$REPO/scripts/55-bootimg-avb.sh"
fi
if [ "$STOCK_B" -eq 1 ]; then
  BOOT_IMG="$REF_RECOVERY/boot_b.img"
  VENDOR_BOOT_IMG="$REF_RECOVERY/vendor_boot_b.img"
  DTBO_IMG="$REF_RECOVERY/dtbo_b.img"
  VBMETA_B_IMG="$REF_RECOVERY/vbmeta_b.img"
  VBMETA_SYS_IMG=""
  VBMETA_VENDOR_IMG=""
  ROOTFS_IMG=""
else
  if [ "$USE_AVB" -eq 1 ]; then
    BOOT_IMG="$OUT/avb/boot_b-Test-avb.img"
  else
    BOOT_IMG="$OUT/boot_b-Test.img"
  fi
  if [ "$STOCK_VENDOR_BOOT" -eq 1 ]; then
    # 原厂 vendor_boot_b 的 dtb 字段是 Android DTBO table；LK 期望这个格式。
    VENDOR_BOOT_IMG="$REF_RECOVERY/vendor_boot_b.img"
  elif [ "$USE_AVB" -eq 1 ]; then
    VENDOR_BOOT_IMG="$OUT/avb/vendor_boot_b-Test-avb.img"
  else
    VENDOR_BOOT_IMG="$OUT/vendor_boot_b-Test.img"
  fi
  if [ "$LINEAGE_DTBO" -eq 1 ]; then
    DTBO_IMG="$HOME/下载/tmp/one/pearl-fastboot/images/dtbo.img"
  else
    DTBO_IMG="$REF_BOOT/dtbo_b-stock.img"
  fi
  VBMETA_B_IMG="$REF_BOOT/vbmeta_b-disabled-8m.img"
  VBMETA_SYS_IMG="$REF_BOOT/vbmeta_system_b-disabled.img"
  VBMETA_VENDOR_IMG="$REF_BOOT/vbmeta_vendor_b-disabled.img"
  ROOTFS_IMG="$OUT/$ROOTFS_IMAGE_NAME"
fi
[ -f "$BOOT_IMG" ] || { echo "missing $BOOT_IMG"; exit 1; }
[ -f "$VENDOR_BOOT_IMG" ] || { echo "missing $VENDOR_BOOT_IMG"; exit 1; }
[ -f "$DTBO_IMG" ] || { echo "missing $DTBO_IMG"; exit 1; }
[ -f "$VBMETA_B_IMG" ] || { echo "missing $VBMETA_B_IMG"; exit 1; }
if [ "$DO_ROOTFS" -eq 1 ] && [ ! -f "$ROOTFS_IMG" ]; then
  echo "missing $ROOTFS_IMG"; exit 1
fi

# 清掉 B 槽上一轮遗留数据
if [ "$DO_ERASE" -eq 1 ]; then
  ERASE_PARTS=(boot_b vendor_boot_b dtbo_b vbmeta_b misc)
  if [ "$STOCK_B" -eq 0 ]; then
    # Linux 模式会写入 disabled 的 system/vendor vbmeta，可以清空；
    # stock-b 模式没有原厂 system/vendor vbmeta 备份，不能擦，否则 AVB 链断裂。
    ERASE_PARTS+=(vbmeta_system_b vbmeta_vendor_b)
  fi
  for p in "${ERASE_PARTS[@]}"; do
    erase_part "$p"
  done
fi

# 写入
flash_part boot_b "$BOOT_IMG"
flash_part vendor_boot_b "$VENDOR_BOOT_IMG"
flash_part dtbo_b "$DTBO_IMG"
flash_part vbmeta_b "$VBMETA_B_IMG"
if [ -n "$VBMETA_SYS_IMG" ] && [ -f "$VBMETA_SYS_IMG" ]; then
  # 4K disabled vbmeta 需要补到分区尺寸，避免分区里残留原厂数据
  make_fullsize "$VBMETA_SYS_IMG" vbmeta_system_b "$BUILD/vbmeta_system_b-disabled-full.img"
  flash_part vbmeta_system_b "$BUILD/vbmeta_system_b-disabled-full.img"
fi
if [ -n "$VBMETA_VENDOR_IMG" ] && [ -f "$VBMETA_VENDOR_IMG" ]; then
  make_fullsize "$VBMETA_VENDOR_IMG" vbmeta_vendor_b "$BUILD/vbmeta_vendor_b-disabled-full.img"
  flash_part vbmeta_vendor_b "$BUILD/vbmeta_vendor_b-disabled-full.img"
fi

if [ "$DO_ROOTFS" -eq 1 ]; then
  if [ "$WIPE_LINUX" -eq 1 ]; then
    echo "==> erase linux (可能较慢)"
    fastboot erase linux || echo "WARN: erase linux failed, 继续 flash"
  fi
  flash_part linux "$ROOTFS_IMG"
fi

if [ "$DO_MISC" -eq 1 ]; then
  flash_part misc "$REF_BOOT/misc-slot-b.img"
fi

echo "==> slot info after flash"
fastboot getvar current-slot 2>&1 | tail -3 || true
fastboot getvar slot-unbootable:a 2>&1 | tail -2 || true
fastboot getvar slot-unbootable:b 2>&1 | tail -2 || true
fastboot getvar slot-retry-count:b 2>&1 | tail -2 || true

if [ "$DO_REBOOT" -eq 1 ]; then
  echo "==> reboot"
  fastboot reboot
else
  echo "==> skip reboot; device remains in fastboot"
fi

cat <<'TIP'
如果重启后直接回 Preloader/BROM：
  1) 不要反复刷；先重新进 fastboot
  2) 执行 scripts/capture-fastboot-debug.sh 抓 getvar / dump_pllk_log / 分区
  3) 如果 fastboot 也进不去，按 preloader 模式 + scripts 里的 mtkclient 读 expdb 日志
回到 Android A 槽:
  scripts/restore-android-a.sh --yes
TIP
