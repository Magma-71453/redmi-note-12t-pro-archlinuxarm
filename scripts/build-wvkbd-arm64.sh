#!/usr/bin/env bash
# Cross-compile wvkbd-mobintl for the pearl rootfs (aarch64, glibc).
set -euo pipefail
REPO="$(cd "$(dirname "$0")/.." && pwd)"
SRC="$REPO/build/wvkbd"
SYSROOT="$REPO/build/rootfs-Test"
STAGE="$REPO/build/wvkbd-syslib"
mkdir -p "$REPO/build"
if [ ! -d "$SRC/.git" ]; then
  git clone --depth 1 https://github.com/jjsullivan5196/wvkbd "$SRC"
fi
mkdir -p "$STAGE"
for n in c m mvec pthread dl rt util resolv; do
  src="$(ls "$SYSROOT"/usr/lib/lib$n.so.* 2>/dev/null | head -1 || true)"
  [ -n "$src" ] && ln -sf "$src" "$STAGE/lib$n.so"
done
export PKG_CONFIG_SYSROOT_DIR="$SYSROOT"
export PKG_CONFIG_LIBDIR="$SYSROOT/usr/lib/pkgconfig:$SYSROOT/usr/share/pkgconfig"
export PKG_CONFIG_PATH="$PKG_CONFIG_LIBDIR"
export LDFLAGS="-L$STAGE -Wl,-rpath-link,$SYSROOT/usr/lib -Wl,--allow-shlib-undefined"
make -C "$SRC" LAYOUT=mobintl wvkbd-mobintl CC=aarch64-linux-gnu-gcc PKG_CONFIG=pkg-config
aarch64-linux-gnu-strip "$SRC/wvkbd-mobintl" -o "$SRC/wvkbd-mobintl.stripped"
install -m755 "$SRC/wvkbd-mobintl.stripped" "$REPO/build/rootfs-Test/usr/bin/wvkbd-mobintl"
echo "built $REPO/build/rootfs-Test/usr/bin/wvkbd-mobintl"
