# boot_b 引导设计（Test 已打包，待实机刷写验证）

## 目标与实现

- `boot_a`：Android，保持原样，继续挂载 `/dev/sdc86` userdata。
- `boot_b`：Linux Test，内核 7.2.9+ + initramfs-final，挂载 `/dev/sdc88` 的
  `/etc/mt6895-rootfs` 分区为根（当前 rootfs label=`archpearl`，ext4）。
- `vendor_boot_b`：提供 pearl DTB，vendor cmdline 为
  `bootopt=64S3,32N2,64N2 androidboot.selinux=permissive`。

## 产物

- `artifacts/Test/boot_b-Test.img`
  sha256 `e34ae45d3f0cc19dfc72e24e9dfe4927f5f1317fe269f675fb18ddb135734fde`
- `artifacts/Test/vendor_boot_b-Test.img`
  sha256 `0711787da078283c41b6c5277d1c211ee59e142e28ddf7ea8e1eca196b5cb26e`

两者与上一轮已验证的 final-v4 镜像逐字节一致。

## 刷写（必须用户确认后执行）

```bash
scripts/flash-test.sh --yes
```

脚本刷 `linux`、`boot_b`、`vendor_boot_b`、`dtbo_b`、`vbmeta_b`，
最后刷 `misc` 把 slot B 设为 active+successful。
不会触碰 `boot_a`、`vendor_boot_a`、`dtbo_a`、`vbmeta_a`、`super`、`userdata`。

## 回退 Android

```bash
scripts/restore-android-a.sh --yes
```
