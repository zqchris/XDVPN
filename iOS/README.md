# XDVPN iOS

This directory contains the first iOS target for XDVPN:

- `XDVPNiOSApp`: SwiftUI configuration app.
- `PacketTunnel`: Network Extension packet tunnel provider.
- `XDVPNShared`: profile and provider configuration models shared by both targets.

The macOS app can launch `openconnect` as a bundled process and use privileged helpers to update routes and DNS. iOS cannot use that architecture. A production iOS client must run the VPN protocol implementation inside `PacketTunnelProvider` and must be signed with Apple Network Extension entitlement approval.

The iOS app keeps the macOS routing-policy surface that matters for mobile: global VPN by default, plus a manual policy for private CIDR presets, custom CIDRs, and domain suffixes. It intentionally does not carry over the local SOCKS5/HTTP proxy mode.

Current status:

- Builds an iOS app and packet-tunnel extension.
- Saves server, username, password reference, protocol, and manual route/domain policy into a `NETunnelProviderManager` configuration.
- Embeds a Packet Tunnel extension entrypoint with an OpenConnect runtime bridge.
- The runtime bridge loads `libopenconnect.dylib` or `OpenConnect.framework/OpenConnect` dynamically from the app or packet-tunnel Frameworks directory, fills username/password auth forms, applies Packet Tunnel network settings, and pumps IP packets through `NEPacketTunnelFlow`.
- Debug builds include a `Simulator Preview` switch for UI testing. Preview mode exercises the connect/disconnect interaction and does not create system VPN traffic.
- Production builds keep certificate validation strict by default. Use `Trust Certificate` only for VPN servers with intentionally untrusted/self-signed certificates.
- Does not implement local SOCKS5/HTTP proxy mode on iOS.
- A real VPN connection requires an iOS/simulator-compatible OpenConnect runtime binary embedded in the app or extension. Without it, the app reports a clear missing-runtime error instead of silently spinning.
- The current iOS Simulator runtime can build and embed `libopenconnect.dylib`, but this simulator image does not expose `com.apple.nehelper`; real Packet Tunnel traffic must be tested on a signed physical device.

To test the current iOS app without a signed production VPN engine:

1. Build and install the app on an iOS Simulator.
2. Open `Simulator Preview`.
3. Tap the blue power button. The state should move from `Disconnected` to `Connecting...` to `Connected`; disconnected state has no outer ring, connected state keeps a complete blue ring.
4. Tap the power button again to return to `Disconnected`.

Build locally:

```bash
./scripts/build-ios.sh
```

Build the iOS OpenConnect runtime and inject it into the Debug simulator app:

```bash
./scripts/build-ios-openconnect-runtime.sh iphonesimulator
```

Build the device OpenConnect runtime for a signed iPhone build:

```bash
./scripts/build-ios-openconnect-runtime.sh iphoneos --skip-app-build
```

For a real device build, set a development team in `XDVPN-iOS.xcodeproj` and use bundle identifiers that have the `packet-tunnel-provider` entitlement.
