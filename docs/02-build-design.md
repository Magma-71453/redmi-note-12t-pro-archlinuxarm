# Test 构建设计

1. `01-fetch.sh`：下载 Linux 7.2.x 与 Arch Linux ARM aarch64。
2. `02-kernel.sh`：交叉编译 7.2.x aarch64 内核、模块、DTB，生成 `Image`。
3. `03-rootfs.sh`：基于 ALARM，用 qemu-user + 用户命名空间 binfmt_misc chroot，
   安装服务器包，启用 sshd/networkd/docker，写 labwc/kitty/neovim 配置。
4. `04-initramfs.sh`：生成最小 initramfs，扫描 PARTNAME=linux。
5. `05-image.sh`：`mkfs.ext4 -d` 生成 rootfs.img，`mkbootimg` 生成 boot_b.img。
6. `06-finalize.sh`：manifest、SHA256SUMS、日志归档、git commit。

主机侧依赖（已确认存在）：`git gcc aarch64-linux-gnu-gcc clang qemu-aarch64-static mkbootimg
cpio fakeroot unshare bwrap`。

## 内核策略

先使用官方 mainline 7.2.10，检查 `arch/arm64/boot/dts/mediatek/` 是否有 `mt6895` 及 pearl；
若缺失，则使用 MT6895 基础 DTS + pearl 板级覆盖，并把失败/待验证点如实记录，不冒充可启动。
