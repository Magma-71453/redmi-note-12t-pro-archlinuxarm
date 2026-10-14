# Redmi Note 12T Pro (pearl) — Arch Linux ARM 服务器系统

面向 **Redmi Note 12T Pro / 23054RA19C（代号 `pearl`，SoC MT6895）** 的
Arch Linux ARM (aarch64) 系统。目标是服务器用途：**Docker、SSH、USB 串口 root shell、
labwc + kitty + neovim 桌面**，不用于游戏。

- 内核：Linux **7.2.10++**，MT6895 pearl 专用分支（见 `docs/kernel-provenance.md`）
- Rootfs：Arch Linux ARM，10 GiB ext4（首次启动自动扩容到 linux 分区）
- 桌面：labwc + kitty + foot + neovim + fastfetch + wvkbd 虚拟键盘
- 布局：顶部 C/D 状态面板、中间 kitty、底部虚拟键盘（见 `docs/DESKTOP-LAYOUT.md`）
- 容器：Docker / containerd，overlayfs 正常
- GPU：Panthor + Mesa PanVK（Vulkan 1.4，Mali-G610 MC6）；Ollama Vulkan 见 `docs/GPU-VULKAN-OLLAMA.md`
- 双系统：A 槽保留 Android，B 槽（`boot_b` + `linux=/dev/sdc88`）运行本系统

> 本机真实代号是 `pearl`，不是 `elish`；`elish` 是 Xiaomi Pad 5 Pro 的代号。
> 为避免刷错，本项目所有产物都按 `pearl` / MT6895 构建。

## 安全警告（重要）

- 生成的 rootfs 会启用 SSH 密码认证；初始 `alarm` / `root` 密码由构建脚本在
  `out/Test/rootfs-password.txt` 中生成（该文件被 gitignore，不会提交）。
- 接入不可信网络前，请先修改密码：
  ```bash
  passwd            # 当前用户
  sudo passwd root  # 如果 sudo 已配置
  passwd root       # 直接以 root 执行时
  ```
- 也可以通过环境变量指定构建密码：`ROOTFS_PASSWORD='...' scripts/30-rootfs.sh`。
- 不要再把真实密码、SSH 私钥、设备序列号、IMEI、Wi-Fi 凭据提交到仓库。

## 分区保护

刷写脚本包含受保护分区黑名单，**不会主动写**：

```text
lk / lk_a / lk_b / md1img / md1img_a / md1img_b / nv / nvdata / nvram /
preloader / userdata / super / 以及 A 槽相关分区
```

B 槽引导依赖 `boot_b`、`vendor_boot_b`、`dtbo_b`、`vbmeta*_b`、`misc` 和
`linux=/dev/sdc88`；A 槽 Android 通过 `misc-slot-a.img` 恢复。
刷机有风险，请先阅读 `docs/` 下的说明。

## 仓库结构

```text
src/        自研组件源码（如 pearl-panel）
config/     构建配置与 rootfs 配置文件
scripts/    可复现构建/打包/刷写脚本
docs/       设计、分区、引导、桌面布局、内核来源
artifacts/  体积可控的交付产物（内核、boot/vendor 镜像、校验和）
out/        本机镜像输出（gitignore）
build/      编译工作区（gitignore）
logs/       构建日志（gitignore）
downloads/  上游源码/rootfs 缓存（gitignore）
```

## 构建命令（概要）

```bash
# 0. 准备目录与内核资产（脚本会自行 source 00-env.sh）
scripts/10-recover-modules.sh
scripts/20-kernel-assets.sh

# 1. 内核
scripts/kernel-build-gadget.sh          # 输出 build/linux-mt6895/.../Image.gz

# 2. rootfs（需要 ROOTFS_PASSWORD 或自动生成）
scripts/30-rootfs.sh
scripts/40-image.sh

# 3. boot/vendor 镜像
scripts/50-bootimg-newkernel.sh

# 4. 汇总校验和/清单
scripts/60-finalize.sh

# 5. GPU / Ollama Vulkan（aarch64 交叉编译，详见 docs/GPU-VULKAN-OLLAMA.md）
scripts/build-ollama-vulkan-arm64.sh   # 产物 artifacts/ollama-vulkan-arm64/
scripts/install-ollama-gpu.sh          # 安装进 build/rootfs-Test；30-rootfs.sh 会自动调用

# 5. 桌面组件交叉编译（已包含在 rootfs 构建流程可选步骤中）
scripts/build-wvkbd-arm64.sh
scripts/build-pearl-panel.sh
scripts/fetch-archarm-tools.sh
scripts/install-desktop-tools.sh
```

## Test 产物

- Rootfs：`out/Test/pearl-linux-rootfs-Test.img`（10 GiB ext4）及 `.zst`
- Boot：`out/Test/avb/boot_b-Test-avb.img`
- Vendor boot：`out/Test/avb/vendor_boot_b-Test-avb.img`
- 汇总：`out/Test/MANIFEST.txt`、`out/Test/SHA256SUMS-ALL`
- 已将校验和/manifest 同步到 `artifacts/Test/`。

## GPU / Vulkan / Ollama

- GPU：Mali-G610 MC6 已通过 panthor + Mesa PanVK 提供 Vulkan 1.4。
- Ollama：当前设备/Test 镜像使用官方 v0.40.4 源码 + 自编译 llama.cpp
  `b11521` Vulkan 后端，实测 `100% GPU`（约 10 tokens/s，0.5B 模型）。
- 内核必须为 48-bit VA/PA，并应用
  `patches/0001-pearl-vulkan-ollama-stability.patch`（LK 内存窗口 reserve，
  防止随机重启）；`scripts/kernel-build-gadget.sh` 会自动、幂等应用。
- 运行与从零重编的完整步骤见 **`docs/GPU-VULKAN-OLLAMA.md`**。
- `phi4-mini:3.8b` 默认全 GPU offload 会触发 PanVK device lost；
  用 `scripts/install-ollama-vulkan-models.sh` 创建 `phi4-mini-vk:3.8b`
  （`num_gpu=32`）后运行。

```bash
# 在设备上
ollama pull qwen2.5:0.5b
ollama run qwen2.5:0.5b
ollama ps                     # PROCESSOR 应为 100% GPU

# 在构建机上重编 Ollama Vulkan 载荷
scripts/build-ollama-vulkan-arm64.sh
scripts/install-ollama-gpu.sh build/rootfs-Test
```

> 官方 Ollama Linux arm64 包目前不含 Vulkan 后端（上游 PR #18466），
> 直接用官方包会退回 CPU。

## 桌面布局

| 区域 | 内容 |
| --- | --- |
| A（底部 716px） | wvkbd 虚拟键盘 |
| B（中间） | kitty，`font_size=22`，启动最大化；fastfetch 完整显示 |
| C（顶部左） | Wi-Fi SSID/信号/状态 + 上下行速率/累计流量；点击打开 `nmtui` |
| D（顶部右） | CPU Top2 进程 + 功耗/电量/预计续航；点击打开 `top` |

电源键被映射为 **屏幕 DPMS 开关**，不会关机；关机请在终端执行 `poweroff`。

## 上传 GitHub

仓库当前未配置 remote。创建远端仓库后：

```bash
git remote add origin git@github.com:<user>/<repo>.git
git push -u origin main
```

请先确认 `git status` 干净、`out/`、`build/`、`logs/`、`downloads/`、`.state/`、
`hwparam.json` 没有被提交（它们都在 `.gitignore` 中）。
