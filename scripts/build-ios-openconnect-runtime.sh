#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PLATFORM="${1:-iphonesimulator}"
APP_BUILD_MODE="${2:-}"

OPENSSL_VERSION="${XDVPN_OPENSSL_VERSION:-3.6.1}"
OPENCONNECT_REPO="${XDVPN_OPENCONNECT_REPO:-https://gitlab.com/openconnect/openconnect.git}"
OPENCONNECT_REF="${XDVPN_OPENCONNECT_REF:-9c136a2}"
MIN_IOS="${XDVPN_IOS_MIN_VERSION:-17.0}"
WORK_DIR="${XDVPN_IOS_DEPS_DIR:-$ROOT/.xdvpn-ios-deps}"
OPENSSL_TARBALL="$WORK_DIR/openssl-$OPENSSL_VERSION.tar.gz"
OPENSSL_SRC="$WORK_DIR/openssl-$OPENSSL_VERSION"
OPENCONNECT_SRC="${XDVPN_OPENCONNECT_SRC:-$WORK_DIR/openconnect-src}"
EMPTY_PC="$WORK_DIR/empty-pkgconfig"

case "$PLATFORM" in
  iphonesimulator)
    SDK_NAME="iphonesimulator"
    OPENSSL_TARGET="iossimulator-arm64-xcrun"
    TARGET_TRIPLE="arm64-apple-ios${MIN_IOS}-simulator"
    MIN_FLAG="-mios-simulator-version-min=$MIN_IOS"
    OPENSSL_MIN_FLAG="-mios-simulator-version-min=$MIN_IOS"
    OPENSSL_PREFIX="$WORK_DIR/openssl-iossim-arm64"
    OPENCONNECT_BUILD="$WORK_DIR/openconnect-build-iossim-arm64"
    OPENCONNECT_PREFIX="$WORK_DIR/openconnect-iossim-arm64"
    BUILD_APP=1
    ;;
  iphoneos)
    SDK_NAME="iphoneos"
    OPENSSL_TARGET="ios64-xcrun"
    TARGET_TRIPLE="arm64-apple-ios$MIN_IOS"
    MIN_FLAG="-miphoneos-version-min=$MIN_IOS"
    OPENSSL_MIN_FLAG="-miphoneos-version-min=$MIN_IOS"
    OPENSSL_PREFIX="$WORK_DIR/openssl-iphoneos-arm64"
    OPENCONNECT_BUILD="$WORK_DIR/openconnect-build-iphoneos-arm64"
    OPENCONNECT_PREFIX="$WORK_DIR/openconnect-iphoneos-arm64"
    BUILD_APP=0
    ;;
  *)
    echo "usage: $0 [iphonesimulator|iphoneos] [--skip-app-build|--build-app]" >&2
    exit 2
    ;;
esac

case "$APP_BUILD_MODE" in
  "")
    ;;
  --skip-app-build)
    BUILD_APP=0
    ;;
  --build-app)
    BUILD_APP=1
    ;;
  *)
    echo "usage: $0 [iphonesimulator|iphoneos] [--skip-app-build|--build-app]" >&2
    exit 2
    ;;
esac

require_tool() {
    if ! command -v "$1" >/dev/null 2>&1; then
        echo "error: missing required tool '$1'" >&2
        exit 1
    fi
}

require_tool curl
require_tool git
require_tool make
require_tool xcrun
require_tool install_name_tool
require_tool codesign
require_tool pkg-config
require_tool autoreconf

mkdir -p "$WORK_DIR" "$EMPTY_PC"

if [[ ! -d "$OPENSSL_SRC" ]]; then
    if [[ ! -f "$OPENSSL_TARBALL" ]]; then
        curl -L "https://www.openssl.org/source/openssl-$OPENSSL_VERSION.tar.gz" -o "$OPENSSL_TARBALL"
    fi
    tar -xzf "$OPENSSL_TARBALL" -C "$WORK_DIR"
fi

if [[ ! -f "$OPENSSL_PREFIX/lib/libssl.a" || ! -f "$OPENSSL_PREFIX/lib/libcrypto.a" ]]; then
    echo "Building OpenSSL $OPENSSL_VERSION for $PLATFORM..."
    (
        cd "$OPENSSL_SRC"
        make clean >/dev/null 2>&1 || true
        CFLAGS="$OPENSSL_MIN_FLAG" ./Configure "$OPENSSL_TARGET" no-shared no-tests no-apps \
            --prefix="$OPENSSL_PREFIX" > "$WORK_DIR/openssl-configure-$PLATFORM.log" 2>&1
        make -j"$(sysctl -n hw.ncpu)" > "$WORK_DIR/openssl-make-$PLATFORM.log" 2>&1
        make install_sw > "$WORK_DIR/openssl-install-$PLATFORM.log" 2>&1
    )
fi

if [[ ! -d "$OPENCONNECT_SRC/.git" ]]; then
    git clone "$OPENCONNECT_REPO" "$OPENCONNECT_SRC"
fi

(
    cd "$OPENCONNECT_SRC"
    git fetch --quiet --tags origin
    git -c advice.detachedHead=false checkout --quiet "$OPENCONNECT_REF"
    if [[ ! -x configure ]]; then
        PATH="/opt/homebrew/opt/libtool/libexec/gnubin:$PATH" ./autogen.sh
    fi
)

SDK_PATH="$(xcrun --sdk "$SDK_NAME" --show-sdk-path)"
CC_PATH="$(xcrun --sdk "$SDK_NAME" --find clang)"

rm -rf "$OPENCONNECT_BUILD" "$OPENCONNECT_PREFIX"
mkdir -p "$OPENCONNECT_BUILD"

echo "Building OpenConnect $OPENCONNECT_REF for $PLATFORM..."
(
    cd "$OPENCONNECT_BUILD"
    CC="$CC_PATH" \
    CFLAGS="-target $TARGET_TRIPLE -isysroot $SDK_PATH $MIN_FLAG -fPIC -D__APPLE_USE_RFC_3542" \
    CPPFLAGS="-I$OPENSSL_PREFIX/include -I$SDK_PATH/usr/include/libxml2" \
    LDFLAGS="-target $TARGET_TRIPLE -isysroot $SDK_PATH $MIN_FLAG -L$OPENSSL_PREFIX/lib" \
    OPENSSL_CFLAGS="-I$OPENSSL_PREFIX/include" \
    OPENSSL_LIBS="-L$OPENSSL_PREFIX/lib -lssl -lcrypto -framework Security -framework CoreFoundation" \
    LIBXML2_CFLAGS="-I$SDK_PATH/usr/include/libxml2" \
    LIBXML2_LIBS="-lxml2" \
    ZLIB_CFLAGS="" \
    ZLIB_LIBS="-lz" \
    PKG_CONFIG="$(command -v pkg-config)" \
    PKG_CONFIG_LIBDIR="$EMPTY_PC" \
    "$OPENCONNECT_SRC/configure" \
        --host=arm-apple-darwin \
        --prefix="$OPENCONNECT_PREFIX" \
        --with-vpnc-script=/etc/vpnc/vpnc-script \
        --without-gnutls \
        --disable-nls \
        --disable-symvers \
        --without-lz4 \
        --with-builtin-json \
        --without-libproxy \
        --without-stoken \
        --without-libpcsclite \
        --without-libpskc \
        --without-gssapi \
        --without-openssl-version-check \
        --disable-flask-tests \
        --disable-dsa-tests > "$WORK_DIR/openconnect-configure-$PLATFORM.log" 2>&1
    make -j"$(sysctl -n hw.ncpu)" > "$WORK_DIR/openconnect-make-$PLATFORM.log" 2>&1
    make install > "$WORK_DIR/openconnect-install-$PLATFORM.log" 2>&1
)

RUNTIME_SOURCE="$OPENCONNECT_PREFIX/lib/libopenconnect.5.dylib"
if [[ ! -f "$RUNTIME_SOURCE" ]]; then
    echo "error: runtime dylib not found: $RUNTIME_SOURCE" >&2
    exit 1
fi

if [[ "$BUILD_APP" -eq 1 ]]; then
    if [[ "$PLATFORM" != "iphonesimulator" ]]; then
        echo "error: --build-app is only supported for iphonesimulator in this helper" >&2
        exit 1
    fi

    "$ROOT/scripts/build-ios.sh"

    for dest in \
        "$ROOT/build/Debug-iphonesimulator/XDVPN.app/Frameworks" \
        "$ROOT/build/Debug-iphonesimulator/XDVPN.app/PlugIns/PacketTunnel.appex/Frameworks" \
        "$ROOT/build/Debug-iphonesimulator/PacketTunnel.appex/Frameworks"; do
        mkdir -p "$dest"
        cp "$RUNTIME_SOURCE" "$dest/libopenconnect.dylib"
        install_name_tool -id @rpath/libopenconnect.dylib "$dest/libopenconnect.dylib"
        codesign --force --sign - "$dest/libopenconnect.dylib" >/dev/null
    done

    codesign --force --sign - "$ROOT/build/Debug-iphonesimulator/XDVPN.app/PlugIns/PacketTunnel.appex" >/dev/null
    codesign --force --sign - "$ROOT/build/Debug-iphonesimulator/XDVPN.app" >/dev/null
    echo "Injected libopenconnect.dylib into build/Debug-iphonesimulator/XDVPN.app"
else
    echo "Built runtime: $RUNTIME_SOURCE"
fi
