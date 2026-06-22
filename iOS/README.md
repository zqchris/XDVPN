# XDVPN iOS

This directory contains the first iOS target for XDVPN:

- `XDVPNiOSApp`: SwiftUI configuration app.
- `PacketTunnel`: Network Extension packet tunnel provider.
- `XDVPNShared`: profile and provider configuration models shared by both targets.

The macOS app can launch `openconnect` as a bundled process and use privileged helpers to update routes and DNS. iOS cannot use that architecture. A production iOS client must run the VPN protocol implementation inside `PacketTunnelProvider` and must be signed with Apple Network Extension entitlement approval.

Current status:

- Builds an iOS app and packet-tunnel extension.
- Saves server, username, password reference, protocol, and fixed global-VPN mode into a `NETunnelProviderManager` configuration.
- Embeds a Packet Tunnel extension entrypoint.
- Does not implement local SOCKS5/HTTP proxy mode or split-tunnel UI on iOS.
- Fails tunnel start with a clear error until an OpenConnect-compatible engine is linked into the extension.

Build locally:

```bash
./scripts/build-ios.sh
```

For a real device build, set a development team in `XDVPN-iOS.xcodeproj` and use bundle identifiers that have the `packet-tunnel-provider` entitlement.
