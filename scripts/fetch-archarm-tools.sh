#!/usr/bin/env bash
# Fetch small aarch64 helper packages (wlopm/wlr-randr/grim) and install into the rootfs tree.
set -euo pipefail
REPO="$(cd "$(dirname "$0")/.." && pwd)"
MIRROR="${ALARM_MIRROR:-http://mirror.archlinuxarm.org/aarch64/extra}"
DEST="$REPO/build/pkgs"
mkdir -p "$DEST" "$DEST/extract"
for pkg in wlopm-1.0.0-3-aarch64.pkg.tar.xz wlr-randr-0.5.0-1-aarch64.pkg.tar.xz grim-1.5.0-2-aarch64.pkg.tar.xz; do
  [ -f "$DEST/$pkg" ] || curl -fL "$MIRROR/$pkg" -o "$DEST/$pkg"
  tar -xf "$DEST/$pkg" -C "$DEST/extract"
done
for b in wlopm wlr-randr grim; do
  src="$(find "$DEST/extract" -path "*/usr/bin/$b" -type f | head -1)"
  install -m755 "$src" "$REPO/build/rootfs-Test/usr/bin/$b"
done
