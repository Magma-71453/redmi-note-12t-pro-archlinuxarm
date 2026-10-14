#!/usr/bin/env bash
set -uo pipefail
REPO="$(cd "$(dirname "$0")/.." && pwd)"
KSRC="$REPO/build/linux-mt6895"
LLVM_BIN="$REPO/build/llvm-bin/usr/bin"
export PATH="$LLVM_BIN:$PATH"
cd "$KSRC"

# 应用 $REPO/patches/*.patch（幂等）：
#   - 48-bit VA/PA 之后仍需修复 LK 内存窗口中无线性映射的 RAM 区，
#     否则 buddy 分配器把坏页发给任意进程，clear_page() 会 kernel panic。
#   - 这些补丁已在 7.2.10++ #10 真机验证；详见 docs/GPU-VULKAN-OLLAMA.md。
if [ "${KERNEL_SKIP_PATCHES:-0}" != 1 ]; then
  for p in "$REPO"/patches/*.patch; do
    [ -e "$p" ] || continue
    if git -C "$KSRC" apply --check "$p" 2>/dev/null; then
      echo "[kernel-build] apply $(basename "$p")"
      git -C "$KSRC" apply "$p" || exit 1
    elif git -C "$KSRC" apply --reverse --check "$p" 2>/dev/null; then
      echo "[kernel-build] already applied $(basename "$p")"
    else
      echo "[kernel-build] ERROR: patch conflict: $(basename "$p")" >&2
      exit 1
    fi
  done
fi

# pearl / MT6895：Cortex-A78/A55 只支持 48-bit VA。内核若按 52-bit VA 编译，
# 会走 arm64 的 vabits_actual=48 fallback，并调整 memstart_addr；该路径下
# page_to_virt() 会算出错误线性映射地址，panthor 在 pin GEM 页时触发
# clear_page 内核 panic。这里强制 48-bit VA/PA。
if [ "${KERNEL_FORCE_VA48:-1}" = 1 ]; then
  ./scripts/config --file .config \
    --disable ARM64_VA_BITS_52 --enable ARM64_VA_BITS_48 \
    --disable ARM64_PA_BITS_52 --enable ARM64_PA_BITS_48 \
    --disable ARM64_LPA2
  make LLVM=1 ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- olddefconfig
fi

exec make LLVM=1 ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- -j"$(nproc)" Image.gz dtbs
