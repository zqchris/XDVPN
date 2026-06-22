#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORK_DIR="${XDVPN_IOS_DEPS_DIR:-$ROOT/.xdvpn-ios-deps}"
CONFIGURATION="${CONFIGURATION:-Debug}"
DEVELOPMENT_TEAM="${DEVELOPMENT_TEAM:-}"
ALLOW_MISSING_IDENTITY="${XDVPN_ALLOW_MISSING_SIGNING_IDENTITY:-0}"
SKIP_RUNTIME_BUILD=0

usage() {
    cat >&2 <<'USAGE'
usage: DEVELOPMENT_TEAM=TEAMID scripts/build-ios-device.sh [--skip-runtime-build]

Build a signed iphoneos XDVPN.app with PacketTunnel.appex and embedded
libopenconnect.dylib. The selected Apple team must have Network Extension
packet-tunnel-provider capability for both bundle identifiers.

Environment:
  DEVELOPMENT_TEAM                 Apple Developer Team ID, required.
  CONFIGURATION                    Xcode configuration, default Debug.
  XDVPN_IOS_DEPS_DIR               Dependency work dir, default .xdvpn-ios-deps.
  XDVPN_ALLOW_MISSING_SIGNING_IDENTITY=1
                                   Let xcodebuild report signing failures instead
                                   of failing this script before build.
USAGE
}

while [[ $# -gt 0 ]]; do
    case "$1" in
      --skip-runtime-build)
        SKIP_RUNTIME_BUILD=1
        shift
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      *)
        usage
        exit 2
        ;;
    esac
done

if [[ -z "$DEVELOPMENT_TEAM" ]]; then
    echo "error: DEVELOPMENT_TEAM is required for an iphoneos VPN build" >&2
    usage
    exit 1
fi

if [[ "$ALLOW_MISSING_IDENTITY" != "1" ]] &&
   ! security find-identity -v -p codesigning 2>/dev/null | grep -Eq "Apple (Development|Distribution):|iPhone (Developer|Distribution):"; then
    echo "error: no Apple Development/Distribution signing identity found in this keychain" >&2
    echo "       Without a valid Apple certificate and Network Extension provisioning profiles, iOS will not run the VPN." >&2
    exit 1
fi

if [[ "$SKIP_RUNTIME_BUILD" -eq 0 ]]; then
    "$ROOT/scripts/build-ios-openconnect-runtime.sh" iphoneos --skip-app-build
fi

RUNTIME="$WORK_DIR/openconnect-iphoneos-arm64/lib/libopenconnect.5.dylib"
if [[ ! -f "$RUNTIME" ]]; then
    echo "error: missing iphoneos OpenConnect runtime: $RUNTIME" >&2
    echo "       Run scripts/build-ios-openconnect-runtime.sh iphoneos --skip-app-build first." >&2
    exit 1
fi

XDVPN_IOS_DEPS_DIR="$WORK_DIR" \
XDVPN_REQUIRE_OPENCONNECT_RUNTIME=1 \
xcodebuild \
  -project "$ROOT/XDVPN-iOS.xcodeproj" \
  -target XDVPNiOS \
  -configuration "$CONFIGURATION" \
  -sdk iphoneos \
  DEVELOPMENT_TEAM="$DEVELOPMENT_TEAM" \
  CODE_SIGN_STYLE=Automatic \
  build

APP="$ROOT/build/$CONFIGURATION-iphoneos/XDVPN.app"
"$ROOT/scripts/check-ios-vpn-signing.sh" "$APP"

echo "Built signed iPhone app: $APP"
