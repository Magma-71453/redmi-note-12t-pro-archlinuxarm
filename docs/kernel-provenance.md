# Test 内核来源与真实性说明

## 为什么不是从 kernel.org 的 mainline 直接编译

`linux-7.2.10` mainline 源码（`arch/arm64/boot/dts/mediatek/`）里**没有 MT6895/pearl DTS**，
只有 `mt6893-pinfunc.h` / `mt6878-pinfunc.h`，也没有 MTK CCCI、CONFIG_MTK_IMGSENSOR 等
设备驱动。直接编译出的 Image 不可能在 Redmi Note 12T Pro 上启动。

真机 `boot_b` 中已有的内核自报：

```text
Linux version 7.2.9+ (root@Flaming-Penguin)
(clang version 23.1.1, LLD 23.1.1) #1 SMP PREEMPT
```

提取的内嵌 `.config` 显示这是为 MT6895 定制的 7.2.9 内核，包含：

```text
CONFIG_ARCH_MEDIATEK=y
CONFIG_MTK_IMGSENSOR_PLATFORM="MTK_PLATFORM"
CONFIG_PINCTRL_MT6895=y
CONFIG_COMMON_CLK_MT6895=y
CONFIG_MTK_IOMMU_MT6895=y
CONFIG_MTK_SCPSYS_MT6895=y
CONFIG_SCSI_UFS_MEDIATEK=y
CONFIG_MTK_COMBO_CHIP_CONSYS_6895=y
CONFIG_DRM_PANTHOR=y
CONFIG_EXT4_FS=y
CONFIG_F2FS_FS=y
```

该二进制与 `/usr/lib/modules/7.2.9+` 的 1544 个模块来自上一轮 `pearl-armbian`
构建（构建目录已不存在，但刷机包 `~/下载/pearl-刷机文件/` 中的
`boot-pearl-linux-final-v4.img` / `initramfs-final.cpio.lz4` /
`vendor_boot-pearl-linux-final.img` 是已知能启动的 final v4 版本）。

因此 Test 版本**沿用这个精确匹配硬件的 7.2.9+ 内核二进制与模块**，不重新编译一个
无法启动的 mainline 7.2.10。这样模块 vermagic、DTB、initramfs 和已存在的
`linux` 分区都精确匹配。

> 仍待补：该内核的原始源码树/补丁。当前构建目录已丢失，只保留了二进制、模块、
> DTB 和内核内嵌 config。后续如需从源码重编，需要先找回/重建 MT6895 驱动补丁。

## 2026-10-14 更新：7.2.10++（Test 实际运行内核）

- 源码：`https://github.com/MT6895-Mainline/linux`
- 分支：`7.2-mt6895-xiaomi-pearl`
- commit：`a908b7825c7d619873392e5fbbcba2e54695d0eb`
- 构建：`scripts/kernel-build-gadget.sh`（`build/linux-mt6895`）
- 配置：`artifacts/kernel-7.2.10++/config`
  - 以旧 `artifacts/kernel-7.2.9+/config` 为底
  - 合并 `arch/arm64/configs/pearl.config`：`CONFIG_MTK_DVFSRC=y`、
    `CONFIG_INTERCONNECT_MTK*`（MMQOS/EMI）等，修复显示组件长期
    `supplier soc@0:interconnect not ready` 导致 `mediatek-drm` 不注册的问题
  - USB：`CONFIG_USB_MTU3_GADGET=y`，关闭 DUAL_ROLE/HOST，保持 gadget-only
- 产物：`artifacts/kernel-7.2.10++/Image.gz`（内嵌 DTB，启动时覆盖 LK FDT）
- 运行时 `uname -r`：`7.2.10++`；rootfs 内模块目录仍为 `7.2.9+`，
  显示/存储/USB 等关键驱动为 built-in，Docker 已可用
