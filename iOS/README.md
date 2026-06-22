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
- Embeds a Packet Tunnel extension entrypoint.
- Includes a `Demo Tunnel` switch for simulator/UI testing. Demo mode previews the connect/disconnect interaction in the app and does not create system VPN traffic.
- Does not implement local SOCKS5/HTTP proxy mode on iOS.
- Fails tunnel start with a clear error until an OpenConnect-compatible engine is linked into the extension.

To test the current iOS app without a signed production VPN engine:

1. Build and install the app on an iOS Simulator.
2. Open `Demo Tunnel`.
3. Tap the blue power button. The state should move from `Disconnected` to `Connecting...` to `Connected`; disconnected state has no outer ring, connected state keeps a complete blue ring.
4. Tap the power button again to return to `Disconnected`.

Build locally:

```bash
./scripts/build-ios.sh
```

For a real device build, set a development team in `XDVPN-iOS.xcodeproj` and use bundle identifiers that have the `packet-tunnel-provider` entitlement.
