# pearl-linux Test 交付产物（kernel #10 / Vulkan-Ollama 稳定版）

- `boot_b-Test.img` — Android boot v4，Linux `7.2.10++`（48-bit VA + reserve
  修复）+ initramfs-final
- `vendor_boot_b-Test.img` — vendor_boot v4，pearl DTB + permissive cmdline +
  initramfs fragment
- `../kernel-7.2.10++/` — 内核 `Image.gz`、`pearl.dtb`、config、initramfs 与
  `SHA256SUMS`（补丁见仓库 `patches/`）
- `MANIFEST.txt`、`SHA256SUMS-ALL`、`packages-*.txt` — 版本/校验/包清单
- rootfs 原始 10G ext4 与 zst 压缩镜像体积原因放在 `out/Test/`；
  校验和见 `rootfs-image-SHA256SUMS`

## GPU / Ollama

- `vulkan-panfrost`（Mesa PanVK）+ 自编译 Ollama v0.40.4 / llama.cpp b11521
- `ollama run qwen2.5:0.5b`：默认 100% GPU，约 10 tokens/s
- `phi4-mini:3.8b` 默认全 offload 会触发 PanVK `INSTR_BARRIER_FAULT`；
  用 `ollama-vk-models` 创建 `phi4-mini-vk:3.8b`（`num_gpu=32`）后运行
- 详见 `docs/GPU-VULKAN-OLLAMA.md`

## 刷写顺序（需用户显式确认后执行）

```bash
scripts/flash-test.sh --yes
```

脚本写 `linux`、`boot_b`、`vendor_boot_b`、`dtbo_b`、`vbmeta_b`，最后写
`misc` 把 B 槽设为 active+successful；不会触碰 A 槽与 `userdata`。

## 回退 Android

```bash
scripts/restore-android-a.sh --yes
```
