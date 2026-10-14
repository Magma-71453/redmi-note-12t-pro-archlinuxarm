#!/usr/bin/env bash
# 为已知会触发 PanVK shader/device-lost 的模型创建 Vulkan 安全变体。
#
# 目前已知：
#   phi4-mini:3.8b 默认 num_gpu=-1（33/33 层全 offload）会在 warmup 时
#   触发 panthor CS_FAULT (INSTR_BARRIER_FAULT)，PanVK 报 ErrorDeviceLost，
#   llama-server abort（不会重启内核）。实测 num_gpu=32（输出层/末层留 CPU）
#   可稳定运行，速度约 7-8 tokens/s。
#
# 用法：模型 pull 完成后，在设备上执行本脚本。
set -euo pipefail

command -v ollama >/dev/null || { echo "ollama not found" >&2; exit 1; }

has_model() {
  ollama list 2>/dev/null | awk 'NR>1 {print $1}' | grep -qx "$1"
}

if ! has_model "phi4-mini:3.8b"; then
  echo "phi4-mini:3.8b 尚未 pull；先执行: ollama pull phi4-mini:3.8b" >&2
  exit 0
fi

if has_model "phi4-mini-vk:3.8b"; then
  echo "phi4-mini-vk:3.8b 已存在"
  exit 0
fi

ollama create phi4-mini-vk:3.8b -f - <<'MF'
FROM phi4-mini:3.8b
PARAMETER num_ctx 512
PARAMETER num_gpu 32
MF

echo "已创建 phi4-mini-vk:3.8b，用以下命令运行："
echo "  ollama run phi4-mini-vk:3.8b"
