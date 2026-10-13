# Redmi Note 12T Pro (pearl) — Linux Server Test 镜像

> 目标：为 **Redmi Note 12T Pro / 23054RA19C（真机代号 `pearl`，SoC MT6895）** 构建
> 面向服务器用途的 **Arch Linux ARM (aarch64)** 系统。
> 桌面使用轻量 Wayland 合成器 **labwc**，终端 **kitty**，编辑器 **neovim**，并支持 **Docker**。
> 内核目标系列：**Linux 7.2.x**。首个交付版本标题：**Test**。

仓库目录：``

## 重要更正：真机代号不是 `elish`

用户描述为 “Redmi Note 12 T Pro (elish)”，但 ADB 真机读数为：

| 项目 | 真机值 |
|---|---|
| `ro.product.device` | `pearl` |
| `ro.product.model` | `23054RA19C` |
| `ro.board.platform` | `mt6895` |
| 型号 | Redmi Note 12T Pro（中国版） |
| 启动槽 | `_a`（A/B 设备） |
| Bootloader | 已解锁（`ro.boot.verifiedbootstate=orange`） |
| ADB 序列号 | `REDACTED_DEVICE_SERIAL` |

`elish` 是 **Xiaomi Pad 5 Pro Wi-Fi（SM8250）** 的代号；本机 `pearl` 是 MTK MT6895 平台。
为避免刷错内核/DTB，本项目按真机 **pearl / MT6895** 构建。

## 分区布局（真机 ADB 读取）

```
boot_a    -> /dev/block/sdc43   64 MiB      当前 Android 引导，保持
boot_b    -> /dev/block/sdc72   64 MiB      Linux Test 引导目标
linux     -> /dev/block/sdc88   ~166 GiB    现有 ext4 LABEL=archpearl
userdata  -> /dev/block/sdc86   ~59.6 GiB   Android userdata，保持不动
```

现有 `linux` 分区是上一轮实验的半成品：ext4 `LABEL=archpearl`
`UUID=b7ae3de3-b7d9-4df6-a640-6d66cfa988da`，文件系统只用约 5.24 GiB 且仅剩 ~94 MiB，
581 个包（GNOME/GDM 等），没有 labwc/kitty/neovim/docker，`/boot` 为空，
但 `/usr/lib/modules/7.2.9+` 有 1544 个 `.ko`。本项目另建完整 Test 镜像，不破坏旧分区。

## 双系统设计

1. `boot_a` 保留 Android，Android 继续挂载 `/dev/sdc86` userdata。
2. 自定义 `boot_b` = Linux 7.2.x 内核 + 自定义 initramfs。
3. initramfs 扫描 `/sys/class/block/*/uevent` 的 `PARTNAME=linux`，挂载 ext4 后 `switch_root`。
4. 刷写/切槽命令只记录在 `docs/boot_b.md`，需单独确认执行，不触碰 Android 其他分区。
5. Android 回退：`fastboot --set-active=a`。

## 目录

```
config/     构建配置（版本、分区、内核、包集合）
docs/       设计、分区、引导、设备证据
scripts/    可复现构建脚本
artifacts/  小体积交付产物
out/        镜像输出（gitignore，另有 SHA256SUMS）
downloads/  上游源码/rootfs（gitignore）
build/      编译工作区（gitignore）
logs/       构建日志（gitignore，关键证据归档到 docs/evidence/）
```

## 构建原则

- 参数集中在 `config/build.conf`；`VERSION_TITLE=Test`。
- 构建全部在主机侧完成，不自动写真机分区。
- 产物生成 SHA256 校验和并写入 git。
- 每个阶段完成后用 `build(pearl): ...` 提交。


## Test 构建结果（2026-10-13）

- 版本标题：`Test`，git tag：`Test`
- rootfs：`out/Test/pearl-linux-rootfs-Test.img`（10 GiB ext4）及 `.zst`
- boot：`artifacts/Test/boot_b-Test.img`、`artifacts/Test/vendor_boot_b-Test.img`
- 内核：`artifacts/kernel-7.2.9+/`（7.2.9+，pearl 专用，见 `docs/kernel-provenance.md`）
- 详细说明：`docs/TEST-BUILD.md`
- 刷写脚本默认拒绝执行；确认风险后使用 `scripts/flash-test.sh --yes`
