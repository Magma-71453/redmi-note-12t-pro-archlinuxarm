#!/usr/bin/env bash
# 只补 B 槽缺失的早期固件分区（用 A 槽同款 LineageOS 镜像）。
# 明确不碰: lk, md1img, preloader, nv/nvdata/nvram/nvcfg, proinfo, persist,
#           userdata, super, 以及所有 _a 分区。
set -uo pipefail
cd -- "$(dirname "$0")/.."
REPO="$PWD"
LIN="${LIN:-$HOME/下载/tmp/one/pearl-fastboot}"
FASTBOOT="${FASTBOOT:-fastboot}"
APPLY=0
[ "${1:-}" = "--yes" ] && APPLY=1

die() { echo "ERROR: $*" >&2; exit 1; }
command -v "$FASTBOOT" >/dev/null 2>&1 || die "fastboot not found"
[ -d "$LIN/images" ] || die "missing $LIN/images"
"$FASTBOOT" devices | grep -q . || die "no fastboot device"

guard_b() {
  local p="$1"
  case "$p" in
    *_a) die "拒绝写 A 槽分区: $p" ;;
    preloader|preloader_*|lk|md1img|nv|nvdata|nvram|nvcfg|proinfo|persist|userdata|super|super_*|\
    frp|seccfg|boot_para|para|expdb|oops|misc)
      die "保护分区禁止写: $p" ;;
  esac
  case "$p" in *_b) ;; *) die "只允许写 _b 分区: $p" ;; esac
}

EARLY=(apusys audio_dsp ccu dpm gpueb gz logo mcf_ota mcupm mvpu_algo pi_img scp spmfw sspm tee vcp)
echo "只补 B 槽早期固件，不碰 lk/md1img/nv/preloader/userdata/super/A 槽"
for part in "${EARLY[@]}"; do
  img="$LIN/images/$part.img"
  [ -f "$img" ] || { echo "SKIP missing image: $img"; continue; }
  target="${part}_b"
  guard_b "$target"
  echo "==> flash $target <- $img"
  if [ "$APPLY" -eq 1 ]; then
    "$FASTBOOT" flash "$target" "$img" || die "flash $target failed"
  else
    echo "    (dry-run)"
  fi
done
echo "完成。B 槽早期固件补全后，可再用 scripts/flash-test.sh --yes --lineage-dtbo 刷 Linux 启动链。"
