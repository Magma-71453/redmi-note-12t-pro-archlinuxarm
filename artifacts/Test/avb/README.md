# Test AVB boot images

由 `scripts/55-bootimg-avb.sh` 生成，使用与原厂相同的结构：

- Android boot header v4
- `boot_b`：os_version `16.0.0`，os_patch_level `2025-10`
- AVB hash footer，`Algorithm: NONE`，pad 到 64 MiB
- partition_name：`boot` / `vendor_boot`

```text
out/Test/avb/boot_b-Test-avb.img           (64 MiB)
out/Test/avb/vendor_boot_b-Test-avb.img    (64 MiB)
```

这两个是一期调试的重点：原厂 `boot_b`/`vendor_boot_b`/`dtbo_b` 都带 AVB footer，
之前 Test 的小镜像没有 footer，且刷写时没先擦分区，容易留下原厂 AVB footer/尾数据，
可能让 LK 直接复位到 Preloader。
