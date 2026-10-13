#!/usr/bin/env bash
# 在 chroot 内执行：配置首次启动后的 Test 系统。
set -euo pipefail
export LANG=C.UTF-8

VERSION_TITLE="Test"
BUILD_ID="$(date -u +%Y%m%dT%H%M%SZ)"

# ----- 基础身份 -----
echo pearl > /etc/hostname
cat > /etc/hosts <<'HOSTS'
127.0.0.1   localhost
::1         localhost
127.0.1.1   pearl.localdomain pearl
HOSTS
ln -sfn /usr/share/zoneinfo/Asia/Shanghai /etc/localtime
hwclock --systohc --utc 2>/dev/null || true
sed -i 's/^#\s*\(en_US\.UTF-8 UTF-8\)/\1/' /etc/locale.gen
sed -i 's/^#\s*\(zh_CN\.UTF-8 UTF-8\)/\1/' /etc/locale.gen
locale-gen >/dev/null
printf 'LANG=en_US.UTF-8\n' > /etc/locale.conf
printf 'KEYMAP=us\n' > /etc/vconsole.conf

# initramfs-final 用它识别可挂载的 Linux rootfs 分区
cat > /etc/mt6895-rootfs <<RELEASE
Redmi Note 12T Pro (pearl) Linux rootfs marker
version=${VERSION_TITLE}
build=${BUILD_ID}
RELEASE
cat > /etc/pearl-linux-release <<RELEASE
NAME="pearl-linux"
VERSION="${VERSION_TITLE}"
ID=pearl-linux
PRETTY_NAME="pearl-linux Test (Arch Linux ARM, 7.2.9+ kernel)"
HOME_URL="https://archlinuxarm.org/"
BUILD_DATE="${BUILD_ID}"
RELEASE
cp -f /etc/pearl-linux-release /etc/os-release
printf '\npearl-linux Test build %s\n' "$BUILD_ID" >> /etc/motd

# ----- 文件系统与首次启动扩容 -----
cat > /etc/fstab <<'FSTAB'
# <file system> <dir> <type> <options> <dump> <pass>
LABEL=archpearl  /      ext4  rw,noatime,errors=remount-ro  0 1
tmpfs            /tmp   tmpfs rw,nosuid,nodev,noexec,relatime,size=2G 0 0
FSTAB
cat > /usr/local/sbin/pearl-firstboot <<'FIRSTBOOT'
#!/usr/bin/bash
set -euo pipefail
/usr/bin/logger -t pearl-firstboot "starting"
rootdev="$(/usr/bin/findmnt -n -o SOURCE / || true)"
if [ -n "$rootdev" ] && [ -b "$rootdev" ]; then
  /usr/sbin/resize2fs "$rootdev" 2>&1 | /usr/bin/logger -t pearl-firstboot || true
fi
/usr/bin/touch /var/lib/pearl-firstboot.done
/usr/bin/logger -t pearl-firstboot "done"
FIRSTBOOT
chmod 755 /usr/local/sbin/pearl-firstboot
cat > /etc/systemd/system/pearl-firstboot.service <<'UNIT'
[Unit]
Description=Resize pearl root filesystem to fill linux partition
DefaultDependencies=no
After=local-fs.target
Before=docker.service
[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/usr/local/sbin/pearl-firstboot
[Install]
WantedBy=multi-user.target
UNIT
systemctl enable pearl-firstboot.service

# ----- 用户与 SSH -----
# ALARM tarball 自带 uid=1000 的 alarm 用户；Test 直接使用它，避免 useradd 在
# 无映射 uid 的 user namespace 中失败。
PRIMARY_USER=alarm
id -u "$PRIMARY_USER" >/dev/null 2>&1 || useradd -M -u 1000 -U -s /usr/bin/bash "$PRIMARY_USER"
usermod -aG wheel,docker,video,audio,input "$PRIMARY_USER" 2>/dev/null || true
mkdir -p "/home/$PRIMARY_USER"
rm -f "/home/$PRIMARY_USER/$PRIMARY_USER"   # 清理早期脚本误建的 self symlink
cp -a /etc/skel/. "/home/$PRIMARY_USER/" 2>/dev/null || true
# initramfs-final 会尝试修正 /home/alarm 属主；保留一个兼容符号链接
ln -sfn "/home/$PRIMARY_USER" /home/mobian
printf '%s:pearl\nroot:CHANGE_ME_AT_BUILD\n' "$PRIMARY_USER" | chpasswd
cat > /etc/tmpfiles.d/pearl-home.conf <<'TMPFILES'
Z /home/alarm 0755 1000 1000 -
z /var/lib/docker 0710 root docker -
TMPFILES
mkdir -p /etc/ssh/sshd_config.d
cat > /etc/ssh/sshd_config.d/10-pearl-test.conf <<'SSH'
PermitRootLogin yes
PasswordAuthentication yes
KbdInteractiveAuthentication no
UseDNS no
SSH
# 首次启动前生成一次 host key（chroot 里可能失败，sshd 首次启动会再生成）
ssh-keygen -A 2>/dev/null || true

# ----- Docker -----
mkdir -p /etc/docker /etc/modules-load.d /etc/sysctl.d
cat > /etc/docker/daemon.json <<'DOCKER'
{
  "log-driver": "journald",
  "iptables": true,
  "ip-forward": true,
  "storage-driver": "overlay2",
  "data-root": "/var/lib/docker"
}
DOCKER
cat > /etc/modules-load.d/90-docker-pearl.conf <<'MODULES'
overlay
br_netfilter
veth
bridge
xt_conntrack
MODULES
cat > /etc/sysctl.d/90-docker-pearl.conf <<'SYSCTL'
net.ipv4.ip_forward = 1
net.bridge.bridge-nf-call-iptables = 1
net.bridge.bridge-nf-call-ip6tables = 1
fs.inotify.max_user_watches = 524288
SYSCTL

# ----- zram / OOM -----
cat > /etc/systemd/zram-generator.conf <<'ZRAM'
[zram0]
zram-size = min(ram / 2, 4096)
compression-algorithm = zstd
swap-priority = 100
ZRAM

# ----- 服务 -----
for unit in sshd NetworkManager docker containerd systemd-resolved systemd-timesyncd earlyoom; do
  systemctl enable "$unit" 2>/dev/null || echo "WARN: enable $unit failed"
done
# 不使用 systemd-networkd；网络由 NetworkManager + systemd-resolved 管理。
systemctl disable systemd-networkd.service systemd-networkd.socket 2>/dev/null || true
rm -f /etc/systemd/system/multi-user.target.wants/systemd-networkd.service
rm -f /etc/systemd/system/sockets.target.wants/systemd-networkd.socket
# systemctl 在 chroot 中有时候不能写 alias，手动补 systemd-resolved。
if [ ! -e /etc/systemd/system/multi-user.target.wants/systemd-resolved.service ]; then
  mkdir -p /etc/systemd/system/multi-user.target.wants
  ln -sf /usr/lib/systemd/system/systemd-resolved.service /etc/systemd/system/multi-user.target.wants/systemd-resolved.service
fi
if [ ! -e /etc/systemd/system/dbus-org.freedesktop.resolve1.service ]; then
  ln -sf /usr/lib/systemd/system/systemd-resolved.service /etc/systemd/system/dbus-org.freedesktop.resolve1.service
fi
systemctl set-default multi-user.target 2>/dev/null || true

# ----- labwc / kitty / nvim 桌面与终端 -----
mkdir -p /etc/skel/.config/labwc /etc/skel/.config/kitty /etc/skel/.config/nvim
cat > /etc/skel/.config/labwc/autostart <<'LABWC'
# labwc 会话启动后打开 kitty 终端；不依赖 GDM/graphical.target。
/usr/bin/kitty --single-instance >/dev/null 2>&1 &
LABWC
cat > /etc/skel/.config/kitty/kitty.conf <<'KITTY'
font_family      monospace
font_size        11.0
cursor_shape     block
scrollback_lines 10000
shell            /usr/bin/bash
confirm_os_window_close 0
map ctrl+shift+enter new_window
map ctrl+shift+t     new_tab
KITTY
cat > /etc/skel/.config/nvim/init.lua <<'NVIM'
-- pearl-linux Test: 极简 neovim 默认配置
vim.opt.number = true
vim.opt.relativenumber = true
vim.opt.expandtab = true
vim.opt.shiftwidth = 2
vim.opt.tabstop = 2
vim.opt.termguicolors = true
vim.opt.mouse = "a"
NVIM
cat > /etc/skel/.bash_profile <<'PROFILE'
# pearl-linux Test
export EDITOR=nvim
export VISUAL=nvim
export PATH="$HOME/.local/bin:$PATH"

# tty1 自动进入 labwc（getty 已 autologin 到 mobian）
if [ -z "${WAYLAND_DISPLAY:-}" ] && [ "$(tty 2>/dev/null)" = "/dev/tty1" ]; then
  if [ -x /usr/bin/labwc ]; then
    export XDG_RUNTIME_DIR="/run/user/$(id -u)"
    mkdir -p "$XDG_RUNTIME_DIR"
    chmod 700 "$XDG_RUNTIME_DIR" 2>/dev/null || true
    exec /usr/bin/labwc
  fi
fi
PROFILE
cp -a /etc/skel/. /home/alarm/ 2>/dev/null || true
# 用 tmpfiles 在真实内核启动后修正家目录属主
cat >> /etc/tmpfiles.d/pearl-home.conf <<'TMPFILES'
Z /home/alarm 0755 1000 1000 -
TMPFILES

# ----- tty1 autologin -----
mkdir -p /etc/systemd/system/getty@tty1.service.d
cat > /etc/systemd/system/getty@tty1.service.d/autologin.conf <<'GETTY'
[Service]
ExecStart=
ExecStart=-/sbin/agetty --autologin alarm --noclear %I $TERM
GETTY

# 清理 generic kernel 残留
rm -rf /boot/vmlinuz-linux-aarch64 /boot/initramfs-linux-aarch64*.img 2>/dev/null || true

echo "pearl-linux Test configuration complete"
