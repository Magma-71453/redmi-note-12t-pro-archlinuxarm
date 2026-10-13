# Test 构建架构（已执行版本）

实际脚本顺序：

1. `scripts/20-kernel-assets.sh` — 校验 `artifacts/kernel-7.2.10++/`：
   `Image.gz`、`initramfs-final.cpio.lz4`、`pearl.dtb`、内嵌 `.config`。
2. `scripts/30-rootfs.sh` — 解压 ALARM aarch64 tarball，在
   `unshare -r -m` + `qemu-aarch64-static`(binfmt_misc) 中执行 pacman：
   - 包集合见 `config/build.conf`
   - 移除 generic `linux-aarch64`
   - 安装 docker/docker-compose、labwc、kitty、neovim、NetworkManager、openssh、
     mesa、zram-generator、earlyoom 等
   - 复制匹配的 `7.2.9+` 模块并 `depmod`
   - 运行 `rootfs-configure.sh`：用户、SSH、Docker、labwc/kitty/nvim、resize 服务
   - `pacman-key --init/populate`，恢复 `SigLevel = Required DatabaseOptional`
3. `scripts/40-image.sh` — 清理 build-only 文件，在 user namespace 中运行
   `mkfs.ext4 -L archpearl -d`，验证 inode uid=0 和 label，zstd 压缩。
4. `scripts/50-bootimg.sh` — 由仓库内内核资产重新 `mkbootimg` 生成
   `boot_b-Test.img`（header v4）和 `vendor_boot_b-Test.img`（vendor header v4 +
   DTB + ramdisk fragment），并校验与已知可启动 final-v4 字节级一致。
5. `scripts/60-finalize.sh` — 输出 `MANIFEST.txt`、包清单、SHA256SUMS-ALL。

## 已确认的构建事实

- 内核 release：`7.2.10++`（源码 pearl 分支；mainline 无 MT6895 DTS）
- rootfs：ext4，label `archpearl`，10 GiB 镜像约 4 GiB 数据
- initramfs-final 支持扫描 `/etc/mt6895-rootfs` 并挂载 ext4/f2fs
- Docker 内核前提：`OVERLAY_FS=y`、`VETH=y`、`BRIDGE=y`、
  `NF_NAT=y`、`IP_NF_TARGET_MASQUERADE=y`、`CGROUP_BPF=y`、`USER_NS=y`
- 桌面：tty1 autologin -> `.bash_profile` exec labwc -> autostart kitty
- 编辑器：`$EDITOR/$VISUAL=nvim`
