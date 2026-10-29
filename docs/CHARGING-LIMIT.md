# 充电上限与旁路供电（pearl）

> 设备实测于 2026-10-29，内核 7.2.10++ + `patches/0002-pearl-mt6375-charge-behaviour.patch`。
> 目标：电池不长期满电（80% 上限），并支持「插电停充、VBUS 直供」的旁路供电模式。

## 1. 为什么必须改内核

本机充电 IC 是 **MT6375**（`mt6375-chg` 驱动，power_supply 名 `mtk-master-charger`），
电量计是 **bq28z610**（`bq28z610-0`）。

设备树里该节点带 `mediatek,tcpm-managed;`，驱动因此进入 **TCPM 托管模式**：

- `mt6375_chg_property_is_writeable()` 在托管模式下对所有属性返回 0
  （`mt6375-charger.c` 中 `if (ddata->tcpm_managed) return 0;`），
  → `/sys/class/power_supply/mtk-master-charger/*` 全部是 **0444 只读**，用户态没有任何充电开关。
- 用户态绕过驱动、直接经 `/dev/i2c-5` 写 `CHG_TOP1` bit0 虽然能立刻停充，但**实测 8 秒后被驱动改回**
  （TCPM 在插线/限流变更时走 `mt6375_tcpm_apply_sink()` 重新打开充电）。
  所以纯用户态方案不可靠。

结论：在 `/lib/modules` 只有 7.2.9+、运行内核是 7.2.10++ 的情况下也装不了外部模块，
**必须重编内核**。

## 2. 内核侧改了什么

`patches/0002-pearl-mt6375-charge-behaviour.patch`，只动两个文件：

| 文件 | 改动 |
|---|---|
| `drivers/power/supply/mediatek/mt6375-charger.c` | 新增 `bool charge_inhibited`；props 增加 `POWER_SUPPLY_PROP_CHARGE_BEHAVIOUR`；`psy_desc.charge_behaviours` 开放 AUTO\|INHIBIT_CHARGE；get/set property 新 case；`property_is_writeable` 对该属性**先于** tcpm 早退返回 1 |
| `drivers/power/supply/mediatek/mt6375-tcpm.h` | 新增 `mt6375_tcpm_inhibit_charge()`；`mt6375_tcpm_apply_sink()` 首行尊重 `charge_inhibited` |

产生的 sysfs 接口：

```
/sys/class/power_supply/mtk-master-charger/charge_behaviour
```

- 可写：`auto` / `inhibit-charge`（其它值返回 EINVAL）
- 读回：`[auto] inhibit-charge` 或 `auto [inhibit-charge]`（方括号是当前值）
- 权限：`rw-r--r--`（写需要 root）

### 关键坑：停充 ≠ 旁路（实测数据）

TCPM 原本的 `mt6375_tcpm_stop_sink()` 会把 `F_CHG_EN` 和 `F_BUCK_EN` **都清 0**。
在 pearl 上这会让整机**由电池供电**，插着充电器也在放电：

| CHG_EN | BUCK_EN | 电池电流 | 结果 |
|---|---|---|---|
| 1 | 1 | +713 mA | 正常充电 |
| **0** | **0** | **-275 mA 持续** | 充不上也供不上（错误） |
| **0** | **1** | +713 mA → **0 uA**，状态 `Not charging` | **真正的旁路供电** |

所以 `mt6375_tcpm_inhibit_charge()` 特意 **只关 CHG_EN、保留 BUCK_EN=1**，
让系统由 VBUS 供电、电池电流收敛到 0。这是本补丁与「直接调用 stop_sink」的本质区别。

## 3. 用户态

| 文件 | 作用 |
|---|---|
| `config/rootfs/usr/local/bin/pearl-charge-limit.py` | 常驻守护：80% 上限 + 旁路执行者 |
| `config/rootfs/usr/local/bin/pearl-bypass` | `on\|off\|status` 旁路开关 |
| `config/rootfs/etc/systemd/system/pearl-charge-limit.service` | `Restart=always` |

策略：电量 **≥80% 停充**，**≤75% 恢复**，中间 5% 回差防止阈值附近反复启停；
旁路供电**优先于** 80% 逻辑。状态存 `/var/lib/pearl-charge/state.json`。

```bash
sudo pearl-bypass on      # 插电即停充，系统由 VBUS 供电
sudo pearl-bypass off     # 回到 80% 上限逻辑
sudo pearl-bypass status
systemctl status pearl-charge-limit
journalctl -u pearl-charge-limit -f
```

属性不存在时（旧内核）守护只记一条日志并每 30 秒重试，不会崩溃刷屏。

## 4. 实测结果（设备 192.168.7.204）

```
# 92% > 80%，守护自动停充
pearl-charge-limit: cap=92 status=Charging online=1 behaviour=auto bypass=off
  | 写入 auto -> inhibit-charge | 电量 92% >= 80% 且正在充电 -> 停充

# 电流收敛到 0（旁路而非放电）
t+10s  ibat=221000uA Charging
t+60s  ibat=     0uA Not charging     <- 收敛
t+90s  ibat=     0uA Not charging

# 恢复 auto 立刻充回
after auto: ibat=762000uA Charging
```

## 5. 构建与刷写

```bash
source build/llvm-env.sh
scripts/kernel-build-gadget.sh        # 自动应用 patches/0001 + 0002
scripts/50-bootimg-newkernel.sh       # 产出 out/Test/avb/boot_b-Test-avb.img
# 刷 write:
dbclient ... 'sudo dd if=boot_b-new.img of=/dev/disk/by-partlabel/boot_b bs=1M conv=fsync'
```

## 6. 回滚

设备上已预置原始镜像与脚本：

```bash
sudo /root/recovery/rollback-boot.sh      # 校验 a6efd4ca… 后写回原始 boot_b
```

本机备份在 `build/boot-backup/`（boot_b / vendor_boot_b / dtbo_b / vbmeta_b / boot_a，含 SHA256SUMS）。

> kexec 免刷机验证在本机上**不可行**：`kexec -e` 后设备起不来（initramfs 依赖 LK 传入的
> `debug_ext.initrd_size`，kexec 自建 FDT 绕过了这段）。必须走刷 boot_b 的正路。
