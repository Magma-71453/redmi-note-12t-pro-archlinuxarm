#!/usr/bin/env bash
# 把交叉编译好的 Ollama Vulkan(aarch64) 载荷安装进 pearl rootfs 树。
#
# 用法: scripts/install-ollama-gpu.sh [rootfs-dir]
#   rootfs-dir 默认 build/rootfs-Test
# 载荷目录: artifacts/ollama-vulkan-arm64/（可用 OLLAMA_ARTIFACT_DIR 覆盖），
# 由 scripts/build-ollama-vulkan-arm64.sh 生成。
set -euo pipefail
source "$(dirname "$0")/00-env.sh"

ROOTFS="${1:-$ROOTFS_DIR}"
ARTIFACT="${OLLAMA_ARTIFACT_DIR:-$ART/ollama-vulkan-arm64}"

[ -d "$ROOTFS/usr" ] || die "rootfs not found: $ROOTFS"
[ -x "$ARTIFACT/bin/ollama" ] || die "missing $ARTIFACT/bin/ollama; run scripts/build-ollama-vulkan-arm64.sh first"
[ -f "$ARTIFACT/SHA256SUMS" ] || die "missing $ARTIFACT/SHA256SUMS"

log "verify ollama-vulkan payload"
( cd "$ARTIFACT" && sha256sum -c SHA256SUMS >/dev/null )

log "install ollama into $ROOTFS"
install -d -m755 "$ROOTFS/usr/local/bin" "$ROOTFS/usr/local/lib/ollama"
install -m755 "$ARTIFACT/bin/ollama" "$ROOTFS/usr/local/bin/ollama"
cp -a "$ARTIFACT/lib/ollama/." "$ROOTFS/usr/local/lib/ollama/"

# PanVK 对长 prompt 的单张图会在 vkEndCommandBuffer 返回 VK_ERROR_OUT_OF_DEVICE_MEMORY；
# 真机实测把 batch/ubatch 限制到 4 可稳定工作。这里用 wrapper 覆盖 Ollama 传入的
# 默认 -b 512/-ub 512（llama.cpp 参数后者覆盖前者）。
install -m755 "$ARTIFACT/lib/ollama/llama-server" \
  "$ROOTFS/usr/local/lib/ollama/llama-server.real"
cat > "$ROOTFS/usr/local/lib/ollama/llama-server" <<'WRAP'
#!/bin/sh
# pearl PanVK workaround: cap batch/ubatch to 4 to avoid vkEndCommandBuffer OOM.
for a in "$@"; do
  case "$a" in
    --list-devices|--version) exec /usr/local/lib/ollama/llama-server.real "$@" ;;
  esac
done
if [ "${OLLAMA_VULKAN:-1}" = "0" ] || [ "${GGML_VK_VISIBLE_DEVICES:-}" = "-1" ]; then
  exec /usr/local/lib/ollama/llama-server.real "$@"
fi
B="${OLLAMA_VK_BATCH:-4}"
exec /usr/local/lib/ollama/llama-server.real "$@" -b "$B" -ub "$B"
WRAP
chmod 755 "$ROOTFS/usr/local/lib/ollama/llama-server"

if [ -x "$ARTIFACT/lib/ollama/llama-bench" ]; then
  ln -sfn /usr/local/lib/ollama/llama-bench "$ROOTFS/usr/local/bin/llama-bench"
fi

# Vulkan/PanVK 稳定性调优：512 context + 关 flash attention + 限制命令流/分配策略。
install -d -m755 "$ROOTFS/etc/systemd/system/ollama.service.d"
cat > "$ROOTFS/etc/systemd/system/ollama.service.d/10-panvk-tune.conf" <<'CONF'
[Service]
Environment="OLLAMA_CONTEXT_LENGTH=512"
Environment="OLLAMA_FLASH_ATTENTION=0"
Environment="OLLAMA_VK_BATCH=4"
Environment="GGML_VK_MAX_NODES_PER_SUBMIT=16"
Environment="GGML_VK_SUBALLOCATION_BLOCK_SIZE=67108864"
Environment="GGML_VK_DISABLE_FUSION=1"
Environment="GGML_VK_DISABLE_GRAPH_OPTIMIZE=1"
Environment="GGML_VK_DISABLE_ASYNC=1"
Environment="GGML_VK_PREFER_HOST_MEMORY=1"
CONF

log "configure ollama user + systemd unit inside rootfs"
"$REPO/scripts/enter-rootfs.sh" "$ROOTFS" /bin/bash -lc '
set -e
useradd --system -M -d /usr/share/ollama -s /usr/sbin/nologin ollama 2>/dev/null || true
usermod -aG render,video ollama 2>/dev/null || true
cat > /etc/systemd/system/ollama.service <<'"'"'UNIT'"'"'
[Unit]
Description=Ollama Service (Vulkan/PanVK + CPU, pearl)
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
# 额外保守措施：强制关闭 shmem 大页。注意内核 panic 的真正修复是 48-bit VA
# 内核（scripts/kernel-build-gadget.sh 强制 KERNEL_FORCE_VA48=1）。
ExecStartPre=+/bin/sh -c '"'"'echo deny > /sys/kernel/mm/transparent_hugepage/shmem_enabled'"'"'
# rootfs 在构建期位于 user namespace，无法直接 chown 到 ollama；改由首次启动时创建。
ExecStartPre=+/usr/bin/install -d -o ollama -g ollama -m 0700 /usr/share/ollama
ExecStart=/usr/local/bin/ollama serve
User=ollama
Group=ollama
SupplementaryGroups=render video
Environment="HOME=/usr/share/ollama"
Environment="OLLAMA_MODELS=/usr/share/ollama/.ollama/models"
Environment="OLLAMA_VULKAN=1"
Environment="OLLAMA_IGPU_ENABLE=1"
Environment="PATH=/usr/local/sbin:/usr/local/bin:/usr/bin"
# 让 Ollama 读取每进程 GPU 显存信息（UMA 设备上可选，失败会自动降级为估算）。
AmbientCapabilities=CAP_PERFMON
CapabilityBoundingSet=CAP_PERFMON
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
UNIT
cat > /etc/systemd/system/pearl-thp-shmem-deny.service <<'"'"'THPUNIT'"'"'
[Unit]
Description=Disable shmem THP globally for Panthor/Mali (extra safety)
DefaultDependencies=no
After=sysinit.target
Before=ollama.service multi-user.target

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/bin/sh -c '"'"'echo deny > /sys/kernel/mm/transparent_hugepage/shmem_enabled'"'"'

[Install]
WantedBy=sysinit.target
THPUNIT
mkdir -p /etc/systemd/system/multi-user.target.wants /etc/systemd/system/sysinit.target.wants
ln -sf ../ollama.service /etc/systemd/system/multi-user.target.wants/ollama.service
ln -sf ../pearl-thp-shmem-deny.service /etc/systemd/system/sysinit.target.wants/pearl-thp-shmem-deny.service
command -v vulkaninfo >/dev/null || echo "WARN: vulkaninfo missing" >&2
[ -f /usr/share/vulkan/icd.d/panfrost_icd.json ] || echo "WARN: panvk ICD missing" >&2
[ -f /usr/lib/firmware/arm/mali/arch10.8/mali_csffw.bin ] || echo "WARN: mali firmware missing" >&2
'

log "ollama installed."
