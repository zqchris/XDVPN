#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PLATFORM="${PLATFORM_NAME:-${1:-iphonesimulator}}"
PRODUCT_BUNDLE=""
WORK_DIR="${XDVPN_IOS_DEPS_DIR:-$ROOT/.xdvpn-ios-deps}"
REQUIRE_RUNTIME="${XDVPN_REQUIRE_OPENCONNECT_RUNTIME:-0}"

if [[ -n "${TARGET_BUILD_DIR:-}" && -n "${FULL_PRODUCT_NAME:-}" ]]; then
    PRODUCT_BUNDLE="$TARGET_BUILD_DIR/$FULL_PRODUCT_NAME"
fi

if [[ -n "${1:-}" && -d "${1:-}" ]]; then
    PRODUCT_BUNDLE="$1"
    PLATFORM="${2:-$PLATFORM}"
fi

if [[ -z "$PRODUCT_BUNDLE" || ! -d "$PRODUCT_BUNDLE" ]]; then
    echo "warning: PacketTunnel product bundle not found; skipping OpenConnect runtime embed" >&2
    exit 0
fi

case "$PLATFORM" in
  iphonesimulator)
    RUNTIME_SOURCE="$WORK_DIR/openconnect-iossim-arm64/lib/libopenconnect.5.dylib"
    ;;
  iphoneos)
    RUNTIME_SOURCE="$WORK_DIR/openconnect-iphoneos-arm64/lib/libopenconnect.5.dylib"
    ;;
  *)
    echo "warning: unsupported platform '$PLATFORM'; skipping OpenConnect runtime embed" >&2
    exit 0
    ;;
esac

DEST_DIR="$PRODUCT_BUNDLE/Frameworks"
DEST="$DEST_DIR/libopenconnect.dylib"

if [[ ! -f "$RUNTIME_SOURCE" ]]; then
    rm -f "$DEST"
    message="OpenConnect runtime missing for $PLATFORM: $RUNTIME_SOURCE"
    if [[ "$REQUIRE_RUNTIME" == "1" ]]; then
        echo "error: $message" >&2
        exit 1
    fi
    echo "warning: $message; run scripts/build-ios-openconnect-runtime.sh $PLATFORM to build it" >&2
    exit 0
fi

mkdir -p "$DEST_DIR"
cp "$RUNTIME_SOURCE" "$DEST"
chmod 0755 "$DEST"
install_name_tool -id @rpath/libopenconnect.dylib "$DEST"

if [[ "${CODE_SIGNING_ALLOWED:-YES}" != "NO" ]]; then
    SIGN_IDENTITY="${EXPANDED_CODE_SIGN_IDENTITY:-}"
    if [[ -z "$SIGN_IDENTITY" && "$PLATFORM" == "iphonesimulator" ]]; then
        SIGN_IDENTITY="-"
    fi
    if [[ -n "$SIGN_IDENTITY" ]]; then
        codesign --force --sign "$SIGN_IDENTITY" --timestamp=none "$DEST" >/dev/null
    fi
fi

echo "Embedded OpenConnect runtime: $DEST"
