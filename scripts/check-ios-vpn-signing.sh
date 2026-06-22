#!/usr/bin/env bash
set -euo pipefail

APP="${1:-build/Debug-iphoneos/XDVPN.app}"
APPEX="$APP/PlugIns/PacketTunnel.appex"
ENTITLEMENT_KEY="com.apple.developer.networking.networkextension"
REQUIRED_VALUE="packet-tunnel-provider"

failures=0

fail() {
    echo "error: $*" >&2
    failures=$((failures + 1))
}

ok() {
    echo "ok: $*"
}

warn() {
    echo "warning: $*" >&2
}

check_bundle_exists() {
    local bundle="$1"
    local label="$2"
    if [[ -d "$bundle" ]]; then
        ok "$label exists: $bundle"
    else
        fail "$label not found: $bundle"
    fi
}

check_developer_signature() {
    local bundle="$1"
    local label="$2"
    local details
    details="$(codesign -dv --verbose=4 "$bundle" 2>&1 || true)"

    if grep -q "Signature=adhoc" <<<"$details"; then
        fail "$label is ad-hoc signed; iOS VPN requires an Apple Development or Distribution signature"
        return
    fi

    if grep -Eq "Authority=Apple (Development|Distribution):|Authority=iPhone (Developer|Distribution):" <<<"$details"; then
        ok "$label has Apple developer signature"
    else
        fail "$label is not signed with an Apple developer identity"
    fi

    if grep -q "TeamIdentifier=" <<<"$details"; then
        ok "$label has team identifier"
    else
        fail "$label missing TeamIdentifier"
    fi
}

check_entitlement() {
    local bundle="$1"
    local label="$2"
    local tmp
    tmp="$(mktemp)"
    if ! codesign -d --entitlements :- "$bundle" >"$tmp" 2>/dev/null; then
        rm -f "$tmp"
        fail "$label entitlements could not be read"
        return
    fi

    if grep -q "<key>$ENTITLEMENT_KEY</key>" "$tmp" &&
       grep -q "<string>$REQUIRED_VALUE</string>" "$tmp"; then
        ok "$label has $REQUIRED_VALUE entitlement"
    else
        fail "$label missing $REQUIRED_VALUE entitlement"
    fi
    rm -f "$tmp"
}

check_profile() {
    local bundle="$1"
    local label="$2"
    local profile="$bundle/embedded.mobileprovision"
    if [[ -f "$profile" ]]; then
        ok "$label has embedded.mobileprovision"
    else
        fail "$label missing embedded.mobileprovision"
    fi
}

check_runtime() {
    local runtime="$APPEX/Frameworks/libopenconnect.dylib"
    if [[ -f "$runtime" ]]; then
        ok "PacketTunnel embeds libopenconnect.dylib"
    else
        fail "PacketTunnel missing Frameworks/libopenconnect.dylib"
    fi
}

if [[ ! -d "$APP" ]]; then
    fail "app bundle not found: $APP"
    echo "usage: $0 path/to/XDVPN.app" >&2
    exit 1
fi

check_bundle_exists "$APP" "XDVPN.app"
check_bundle_exists "$APPEX" "PacketTunnel.appex"

if [[ -d "$APP" ]]; then
    check_developer_signature "$APP" "XDVPN.app"
    check_entitlement "$APP" "XDVPN.app"
    check_profile "$APP" "XDVPN.app"
fi

if [[ -d "$APPEX" ]]; then
    check_developer_signature "$APPEX" "PacketTunnel.appex"
    check_entitlement "$APPEX" "PacketTunnel.appex"
    check_profile "$APPEX" "PacketTunnel.appex"
    check_runtime
fi

if [[ "$APP" == *iphonesimulator* ]]; then
    warn "this is a Simulator build; Simulator cannot prove real VPN traffic"
fi

if [[ "$failures" -gt 0 ]]; then
    echo "iOS VPN signing check failed with $failures issue(s)." >&2
    exit 1
fi

echo "iOS VPN signing check passed."
