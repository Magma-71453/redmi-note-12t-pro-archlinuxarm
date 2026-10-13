# pearl-linux Test 交付产物

- `boot_b-Test.img` — Android boot v4，Linux 7.2.9+ 内核 + initramfs（与上一轮已验证 final-v4 字节级一致）
- `vendor_boot_b-Test.img` — vendor_boot v4，pearl DTB + permissive cmdline + initramfs fragment
- `../kernel-7.2.9+/` — 内核 Image.gz、initramfs、pearl.dtb、内嵌 config、SHA256SUMS
- `MANIFEST.txt`、`SHA256SUMS-ALL`、`packages-pacmanQ-Test.txt` — 版本/校验/包清单
- rootfs 原始 10G ext4 镜像由于体积原因放在 `out/Test/`，校验和见 `rootfs-image-SHA256SUMS`

## 刷写顺序（需用户显式确认后执行）

```bash
scripts/flash-test.sh --yes
```

脚本写 `linux`、`boot_b`、`vendor_boot_b`、`dtbo_b`、`vbmeta_b`，最后写 `misc` 把 B 槽设为
active+successful；不会触碰 `boot_a`、`vendor_boot_a`、`dtbo_a`、`vbmeta_a`、`super`、`userdata`。

## 回退 Android

```bash
scripts/restore-android-a.sh --yes
```
