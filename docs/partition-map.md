# pearl 分区与双系统边界

只读侦察结果（`adb shell su -c 'cat /proc/partitions'` / `ls -l /dev/block/by-name`）：

| by-name | block | blocks(1K) | 大小 | 用途 |
|---|---|---:|---:|---|
| boot_a | /dev/block/sdc43 | 65536 | 64 MiB | 当前 Android 内核/ramdisk，保持 |
| boot_b | /dev/block/sdc72 | 65536 | 64 MiB | Linux Test 内核/initramfs，目标写入点 |
| userdata | /dev/block/sdc86 | 62485636 | ~59.6 GiB | Android 数据，保持不动 |
| linux | /dev/block/sdc88 | 174121984 | ~166 GiB | Linux rootfs |

`linux` 当前为 ext4 `LABEL=archpearl` `UUID=b7ae3de3-b7d9-4df6-a640-6d66cfa988da`，
旧 rootfs 只用约 5.24 GiB，剩 ~94 MiB，因此 Test 版本另建镜像，不直接在线安装。

## 槽位行为

- Android 当前 `ro.boot.slot_suffix=_a`。
- 本项目只写 `boot_b`，`boot_a` 不变。
- `userdata` 是 Android 加密数据，Linux 不应挂载/写入。
- 切槽和刷写命令需单独确认，见 `docs/boot_b.md`。
