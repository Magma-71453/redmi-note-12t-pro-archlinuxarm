# pearl GPU / Vulkan / Ollama GPU 说明

目标：在 Redmi Note 12T Pro（`pearl`，MT6895）的 armarchlinux-pearl 上，
用开源驱动栈提供 Vulkan，并让 Ollama 通过 Vulkan 使用 Mali-G610。

## 结论（真机已验证，2026-10-15）

- 内核：`panthor` 1.8.0（built-in），GPU `13000000.gpu` 绑定成功，
  `/dev/dri/card1` 与 `/dev/dri/renderD128` 为 Mali。
- 内核必须使用 **48-bit VA/PA**（见下文内核 panic）；当前真机 `uname -r` 为
  `7.2.10++`，`CONFIG_ARM64_VA_BITS=48`、`CONFIG_ARM64_PA_BITS=48`。
- 用户态：Arch Linux ARM `vulkan-panfrost` 1:26.2.4-1（PanVK）。
  `vulkaninfo --summary`：

  ```text
  deviceName  = Mali-G610 MC6
  driverID    = DRIVER_ID_MESA_PANVK
  driverName  = panvk
  apiVersion  = 1.4.354
  deviceType  = PHYSICAL_DEVICE_TYPE_INTEGRATED_GPU
  ```

- Ollama：官方 v0.40.4 Linux arm64 包**没有** Vulkan 后端
  （上游 PR #18466 仍 open）。本仓库用官方 v0.40.4 源码的 Go 主程序 +
  交叉编译的 llama.cpp `b11521` Vulkan 后端（`libggml-vulkan.so`）。

- 真机实测 `ollama run` / `/api/generate`：

  ```text
  PROCESSOR = 100% GPU
  CONTEXT   = 512
  eval      ≈ 10 tokens/s
  prompt eval ≈ 10-15 tokens/s
  ```

## 内核侧：52-bit VA 回退导致 panthor 内核 panic

本项目早期内核按 `CONFIG_ARM64_VA_BITS_52 + ARM64_PA_BITS_52 + LPA2` 编译，
但 MT6895（Cortex-A78/A55）只支持 48-bit VA，内核在启动时进入
`vabits_actual=48` 回退路径并调整 `memstart_addr`。该路径下 `page_to_virt()`
会算出未映射的线性映射地址，panthor 第一次 pin 大 GEM 对象时触发：

```text
Unhandled 64-bit el1h sync exception ... Comm: llama-server
pc : clear_page+0x30/0x68
lr : shmem_get_folio_gfp+0x324/0x63c
 drm_gem_get_pages
 panthor_gem_backing_pin_locked
 panthor_vm_bind_exec_sync_op
Kernel panic - not syncing: Unhandled exception
```

panic 里的 `PHYS_OFFSET: 0xfff1000040000000` 就是 52→48 回退修正值。

**修复方式：内核强制 48-bit VA/PA**

`scripts/kernel-build-gadget.sh` 在编译前执行：

```text
CONFIG_ARM64_VA_BITS_48=y       (disable 52)
CONFIG_ARM64_PA_BITS_48=y       (disable 52)
CONFIG_ARM64_LPA2 关闭
```

真机验证：`uname -r` 仍是 `7.2.10++`，但不再 panic，panthor/Vulkan/llama.cpp
正常工作。验证内核镜像为 `out/Test/avb/boot_b-Test-48va-avb.img`。

（`pearl-thp-shmem-deny.service` 只是额外保守措施，强制 shmem 不使用大页，
不是上述 panic 的修复；真正的修复是 48-bit VA 内核。）

## 用户态安装

`config/build.conf` / `scripts/rootfs-packages.sh` 包含：

```text
mesa mesa-utils vulkan-icd-loader
vulkan-panfrost vulkan-tools vulkan-mesa-layers
```

安装后：

```text
/usr/lib/libvulkan_panfrost.so
/usr/share/vulkan/icd.d/panfrost_icd.json
```

`vulkan-panfrost` 必须和 `mesa` 同版本（当前均为 1:26.2.4-1）。

## Ollama Vulkan 载荷

构建（x86_64 构建机，需要联网）：

```bash
scripts/build-ollama-vulkan-arm64.sh
# 产物 artifacts/ollama-vulkan-arm64/{bin/ollama,lib/ollama/**}
```

安装进 rootfs 树：

```bash
scripts/install-ollama-gpu.sh build/rootfs-Test
# 若已有图像：scripts/40-image.sh && scripts/60-finalize.sh
```

固定版本：Ollama `v0.40.4`，llama.cpp `b11521`，llama-server `0.6.0-dev`。

## PanVK 长 prompt 的 `vkEndCommandBuffer` OOM

短 prompt（1 token）时 Vulkan 推理正常；但 Ollama 的 chat 模板会把 “hello”
扩成 ~82 tokens 的 prompt，此时 PanVK 在 `vkEndCommandBuffer()` 返回
`VK_ERROR_OUT_OF_DEVICE_MEMORY`：

```text
decode() failed: vk::CommandBuffer::end: ErrorOutOfDeviceMemory
```

真机实测：

```text
-b/-ub 16/32/64/128/512  -> OOM
-b/-ub 4                 -> 成功（长 prompt + 生成都正常）
```

这是 PanVK 单张 prompt 图的命令流限制/fragmentation 问题，不是系统内存不足
（测试时 MemAvailable 仍有 6.5 GiB）。规避方式：

`scripts/install-ollama-gpu.sh` 会：

1. 把真正的 `llama-server` 装成 `llama-server.real`；
2. 用 wrapper 覆盖 `/usr/local/lib/ollama/llama-server`，在 Ollama 传入的
   `-b 512 -ub 512` 之后追加 `-b 4 -ub 4`（llama.cpp 后者覆盖前者）；
3. 写入 `/etc/systemd/system/ollama.service.d/10-panvk-tune.conf`：

```text
OLLAMA_CONTEXT_LENGTH=512
OLLAMA_FLASH_ATTENTION=0
OLLAMA_VK_BATCH=4
GGML_VK_MAX_NODES_PER_SUBMIT=16
GGML_VK_SUBALLOCATION_BLOCK_SIZE=67108864
GGML_VK_DISABLE_FUSION=1
GGML_VK_DISABLE_GRAPH_OPTIMIZE=1
GGML_VK_DISABLE_ASYNC=1
GGML_VK_PREFER_HOST_MEMORY=1
```

如需更大的 context 或 batch，可修改这些值后
`systemctl daemon-reload && systemctl restart ollama`，再按上面的方法实测；
`OLLAMA_VK_BATCH` 可单独覆盖 wrapper 的 batch。

## 真机验证命令

```bash
# 1. 内核 VA 与 Vulkan 设备
uname -a
zcat /proc/config.gz | grep -E 'CONFIG_ARM64_VA_BITS=|CONFIG_ARM64_PA_BITS='
vulkaninfo --summary | sed -n '/GPU0:/,/driverUUID/p'

# 2. PanVK + llama.cpp Vulkan 后端
GGML_BACKEND_PATH=/usr/local/lib/ollama/vulkan/libggml-vulkan.so \
  /usr/local/lib/ollama/llama-server --list-devices

# 3. Ollama
systemctl status ollama --no-pager
ollama list
ollama run qwen2.5:0.5b "你好"
ollama ps          # PROCESSOR 应显示 100% GPU
journalctl -u ollama -b --no-pager | grep -E 'library=Vulkan|Mali|n_batch|decode'
```

API 方式：

```bash
curl -s http://127.0.0.1:11434/api/generate \
  -d '{"model":"qwen2.5:0.5b","prompt":"hello","stream":false,
       "options":{"num_ctx":512,"num_predict":8,"temperature":0}}' | jq .
```

## 已知限制 / 注意事项

- PanVK 仍是较新的开源驱动；Mesa 25.0 起对 Mali-G610 默认启用并达到
  Vulkan 1.1 conformance，26.x 使用中仍可能遇到命令流/内存边界问题。
- 当前默认 context 512、batch 4，是为了稳定性；模型越大、prompt 越长，
  需要重新实测调参。
- `/tmp` 在 fstab 中是 `noexec`，测试可执行文件不要放 `/tmp`。
- 官方 ARM64 Ollama 合并 Vulkan 支持后（PR #18466），可改回官方包；
  届时删除自编译的 `lib/ollama/vulkan` 和 wrapper 即可。
- 不要删除 `/usr/lib/firmware/arm/mali/arch10.10/mali_csffw.bin` 的未压缩实体；
  当前内核没有 `CONFIG_FW_LOADER_COMPRESS_ZSTD`。

---

# 从零重编 Ollama（x86_64 构建机 → aarch64 设备）

本节记录本项目实际使用的完整步骤，便于以后 Ollama/llama.cpp 升级或重新构建。

## 0. 构建机依赖

在 Arch/CachyOS 构建机上安装：

```bash
sudo pacman -S --needed \
  base-devel git go cmake ninja curl \
  aarch64-linux-gnu-gcc aarch64-linux-gnu-g++ \
  vulkan-headers spirv-tools shaderc glslang
```

`spirv-headers` 如果未安装，脚本会自动从 Arch 镜像下载 package 并解包到
`build/ollama-vulkan/host-spirv/`。目标 aarch64 的 Vulkan loader 需要先有
`build/rootfs-Test/usr/lib/libvulkan.so.1`（由 `scripts/30-rootfs.sh` 或
ALARM `vulkan-icd-loader` 包提供）。

版本固定：

```text
Ollama       v0.40.4   (可用 OLLAMA_VERSION 覆盖)
llama.cpp    b11521    (Ollama 仓库内的 LLAMA_CPP_VERSION)
```

## 1. 使用脚本一键构建（推荐）

```bash
cd redmi-note-12t-pro-linux
scripts/build-ollama-vulkan-arm64.sh
```

脚本会：

1. 浅克隆 `https://github.com/ollama/ollama.git` 到
   `build/ollama-vulkan/ollama`；
2. 写 aarch64 CMake toolchain，并用 cgo 交叉编译 Ollama Go 主程序；
3. 用 preset `cpu` 构建 `llama-server` + ggml CPU 多变体；
4. 准备 host Vulkan headers/SPIRV-Headers + 目标 `libvulkan.so.1`，
   用 preset `vulkan` 构建 `libggml-vulkan.so`；
5. 汇总到：

```text
artifacts/ollama-vulkan-arm64/
  bin/ollama
  lib/ollama/llama-server
  lib/ollama/llama-server.real（安装时由 install 脚本生成）
  lib/ollama/libggml*.so
  lib/ollama/vulkan/libggml-vulkan.so
  lib/ollama/llama-bench
  VERSION
  SHA256SUMS
```

构建耗时：16 核构建机约 20–40 分钟，产物约 90 MiB。

## 2. 手动命令（脚本失败/需要排查时）

```bash
WORK=$PWD/build/ollama-vulkan
SRC=$WORK/ollama
mkdir -p "$WORK"

git clone --depth 1 --branch v0.40.4 \
  https://github.com/ollama/ollama.git "$SRC"

cat > "$WORK/toolchain-aarch64.cmake" <<'EOF2'
set(CMAKE_SYSTEM_NAME Linux)
set(CMAKE_SYSTEM_PROCESSOR aarch64)
set(CMAKE_C_COMPILER /usr/bin/aarch64-linux-gnu-gcc)
set(CMAKE_CXX_COMPILER /usr/bin/aarch64-linux-gnu-g++)
set(CMAKE_FIND_ROOT_PATH_MODE_PROGRAM NEVER)
set(CMAKE_FIND_ROOT_PATH_MODE_LIBRARY BOTH)
set(CMAKE_FIND_ROOT_PATH_MODE_INCLUDE BOTH)
set(CMAKE_FIND_ROOT_PATH_MODE_PACKAGE BOTH)
EOF2

# Go 主程序（cgo 交叉；Ollama 的 sqlite/mlx 绑定需要 cgo）
cd "$SRC"
CGO_ENABLED=1 CC=aarch64-linux-gnu-gcc CXX=aarch64-linux-gnu-g++ \
GOOS=linux GOARCH=arm64 \
GOCACHE="$WORK/go-cache" GOMODCACHE="$WORK/go-mod" \
go build -trimpath -buildmode=pie -ldflags="-w -s" \
  -o "$WORK/stage-ollama" .

# CPU 后端
cmake -S llama/server --preset cpu \
  -DCMAKE_TOOLCHAIN_FILE="$WORK/toolchain-aarch64.cmake" \
  -DFETCHCONTENT_BASE_DIR="$WORK/fc-cpu"
cmake --build build/llama-server-cpu -- -l"$(nproc)"
cmake --install build/llama-server-cpu --component llama-server --strip

# 准备 host Vulkan SDK 目录（headers + 目标 loader + spirv headers）
VKS="$WORK/vk-sdk"; rm -rf "$VKS"; mkdir -p "$VKS/include" "$VKS/lib"
cp -a /usr/include/vulkan /usr/include/vk_video "$VKS/include/" 2>/dev/null || true
# spirv-headers 可由 pacman -Sp spirv-headers 下载后解包到 $WORK/host-spirv
cp -a "$WORK/host-spirv/usr/include/spirv" "$VKS/include/"
cp -L build/rootfs-Test/usr/lib/libvulkan.so.1 "$VKS/lib/libvulkan.so"

# Vulkan 后端（复用已打 Ollama compat patch 的 llama.cpp 源码）
OLLAMA_LLAMA_CPP_SOURCE="$WORK/fc-cpu/llama_cpp-src" \
cmake -S llama/server --preset vulkan \
  -DCMAKE_TOOLCHAIN_FILE="$WORK/toolchain-aarch64.cmake" \
  -DOLLAMA_LLAMA_CPP_SKIP_COMPAT_PATCH=ON \
  -DSPIRV-Headers_DIR="$WORK/host-spirv/usr/share/cmake/SPIRV-Headers" \
  -DVulkan_INCLUDE_DIR="$VKS/include" \
  -DVulkan_LIBRARY="$VKS/lib/libvulkan.so" \
  -DVulkan_GLSLC_EXECUTABLE="$(command -v glslc)" \
  -DVulkan_GLSLANG_VALIDATOR_EXECUTABLE="$(command -v glslangValidator)"
cmake --build build/llama-server-vulkan --target ggml-vulkan -- -l"$(nproc)"
cmake --install build/llama-server-vulkan --component llama-server --strip
```

`page_to_virt()` 提示：不要用 52-bit VA 内核（见上文）；否则运行时会 panic。

## 3. 安装到 rootfs / 设备

```bash
# 安装进构建机的 rootfs 树（会生成 wrapper 与 systemd drop-in）
scripts/install-ollama-gpu.sh build/rootfs-Test

# 重新生成可刷机镜像（out/Test，gitignore）
scripts/40-image.sh
scripts/60-finalize.sh
```

安装脚本会自动：

- 复制 `bin/ollama`、`lib/ollama/**` 到 `/usr/local/`；
- 把真 `llama-server` 放到 `llama-server.real`，并安装 batch=4 wrapper；
- 写 `ollama.service` 和 `ollama.service.d/10-panvk-tune.conf`；
- 创建 `ollama` 系统用户并加入 `render,video` 组。

## 4. 在设备上运行 Ollama

```bash
# 连接设备
dbclient -i ~/.ssh/dropbear_ed25519_host_key alarm@192.168.7.204

# 拉取模型（走系统服务，存储于 /usr/share/ollama/.ollama/models）
ollama pull qwen2.5:0.5b
ollama list

# 交互式运行（推荐有 TTY 的 SSH）
ollama run qwen2.5:0.5b

# 查看是否 100% GPU
ollama ps
```

API 方式：

```bash
curl -s http://127.0.0.1:11434/api/generate \
  -H 'Content-Type: application/json' \
  -d '{"model":"qwen2.5:0.5b","prompt":"你好","stream":false,
       "options":{"num_ctx":512,"num_predict":32,"temperature":0}}' | jq .
```

预期：`PROCESSOR 100% GPU`，生成约 10 tokens/s，prompt eval 约 14–15 tokens/s
（Mali-G610 MC6，0.5B q4 模型；模型/上下文不同会有差异）。

## 5. 升级 / 换版本

```bash
# 确认 Ollama 固定版本
OLLAMA_VERSION=v0.41.0 scripts/build-ollama-vulkan-arm64.sh
# llama.cpp 版本由 Ollama 仓库的 LLAMA_CPP_VERSION 决定

scripts/install-ollama-gpu.sh build/rootfs-Test
systemctl restart ollama   # 设备上
```

## 6. 常见问题排查

| 现象 | 原因/处理 |
| --- | --- |
| 内核 panic，`clear_page` / `panthor_vm_bind` | 内核是 52-bit VA fallback；用 48-bit VA 内核（`boot_b-Test-48va-avb.img`） |
| `vk::CommandBuffer::end: ErrorOutOfDeviceMemory` | PanVK 长 prompt 命令流问题；确保 `llama-server` wrapper 生效（batch=4），检查 `n_batch = 4` |
| `vulkaninfo` 找不到 GPU | 缺 `vulkan-panfrost` 或 ICD 未安装；检查 `/usr/share/vulkan/icd.d/` 与 `/dev/dri/renderD128` |
| Ollama 只走 CPU | 官方 arm64 包不含 Vulkan；使用本仓库编译的 payload，或检查 `OLLAMA_VULKAN=1` / `OLLAMA_IGPU_ENABLE=1` |
| `ollama run` 非 TTY 卡住 | 用交互式 SSH，或用 `curl /api/generate` |
| `/tmp` 下程序无法执行 | fstab 将 `/tmp` 挂为 `noexec`；用 `/home/alarm` 或正式安装路径 |
