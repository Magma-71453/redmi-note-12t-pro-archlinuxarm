#!/usr/bin/env bash
# 为 armarchlinux-pearl 交叉编译带 Vulkan(PanVK) 后端的 Ollama aarch64 载荷。
#
# 产物: artifacts/ollama-vulkan-arm64/{bin/ollama,lib/ollama/**,VERSION,SHA256SUMS}
# 之后运行: scripts/install-ollama-gpu.sh [rootfs-dir]
#
# 依赖（构建机，x86_64 Arch/CachyOS 实测）：
#   go cmake ninja git curl
#   aarch64-linux-gnu-gcc aarch64-linux-gnu-g++
#   vulkan-headers spirv-tools shaderc glslang
#   build/rootfs-Test/usr/lib/libvulkan.so.1（目标 aarch64 loader，来自 ALARM）
set -euo pipefail
source "$(dirname "$0")/00-env.sh"

OLLAMA_VERSION="${OLLAMA_VERSION:-v0.40.4}"
JOBS="${JOBS:-$(nproc)}"
WORK="$BUILD/ollama-vulkan"
SRC="$WORK/ollama"
STAGE="$WORK/stage"
ARTIFACT="${OLLAMA_ARTIFACT_DIR:-$ART/ollama-vulkan-arm64}"

require() { command -v "$1" >/dev/null 2>&1 || die "缺少命令: $1"; }
require go cmake ninja git curl aarch64-linux-gnu-gcc aarch64-linux-gnu-g++
require glslc glslangValidator
[ -f /usr/include/vulkan/vulkan.h ] || die "缺少 vulkan-headers"
[ -f "$ROOTFS_DIR/usr/lib/libvulkan.so.1" ] || \
  die "缺少目标 aarch64 libvulkan.so.1；请先运行 scripts/30-rootfs.sh 构建 rootfs 树"

mkdir -p "$WORK" "$LOGS"

# 1. Ollama 源码（固定版本，浅克隆）
if [ ! -d "$SRC/.git" ]; then
  log "clone ollama $OLLAMA_VERSION -> $SRC"
  rm -rf "$SRC"
  git clone --depth 1 --branch "$OLLAMA_VERSION" https://github.com/ollama/ollama.git "$SRC"
else
  log "reuse ollama source $SRC"
fi

# 2. aarch64 交叉工具链
TOOLCHAIN="$WORK/toolchain-aarch64.cmake"
cat > "$TOOLCHAIN" <<'EOF'
set(CMAKE_SYSTEM_NAME Linux)
set(CMAKE_SYSTEM_PROCESSOR aarch64)
set(CMAKE_C_COMPILER /usr/bin/aarch64-linux-gnu-gcc)
set(CMAKE_CXX_COMPILER /usr/bin/aarch64-linux-gnu-g++)
set(CMAKE_FIND_ROOT_PATH_MODE_PROGRAM NEVER)
set(CMAKE_FIND_ROOT_PATH_MODE_LIBRARY BOTH)
set(CMAKE_FIND_ROOT_PATH_MODE_INCLUDE BOTH)
set(CMAKE_FIND_ROOT_PATH_MODE_PACKAGE BOTH)
EOF

# 3. 主机侧 SPIRV-Headers（llama.cpp 的 Vulkan 后端需要）
SPIRV="$WORK/host-spirv"
if [ ! -f "$SPIRV/usr/share/cmake/SPIRV-Headers/SPIRV-HeadersConfig.cmake" ]; then
  log "fetch spirv-headers package for build host"
  rm -rf "$SPIRV"; mkdir -p "$SPIRV"
  url="$(pacman -Sp spirv-headers 2>/dev/null | tail -1 || true)"
  [ -n "$url" ] || die "无法解析 spirv-headers 包；请先 pacman -S spirv-headers"
  curl -fsSL "$url" -o "$WORK/spirv-headers.pkg.tar.zst"
  tar --zstd -xf "$WORK/spirv-headers.pkg.tar.zst" -C "$SPIRV"
fi

# 4. 目标 Vulkan loader + 主机 Vulkan 头文件，组装成 CMake 可用的“SDK”
VKS="$WORK/vk-sdk"
rm -rf "$VKS"; mkdir -p "$VKS/include" "$VKS/lib"
cp -a /usr/include/vulkan "$VKS/include/"
[ -d /usr/include/vk_video ] && cp -a /usr/include/vk_video "$VKS/include/"
cp -a "$SPIRV/usr/include/spirv" "$VKS/include/"
target_loader="$(readlink -f "$ROOTFS_DIR/usr/lib/libvulkan.so.1")"
cp -L "$target_loader" "$VKS/lib/libvulkan.so"

# 5. Go 主程序（cgo 交叉，Ollama 的 mlx/sqlite 绑定需要）
log "build ollama Go binary (linux/arm64)"
mkdir -p "$STAGE/bin"
(
  cd "$SRC"
  CGO_ENABLED=1 CC=aarch64-linux-gnu-gcc CXX=aarch64-linux-gnu-g++ \
  GOOS=linux GOARCH=arm64 \
  GOCACHE="$WORK/go-cache" GOMODCACHE="$WORK/go-mod" \
  go build -trimpath -buildmode=pie -ldflags="-w -s" -o "$STAGE/bin/ollama" .
)

# 6. CPU 后端（llama-server + ggml CPU 变体）
log "configure/build llama-server CPU payload (aarch64)"
cmake -S "$SRC/llama/server" --preset cpu \
  -DCMAKE_TOOLCHAIN_FILE="$TOOLCHAIN" \
  -DFETCHCONTENT_BASE_DIR="$WORK/fc-cpu"
cmake --build "$SRC/build/llama-server-cpu" -- -l"$JOBS"
cmake --install "$SRC/build/llama-server-cpu" --component llama-server --strip

# 7. Vulkan 后端（复用上一步已打 Ollama compat patch 的 llama.cpp 源码）
log "configure/build llama-server Vulkan payload (aarch64)"
OLLAMA_LLAMA_CPP_SOURCE="$WORK/fc-cpu/llama_cpp-src" \
cmake -S "$SRC/llama/server" --preset vulkan \
  -DCMAKE_TOOLCHAIN_FILE="$TOOLCHAIN" \
  -DOLLAMA_LLAMA_CPP_SKIP_COMPAT_PATCH=ON \
  -DSPIRV-Headers_DIR="$SPIRV/usr/share/cmake/SPIRV-Headers" \
  -DVulkan_INCLUDE_DIR="$VKS/include" \
  -DVulkan_LIBRARY="$VKS/lib/libvulkan.so" \
  -DVulkan_GLSLC_EXECUTABLE="$(command -v glslc)" \
  -DVulkan_GLSLANG_VALIDATOR_EXECUTABLE="$(command -v glslangValidator)"
cmake --build "$SRC/build/llama-server-vulkan" --target ggml-vulkan -- -l"$JOBS"
cmake --install "$SRC/build/llama-server-vulkan" --component llama-server --strip

# 8. 汇总载荷
log "assemble payload -> $ARTIFACT"
rm -rf "$ARTIFACT"
mkdir -p "$ARTIFACT/bin" "$ARTIFACT/lib/ollama"
install -m755 "$STAGE/bin/ollama" "$ARTIFACT/bin/ollama"
cp -a "$SRC/dist/lib/ollama/." "$ARTIFACT/lib/ollama/"

# 诊断工具：llama-bench（Ollama 调度器默认不安装）
for f in llama-bench libllama-bench-impl.so; do
  if [ -f "$SRC/build/llama-server-cpu/bin/$f" ]; then
    cp -a "$SRC/build/llama-server-cpu/bin/$f" "$ARTIFACT/lib/ollama/$f"
  fi
done

cat > "$ARTIFACT/VERSION" <<EOF
ollama=$OLLAMA_VERSION
llama_cpp=$(cat "$SRC/LLAMA_CPP_VERSION")
arch=aarch64
backend=cpu+vulkan(panvk)
built_utc=$(date -u +%Y-%m-%dT%H:%M:%SZ)
EOF
( cd "$ARTIFACT" && find . -type f ! -name SHA256SUMS -print0 | sort -z | \
    xargs -0 sha256sum > SHA256SUMS )

log "done: $ARTIFACT"
ls -lh "$ARTIFACT/llama-server" 2>/dev/null || ls -lh "$ARTIFACT/lib/ollama/llama-server"
log "next: scripts/install-ollama-gpu.sh ${ROOTFS_DIR#"$REPO"/}"
