#!/usr/bin/env bash
set -uo pipefail
REPO="$(cd "$(dirname "$0")/.." && pwd)"
KSRC="$REPO/build/linux-mt6895"
LLVM_BIN="$REPO/build/llvm-bin/usr/bin"
export PATH="$LLVM_BIN:$PATH"
cd "$KSRC"
exec make LLVM=1 ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- -j"$(nproc)" Image.gz dtbs
