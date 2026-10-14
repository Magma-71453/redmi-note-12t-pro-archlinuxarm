# Pearl Linux kernel 7.2.10++（kernel #10，48-bit VA + reserve 修复）

Source: https://github.com/MT6895-Mainline/linux
Branch: 7.2-mt6895-xiaomi-pearl
Commit: a908b7825c7d619873392e5fbbcba2e54695d0eb

Build:

```bash
./scripts/kernel-build-gadget.sh
```

`kernel-build-gadget.sh` 会：

1. 强制 48-bit VA/PA（`CONFIG_ARM64_VA_BITS=48`、`PA_BITS=48`、LPA2 off），
   避免 52-bit VA 回退导致 `page_to_virt()` 错误 / panthor `clear_page` panic；
2. 幂等应用 `patches/0001-pearl-vulkan-ollama-stability.patch`：
   - reserve LK 内存窗口 `db870000-ed6dffff`（0x11e70000）与
     `bf6f0000-bf6fffff`（0x10000），避免 buddy 分配无线性映射的页；
   - `map_mem()` 打印/检查 `PEARL-MAP`；
   - CCCI `free_reserved_memory()` 不再释放 no-map/ccci-tag 窗口；
   - DTS `mblock-30-ccci_tag_mem` 去掉 `no-map`。

真机验证：`7.2.10++ #10`，qwen2.5:0.5b 与 phi4-mini-vk:3.8b
（`num_gpu=32`）连续推理，无 kernel panic/重启。MemTotal 约 7.0 GiB。

Config 为 `config`；内核内嵌 `mt6895-xiaomi-pearl.dtb` 并覆盖 LK FDT。
注意：本产物不含 `scripts/flash-*`；刷写参考仓库 `docs/`。
