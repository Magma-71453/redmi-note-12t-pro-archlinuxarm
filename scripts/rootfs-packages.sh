#!/usr/bin/env bash
# 在 chroot 内执行：系统升级 + 安装 Test server/desktop/container 包集合。
set -euo pipefail
export LANG=C.UTF-8
PKGS=(
  base systemd systemd-sysvcompat
  linux-firmware
  openssh networkmanager iwd dhcpcd
  docker docker-compose
  labwc kitty neovim foot wl-clipboard
  mesa mesa-utils vulkan-icd-loader
  sudo git curl wget htop tmux jq rsync unzip
  python python-pip
  zram-generator earlyoom polkit seatd
)
# ALARM tarball 自带 generic linux-aarch64，本项目使用 7.2.10++ pearl 定制内核，
# 移除 generic 内核，避免 /boot 和 /usr/lib/modules 混淆。
pacman -Rdd --noconfirm linux-aarch64 || true
pacman -Syu --noconfirm
pacman -S --noconfirm --needed "${PKGS[@]}"
pacman -Q > /tmp/installed-packages.txt
pacman -Q "${PKGS[@]}" || true
