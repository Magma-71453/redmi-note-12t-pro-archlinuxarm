# Test 内核来源与真实性说明

> 当前 Test 内核：**7.2.10++**（pearl 分支，见文件末尾更新）。
> 下文 7.2.9+ 描述为早期基线/历史来源，保留用于追溯。

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
  - 以旧 7.2.9+ 基线 config（已不在当前树，见 git 历史）为底
  - 合并 `arch/arm64/configs/pearl.config`：`CONFIG_MTK_DVFSRC=y`、
    `CONFIG_INTERCONNECT_MTK*`（MMQOS/EMI）等，修复显示组件长期
    `supplier soc@0:interconnect not ready` 导致 `mediatek-drm` 不注册的问题
  - USB：`CONFIG_USB_MTU3_GADGET=y`，关闭 DUAL_ROLE/HOST，保持 gadget-only
- 产物：`artifacts/kernel-7.2.10++/Image.gz`（内嵌 DTB，启动时覆盖 LK FDT）
- 运行时 `uname -r`：`7.2.10++`；rootfs 内模块目录仍为 `7.2.9+`，
  显示/存储/USB 等关键驱动为 built-in，Docker 已可用

### 2026-10-14 开机静默与桌面自启

- `arch/arm64/kernel/setup.c` 不再追加 `ignore_loglevel`，改为追加
  ` quiet loglevel=3`，避免启动时刷屏；完整日志仍由
  `pearl-debug-log.service` 写入 expdb。
- 内核 boot 镜像重新打包为 `artifacts/Test/boot_b-Test.img` / `out/Test/avb/boot_b-Test-avb.img`。
- 桌面启动改为 systemd 服务 `pearl-labwc.service`（`/etc/systemd/system/`），
  不再依赖 getty autologin + `.bash_profile`；`getty@tty1.service` 已禁用。
- 实测启动：kernel ~9.9s + userspace ~6.0s ≈ 15.9s。

### 2026-10-14 suspend / USB 更新

- USB 恢复 `CONFIG_USB_MTU3_DUAL_ROLE=y`（`GADGET`/`HOST` 由 dual-role 管理），
  `mt6375-tcpc` 正常注册，充电和 USB-C 扩展坞 host 模式恢复；
  ttyGS0 gadget 服务默认禁用。
- `mtk-spmi-keys` 增加 PMIC IRQ + `enable_irq_wake`，电源键可作为 s2idle 唤醒源。
- 尝试让 `mtk_drm_sys_suspend` 始终保存/恢复 DRM atomic state，但 mainline
  DSI/OVL resume 后仍会 underrun、面板白屏；因此 `systemctl suspend` 改为
  `pearl-sleep` 安全熄屏方案（不进入内核 suspend）。
