#!/usr/bin/env bash
set -uo pipefail
REPO="$(cd "$(dirname "$0")/.." && pwd)"
KSRC="$REPO/build/linux-mt6895"
LLVM_BIN="$REPO/build/llvm-bin/usr/bin"
export PATH="$LLVM_BIN:$PATH"
cd "$KSRC"

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
