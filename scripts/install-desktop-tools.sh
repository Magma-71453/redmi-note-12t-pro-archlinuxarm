#!/usr/bin/env bash
# Install pearl desktop configs/tools into the rootfs build tree.
set -euo pipefail
REPO="$(cd "$(dirname "$0")/.." && pwd)"
R="$REPO/build/rootfs-Test"
CFG="$REPO/config/rootfs"
install -d "$R/home/alarm/.config/fastfetch" "$R/home/alarm/.config/kitty" "$R/home/alarm/.config/labwc"
install -d "$R/etc/systemd/system/multi-user.target.wants" "$R/etc/systemd/logind.conf.d" "$R/usr/local/bin"
install -m644 "$CFG/home/alarm/.config/fastfetch/config.jsonc" "$R/home/alarm/.config/fastfetch/config.jsonc"
install -m644 "$CFG/home/alarm/.config/kitty/kitty.conf"        "$R/home/alarm/.config/kitty/kitty.conf"
install -m755 "$CFG/home/alarm/.config/labwc/autostart"         "$R/home/alarm/.config/labwc/autostart"
install -m755 "$CFG/usr/local/bin/pearl-powerkey.py"            "$R/usr/local/bin/pearl-powerkey.py"
install -m644 "$CFG/etc/systemd/system/pearl-powerkey.service"  "$R/etc/systemd/system/pearl-powerkey.service"
install -m644 "$CFG/etc/systemd/system/pearl-usb-console.service" "$R/etc/systemd/system/pearl-usb-console.service" 2>/dev/null || true
install -m644 "$CFG/etc/systemd/system/pearl-usb-gadget.service"  "$R/etc/systemd/system/pearl-usb-gadget.service" 2>/dev/null || true
install -m644 "$CFG/etc/systemd/logind.conf.d/10-pearl-power.conf" "$R/etc/systemd/logind.conf.d/10-pearl-power.conf"
ln -sfn /etc/systemd/system/pearl-powerkey.service "$R/etc/systemd/system/multi-user.target.wants/pearl-powerkey.service"
echo "installed pearl desktop configs into $R"
