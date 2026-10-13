# pearl Linux boot debug 记录

## 现象

刷入 Test Linux B 槽后重启，屏幕黑，设备很快回到 MTK Preloader/BROM 循环，
说明 LK/preloader 阶段就没有顺利交接给 kernel，而不是 Linux userland 问题。

## 原厂与 Test 镜像的关键差异

原厂 B 槽 dump（`~/下载/pearl-刷机文件/3-原厂分区备份/`）：

| 分区 | 形态 |
|---|---|
| `boot_b` | 64 MiB 分区，Android boot header v4，尾部 AVB hash footer（`Algorithm: NONE`） |
| `vendor_boot_b` | 64 MiB 分区，vendor_boot header v4，尾部 AVB hash footer |
| `dtbo_b` | 32 MiB 分区，尾部 AVB hash footer |
| `vbmeta_b` | 8 MiB，AVB0 header，包含 boot / vbmeta_system / vbmeta_vendor 链 |
| `misc` | 4 MiB，A/B slot BCB |

之前 Test 刷写流程的问题：

1. `boot_b` 只有 33 MB、`vendor_boot_b` 只有 13 MB，镜像**没有 AVB footer**；
2. `fastboot flash` 只覆盖分区开头，分区尾部仍残留原厂 `AVBf`/旧数据；
3. `vbmeta_b` 写的是 4K disabled 镜像，8 MiB 分区尾部可能残留原厂 vbmeta 链；
4. 没有先 `fastboot erase` B 槽 boot 相关分区。

这会让 MTK LK 读到的 boot/vendor_boot 与尾部 AVB 元数据不一致，进而复位到
Preloader/BROM。用户“先清空 B 槽缓存”的判断是正确的。

## 新流程

`scripts/flash-test.sh --yes` 现在默认：

```text
erase boot_b vendor_boot_b dtbo_b vbmeta_b vbmeta_system_b vbmeta_vendor_b misc
flash boot_b         out/Test/avb/boot_b-Test-avb.img           (64M + AVB footer)
flash vendor_boot_b  out/Test/avb/vendor_boot_b-Test-avb.img    (64M + AVB footer)
flash dtbo_b         ~/下载/.../2-Linux启动-slotB/dtbo_b-stock.img (32M 原厂)
flash vbmeta_b       ~/下载/.../vbmeta_b-disabled-8m.img        (8M disabled)
flash vbmeta_system_b/vbmeta_vendor_b disabled + pad to partition
flash linux          out/Test/pearl-linux-rootfs-Test.img       (10G ext4)
flash misc           ~/下载/.../misc-slot-b.img                 (最后写)
```

`boot_b` / `vendor_boot_b` 的 AVB footer 由 `scripts/55-bootimg-avb.sh`
使用 `avbtool add_hash_footer --algorithm NONE` 生成，固定 salt，结构对齐原厂；
`out/Test/avb/SHA256SUMS` 记录校验和。

## 调试顺序

1. Android A 槽正常启动后，`adb reboot bootloader` 进入 fastboot。
2. 先运行 `scripts/capture-fastboot-debug.sh`：
   - `fastboot getvar all`
   - slot 状态 / 分区大小
   - `fastboot oem dump_pllk_log`
   - `fastboot fetch` 当前 boot_b/vendor_boot_b/dtbo_b/vbmeta_b/misc/boot_para/expdb/oops
3. 先测 B 槽是否健康：
   ```bash
   scripts/flash-test.sh --yes --stock-b
   ```
   如果原厂 B 槽也复位到 Preloader，说明不是 Test Linux 镜像的问题，而是 B 槽/AB 元数据/AVB 链问题。
4. 再刷 Test Linux：
   ```bash
   scripts/flash-test.sh --yes
   ```
5. 如果仍失败：
   - 重新进 fastboot，执行 `scripts/capture-fastboot-debug.sh`；
   - 如果只有 Preloader：关机后不按键插线，执行
     `scripts/read-mtk-debug.sh --wait`，读取 `expdb`/`oops`；
   - 重点检查 LK log 中的 `AVB`、`vbmeta`、`dtbo`、`boot`、`load`、`verify` 错误。

## 回退 Android A

```bash
scripts/restore-android-a.sh --yes
```
