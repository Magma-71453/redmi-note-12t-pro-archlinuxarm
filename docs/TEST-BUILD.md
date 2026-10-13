# Test 版本构建记录（pearl）

# pearl-linux Test manifest
version_title=Test
build_date_utc=2026-10-13T11:08:10Z
device=pearl
model=23054RA19C
soc=mt6895
arch=arm64
kernel_release=7.2.9+
kernel_asset=artifacts/kernel-7.2.9+
rootfs_image=pearl-linux-rootfs-Test.img
rootfs_image_size=10G
boot_image=boot_b-Test.img
vendor_boot_image=vendor_boot_b-Test.img
linux_partition=/dev/sdc88
boot_b_partition=/dev/sdc72
userdata_partition=/dev/sdc86 (READ-ONLY for Linux)
desktop=labwc
terminal=kitty
editor=neovim
containers=docker

> 说明：真机通过 ADB 识别为 `pearl` / MT6895，用户文字里的 `elish` 经核对是
> Xiaomi Pad 5 Pro (SM8250) 的代号。`/dev/sdc88`（linux）和 `/dev/sdc86`（userdata）
> 与真机 `by-name` 完全一致，因此按 pearl 真机构建。

## 产物

| 文件 | 大小 | SHA256 |
|---|---:|---|
| `out/Test/pearl-linux-rootfs-Test.img` | 10 GiB (约 4 GiB 实际数据) | `` |
| `out/Test/pearl-linux-rootfs-Test.img.zst` | ~850 MiB | `` |
| `out/Test/boot_b-Test.img` | 33,333,248 B | `` |
| `out/Test/vendor_boot_b-Test.img` | 13,316,096 B | `` |

`boot_b-Test.img` / `vendor_boot_b-Test.img` 由 `artifacts/kernel-7.2.9+/` 重新打包，
脚本 50 会校验它们与上一轮已知可启动的 `boot-pearl-linux-final-v4.img` /
`vendor_boot-pearl-linux-final.img` **逐字节一致**。

## 软件版本

- docker: 1:29.9.0-1
- docker-compose: 5.6.0-1
- labwc: 0.20.2-1
- kitty: 0.49.2-1
- neovim: 0.12.6-1
- networkmanager: 1.58.1-2
- openssh: 10.6p1-1
- systemd: 262-1
- zram-generator: 1.2.1-1
- earlyoom: 1.9.0-1

- 桌面：labwc 0.20.2（tty1 autologin 后直接 exec，不再使用 GDM/GNOME）
- 终端：kitty 0.49.2，会话启动自动打开；`$EDITOR/$VISUAL=nvim`
- 编辑器：neovim 0.12.6
- 容器：Docker 29.9.0 + docker-compose 5.6.0，`dockerd` / `containerd` 已 enable
- 服务器：OpenSSH、NetworkManager + systemd-resolved、zram-generator、earlyoom
- 软件源：`https://archlinuxarm.org/$arch/$repo`；已 `pacman-key --init` +
  `--populate archlinuxarm`，最终 `SigLevel = Required DatabaseOptional`

## 刷写与回退

不自动执行刷写。确认风险后运行 `scripts/flash-test.sh --yes`；该脚本会写
`linux`、`boot_b`、`vendor_boot_b`、`dtbo_b`、`vbmeta_b`，最后写 `misc` 把 B 槽设为
active+successful，不会触碰 `boot_a`、`vendor_boot_a`、`dtbo_a`、`vbmeta_a`、`super`、`userdata`。
回 Android：`scripts/restore-android-a.sh --yes`。

## 账号与首次启动

- 用户：`alarm`，密码见 out/Test/rootfs-password.txt；`root` 密码见 out/Test/rootfs-password.txt（**首次登录后请立即修改**）
- SSH 已开启，`PermitRootLogin yes` 仅为 Test 便利，生产前务必改掉
- 首次启动 systemd 会运行 `pearl-firstboot.service`，把 rootfs 在线扩容到整个 linux 分区
- 检查命令：`uname -a` 应显示 `7.2.9+ ... aarch64`；`docker run --rm hello-world`；
  `systemctl status docker sshd NetworkManager`

## 内核来源与重要限制

- mainline Linux 7.2.10 源码中 **没有 MT6895/pearl DTS**，直接编译的 7.2.10 不能在这里启动。
- 本 Test 使用真机 `boot_b` 中已存在的、上一轮 `pearl-armbian` 构建的 **7.2.9+ 专用内核**
  （内嵌 `.config` 含 `CONFIG_ARCH_MEDIATEK`、`CONFIG_PINCTRL_MT6895`、
  `CONFIG_COMMON_CLK_MT6895`、`CONFIG_SCSI_UFS_MEDIATEK`、`CONFIG_EXT4_FS=y` 等）。
- 内核源码树/补丁目录已丢失，`docs/kernel-provenance.md` 记录了二进制资产的 SHA256。
  若要从源码重编，需要先找回/重建 MT6895 驱动与 DTS 补丁。
- 本 Test 尚未在本轮实际重启真机验证；所有刷写都保留在原厂 A 槽回退范围内。
