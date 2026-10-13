# Pearl Test 桌面布局（labwc）

布局按 `图片.kra` 的 A/B/C/D 分区实现，屏幕 1080x2460：

| 区域 | 位置（像素） | 内容 |
| --- | --- | --- |
| C | 顶部左侧 0..540 x 0..560 | WiFi SSID/信号/状态 + wlan0 实时上下行速率/累计流量；点击打开 `nmtui` |
| D | 顶部右侧 540..1080 x 0..560 | CPU Top2 进程、功耗 W、电量 %、预计续航；点击打开 `top` |
| B | 中部 0..1080 x 560..1744 | kitty 终端，启动即最大化，font_size=22；fastfetch 配置为无 logo，完整显示 |
| A | 底部 0..1080 x 1744..2460 | wvkbd-mobintl 虚拟键盘，`-H 716` |

## 组件

- **labwc 0.20.2**：Wayland 合成器，由 tty1 autologin 的 `.bash_profile` 启动。
- **pearl-panel**：本仓库 `src/pearl-panel/pearl-panel.c`，Wayland layer-shell 面板，
  请求顶部 560px exclusive zone；每秒刷新 WiFi/CPU/电源数据。
- **kitty**：`--single-instance --start-as=maximized`；字体 22，避免 fastfetch 被裁切。
- **wvkbd-mobintl**：`scripts/build-wvkbd-arm64.sh` 交叉编译；底部 716px。
- **nmtui**：点击 C 区后在 kitty 中打开的 NetworkManager TUI。
- **fastfetch**：配置 `config/rootfs/home/alarm/.config/fastfetch/config.jsonc`，
  `logo.type=none` + 紧凑模块列表，22pt 下所有信息行完整显示。

## 电源键

- `/usr/local/bin/pearl-powerkey.py` 监听 `mtk-kpd` (`/dev/input/event0`) 的 `KEY_POWER`，
  按下时调用 `wlopm --toggle DSI-1`，只熄灭/点亮屏幕，不关机。
- `/etc/systemd/logind.conf.d/10-pearl-power.conf` 设置 `HandlePowerKey=ignore`，
  防止 systemd-logind 默认触发 `poweroff`。
- 需要关机时使用终端命令 `poweroff`（或 `systemctl poweroff`）。

## 启动

- `pearl-labwc.service` 由 systemd 直接以 alarm 用户在 tty1 启动 labwc，
  带 `PAMName=login` 的 seat0 会话；`getty@tty1.service` 已禁用。
- labwc autostart 依次启动 `pearl-panel`、`wvkbd`、`kitty`。
- 内核 cmdline 追加 `quiet loglevel=3`（不再追加 `ignore_loglevel`），
  启动约 16s，无滚屏日志。
- USB gadget 仍提供 ttyGS0 上的 root bash；Wi-Fi 上 sshd 提供 `alarm`/`root` 登录。

## suspend / 休眠

- `systemctl suspend` 已通过
  `/etc/systemd/system/systemd-suspend.service.d/10-pearl-safe-suspend.conf`
  重定向到 `/usr/local/bin/pearl-sleep`：
  - 调用 `wlopm --off DSI-1` 熄屏；
  - 将 CPU governor 切到 powersave；
  - **不进入** `mem`/s2idle，因此不会触发 mainline DSI resume 的白屏问题；
  - RAM、进程、数据全部保留。
- 按电源键由 `pearl-powerkey.py` 调用 `wlopm --on DSI-1` 亮屏，并把 governor
  恢复为 schedutil。
- **不要**直接执行 `echo mem > /sys/power/state`：当前 mainline 显示驱动
  resume 后 DSI/OVL 会 underrun，面板可能变白，需要 reboot/断电复位。
- ttyGS0（USB gadget 控制台）已禁用：
  `systemctl enable --now pearl-usb-gadget.service pearl-usb-console.service`
  可临时恢复；内核已改为 dual-role，正常情况建议保持关闭，以免影响
  充电和 USB 扩展坞。
