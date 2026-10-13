#!/usr/bin/env bash
# 恢复/校验 Test 内核基线：上一轮 pearl 专用 Linux 7.2.9+ 的 Image.gz、
# initramfs、pearl.dtb、内嵌 .config。这些资产在本仓库 artifacts/ 内版本化。
set -euo pipefail
source "$(dirname "$0")/00-env.sh"

log "verify kernel assets in $KERNEL_ASSET_DIR"
cd "$KERNEL_ASSET_DIR"
sha256sum -c SHA256SUMS
log "kernel assets OK:"
ls -lh
