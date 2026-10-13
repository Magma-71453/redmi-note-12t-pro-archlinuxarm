# boot_b 引导设计（待实机验证）

## 目标

- `boot_a`：Android，保持原样，继续使用 `/dev/sdc86` userdata。
- `boot_b`：Linux Test，7.2.x 内核 + initramfs，挂载 `/dev/sdc88`（PARTLABEL=linux）为根。

## initramfs /init 逻辑

1. 挂载 `/proc`、`/sys`、`/dev`。
2. 扫描 `/sys/class/block/*/uevent` 找 `PARTNAME=linux`；解析出块设备名。
3. `mount -t ext4 -o rw,noatime <dev> /newroot`；失败时回退 LABEL=archpearl、/dev/sdc88。
4. 确认 `/newroot/usr/lib/systemd/systemd` 存在。
5. `switch_root /newroot /usr/lib/systemd/systemd`。

## 刷写（未执行，必须用户确认）

```bash
fastboot getvar current-slot
fastboot flash boot_b out/Test/boot_b.img
fastboot --set-active=b
fastboot reboot
```

## 回退 Android

```bash
fastboot --set-active=a
fastboot reboot
```

注意：不执行 `fastboot erase`、不刷 `super/userdata/vbmeta`。
