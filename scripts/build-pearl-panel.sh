#!/usr/bin/env bash
# Cross-compile the pearl-panel layer-shell status panel for aarch64.
set -euo pipefail
REPO="$(cd "$(dirname "$0")/.." && pwd)"
SRCDIR="$REPO/src/pearl-panel"
OUTDIR="$REPO/build/pearl-panel"
SYSROOT="$REPO/build/rootfs-Test"
STAGE="$REPO/build/wvkbd-syslib"
mkdir -p "$OUTDIR/proto" "$STAGE"
cp -f "$SRCDIR"/proto/*.xml "$OUTDIR/proto/"
cd "$OUTDIR"
wayland-scanner client-header proto/wlr-layer-shell-unstable-v1.xml wlr-layer-shell-unstable-v1-client-protocol.h
wayland-scanner private-code  proto/wlr-layer-shell-unstable-v1.xml wlr-layer-shell-unstable-v1-protocol.c
wayland-scanner client-header proto/xdg-shell.xml xdg-shell-client-protocol.h
wayland-scanner private-code  proto/xdg-shell.xml xdg-shell-client-protocol.c
export PKG_CONFIG_SYSROOT_DIR="$SYSROOT"
export PKG_CONFIG_LIBDIR="$SYSROOT/usr/lib/pkgconfig:$SYSROOT/usr/share/pkgconfig"
export PKG_CONFIG_PATH="$PKG_CONFIG_LIBDIR"
aarch64-linux-gnu-gcc -O2 -Wall -Wextra -I. \
  $(pkg-config --cflags cairo pangocairo wayland-client) \
  "$SRCDIR/pearl-panel.c" wlr-layer-shell-unstable-v1-protocol.c xdg-shell-client-protocol.c \
  -o pearl-panel \
  -L"$STAGE" -Wl,-rpath-link,"$SYSROOT/usr/lib" -Wl,--allow-shlib-undefined \
  $(pkg-config --libs cairo pangocairo wayland-client) -lm
install -m755 pearl-panel "$SYSROOT/usr/local/bin/pearl-panel"
echo "built $SYSROOT/usr/local/bin/pearl-panel"
