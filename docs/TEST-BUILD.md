# Test 构建与刷写说明（当前：7.2.10++）

## 产物

- Rootfs：`out/Test/pearl-linux-rootfs-Test.img` / `.zst`
- Boot AVB：`out/Test/avb/boot_b-Test-avb.img`
- Vendor boot AVB：`out/Test/avb/vendor_boot_b-Test-avb.img`
- 内核资产：`artifacts/kernel-7.2.10++/`（`Image.gz`、`config`、initramfs、DTB）
- 汇总：`out/Test/MANIFEST.txt`、`out/Test/SHA256SUMS-ALL`
- 同步到：`artifacts/Test/`

## 账号与首次启动

- 默认用户：`alarm`；root 与 alarm 的初始密码由构建时生成，保存在
  `out/Test/rootfs-password.txt`（gitignore，不提交）。
- 也可用 `ROOTFS_PASSWORD='自定义' scripts/30-rootfs.sh` 指定。
- 首次启动后请立即执行 `passwd` / `passwd root` 修改密码，再接入不可信网络。
- SSH：`PermitRootLogin yes`，仅为 Test 便利；生产环境请收紧。
- 首次启动 `pearl-firstboot.service` 会把 rootfs 扩容到整个 linux 分区。

## 刷写与回退

不自动执行刷写。确认风险后运行 `scripts/flash-test.sh --yes`；脚本会写
`linux`、`boot_b`、`vendor_boot_b`、`dtbo_b`、`vbmeta_b` 并写 `misc` 把 B 槽设为
active+successful。**受保护分区（lk/md1img/nv/userdata/super 等）不会被写**。
回 Android：`scripts/restore-android-a.sh --yes`。

## 当前系统状态（Test）

- `uname -r`：`7.2.10++`
- 桌面：labwc + kitty(font 22) + wvkbd(-H 716) + `pearl-panel` 四区布局
- 显示：`mediatek-drm card0` + DSI-1 connected；`/dev/dri/card1` 为 Mali panthor
- Docker/containerd：active，overlay2 可用
- USB：ttyGS0 上 root bash；Wi-Fi SSH 可用
- 电源键：短按切换 DPMS（熄屏/亮屏），不关机；关机用 `poweroff`

## 内核来源与限制

- 源码：`https://github.com/MT6895-Mainline/linux`
- 分支：`7.2-mt6895-xiaomi-pearl`
- commit：`a908b7825c7d619873392e5fbbcba2e54695d0eb`
- 配置：`artifacts/kernel-7.2.10++/config`；根 rootfs 内模块目录仍为 `7.2.9+`，
  关键驱动（显示、UFS、USB gadget、Docker 依赖）为 built-in。
- mainline 7.2.10 没有 pearl DTS，不能直接用 mainline 源码启动；必须使用上述分支。
