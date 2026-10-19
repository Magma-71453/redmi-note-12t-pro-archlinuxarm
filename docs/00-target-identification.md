# 目标识别记录

用户文字：Redmi Note 12 T Pro，代号写作 `elish`，分区 `/dev/sdc88:linux`、`/dev/sdc86:userdata`，
Android 使用 `boot_a` 引导并挂载 userdata，希望 `boot_b` 引导 Linux。

ADB 只读读数：

```text
ro.product.device          = pearl
ro.product.model           = 23054RA19C
ro.product.name            = lineage_pearl
ro.board.platform          = mt6895
ro.hardware                = mt6895
ro.boot.slot_suffix        = _a
ro.boot.verifiedbootstate  = orange
ro.build.ab_update         = true
```

符号链接：

```text
boot_a   -> /dev/block/sdc43
boot_b   -> /dev/block/sdc72
linux    -> /dev/block/sdc88
userdata -> /dev/block/sdc86
```

