#!/bin/bash
# Builds the native engines for iOS (arm64, device):
#   Native/build/lib/libciadpi.a  - byedpi + zdpi wrapper (only zdpi_* symbols exported)
#   Native/build/lib/libhev.a     - hev-socks5-tunnel (+ lwip, yaml, hev-task-system)
#   Native/build/include/         - hev-main.h
# Requires macOS with Xcode.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/Native/build"
SDK="iphoneos"
ARCH="arm64"
MIN_IOS="16.0"

BYEDPI_SRC="$ROOT/Vendor/byedpi"
HEV_SRC="$ROOT/Vendor/hev-socks5-tunnel"

CC="$(xcrun --sdk "$SDK" --find clang)"
SYSROOT="$(xcrun --sdk "$SDK" --show-sdk-path)"
TARGET_FLAGS="-arch $ARCH -isysroot $SYSROOT -miphoneos-version-min=$MIN_IOS"

rm -rf "$OUT"
mkdir -p "$OUT/lib" "$OUT/include" "$OUT/obj/byedpi" "$OUT/src/byedpi"

echo "==> Preparing byedpi sources"
cp "$BYEDPI_SRC"/*.c "$BYEDPI_SRC"/*.h "$OUT/src/byedpi/"
rm -f "$OUT/src/byedpi/win_service.c"
cd "$OUT/src/byedpi"

patch_check() {
    # $1 file, $2 pattern that must exist after patching
    if ! grep -q -- "$2" "$1"; then
        echo "error: patch for $1 was not applied (pattern: $2)" >&2
        exit 1
    fi
}

# 1. Stoppable event loop.
perl -0pi -e 's/#include "error.h"\n/#include "error.h"\n\nextern volatile int zdpi_stop_requested;\n/' conev.c
perl -0pi -e 's/while \(!pool->brk\) \{/while (!pool->brk && !zdpi_stop_requested) {/' conev.c
patch_check conev.c "while (!pool->brk && !zdpi_stop_requested)"

# 2. Port ranges are stored in network byte order; compare in host order.
perl -0pi -e 's/\(dst->in\.sin_port < dp->pf\[0\] \|\| dst->in\.sin_port > dp->pf\[1\]\)/(ntohs(dst->in.sin_port) < ntohs(dp->pf[0]) || ntohs(dst->in.sin_port) > ntohs(dp->pf[1]))/' extend.c
patch_check extend.c "ntohs(dst->in.sin_port) < ntohs(dp->pf\[0\])"

# 3. Allow "--rst" groups to drop UDP datagrams (used to block QUIC).
perl -0pi -e 's/(        pair->dp = dp;\n    \}\n)/$1    if (dp->rst) {\n        return n;\n    }\n/' extend.c
if [ "$(grep -c 'if (dp->rst) {' extend.c)" -lt 2 ]; then
    echo "error: UDP rst patch was not applied" >&2
    exit 1
fi

# 4. No daemon() inside an iOS process.
perl -0pi -e 's/\n    #define DAEMON\n/\n    #ifndef ZDPI_EMBED\n    #define DAEMON\n    #endif\n/' main.c
patch_check main.c "ZDPI_EMBED"

cp "$ROOT/Native/src/zdpi.c" "$ROOT/Native/include/zdpi.h" .

echo "==> Compiling byedpi"
CFLAGS="$TARGET_FLAGS -O2 -std=gnu99 -D_DARWIN_C_SOURCE -DZDPI_EMBED -Dmain=ciadpi_main -I. -Wno-unused -Wno-unused-parameter -Wno-deprecated-declarations"
OBJS=()
for src in packets.c main.c conev.c proxy.c desync.c mpool.c extend.c zdpi.c; do
    obj="$OUT/obj/byedpi/${src%.c}.o"
    "$CC" $CFLAGS -c "$src" -o "$obj"
    OBJS+=("$obj")
done

echo "==> Linking libciadpi.a (hiding internal symbols)"
cat > "$OUT/obj/zdpi.exp" <<'EOF'
_zdpi_run
_zdpi_stop
_zdpi_is_running
_zdpi_redirect_stderr
EOF
if xcrun --sdk "$SDK" ld -r -arch "$ARCH" -exported_symbols_list "$OUT/obj/zdpi.exp" \
        -o "$OUT/obj/ciadpi_merged.o" "${OBJS[@]}" 2>"$OUT/obj/ld.log"; then
    xcrun --sdk "$SDK" libtool -static -o "$OUT/lib/libciadpi.a" "$OUT/obj/ciadpi_merged.o"
else
    echo "warning: ld -r failed, linking without symbol hiding:" >&2
    cat "$OUT/obj/ld.log" >&2
    xcrun --sdk "$SDK" libtool -static -o "$OUT/lib/libciadpi.a" "${OBJS[@]}"
fi

echo "==> Building hev-socks5-tunnel"
cd "$HEV_SRC"
make clean >/dev/null 2>&1 || true
make PP="$CC $TARGET_FLAGS" \
     CC="$CC" \
     CFLAGS="$TARGET_FLAGS -O2" \
     LFLAGS="$TARGET_FLAGS" \
     static -j"$(sysctl -n hw.ncpu)"
xcrun --sdk "$SDK" libtool -static -o "$OUT/lib/libhev.a" \
    bin/libhev-socks5-tunnel.a \
    third-part/lwip/bin/liblwip.a \
    third-part/yaml/bin/libyaml.a \
    third-part/hev-task-system/bin/libhev-task-system.a
cp src/hev-main.h "$OUT/include/"
make clean >/dev/null 2>&1 || true

echo "==> Done"
ls -la "$OUT/lib"
