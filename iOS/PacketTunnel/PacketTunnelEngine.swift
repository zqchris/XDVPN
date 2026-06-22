import Foundation
import NetworkExtension
import os.log
import Security

enum PacketTunnelEngineMode: String {
    case openconnect
    case demo
}

struct PacketTunnelConfiguration {
    let server: String
    let username: String
    let protocolName: String
    let engineMode: PacketTunnelEngineMode
    let runningMode: String
    let splitCIDRs: [String]
    let splitDomains: [String]
    let password: String
    let allowUntrustedServerCertificate: Bool

    init(protocolConfiguration: NETunnelProviderProtocol?) {
        let providerConfiguration = protocolConfiguration?.providerConfiguration ?? [:]
        server = providerConfiguration["server"] as? String
            ?? protocolConfiguration?.serverAddress
            ?? "demo.xdvpn.local"
        username = providerConfiguration["username"] as? String ?? "demo"
        protocolName = providerConfiguration["protocol"] as? String ?? "anyconnect"
        runningMode = providerConfiguration["runningMode"] as? String ?? "full"
        splitCIDRs = providerConfiguration["splitCIDRs"] as? [String] ?? []
        splitDomains = providerConfiguration["splitDomains"] as? [String] ?? []
        password = Self.password(
            fromPersistentReference: protocolConfiguration?.passwordReference
        ) ?? providerConfiguration["password"] as? String ?? ""
        allowUntrustedServerCertificate = providerConfiguration["allowUntrustedServerCertificate"] as? Bool ?? false

        let rawMode = providerConfiguration["engineMode"] as? String ?? "openconnect"
        engineMode = PacketTunnelEngineMode(rawValue: rawMode) ?? .openconnect
    }

    var runtimeDictionary: [String: Any] {
        [
            "server": server,
            "username": username,
            "password": password,
            "protocol": protocolName,
            "runningMode": runningMode,
            "splitCIDRs": splitCIDRs,
            "splitDomains": splitDomains,
            "allowUntrustedServerCertificate": allowUntrustedServerCertificate,
        ]
    }

    private static func password(fromPersistentReference persistentReference: Data?) -> String? {
        guard let persistentReference else { return nil }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecValuePersistentRef as String: persistentReference,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess,
              let data = result as? Data,
              let password = String(data: data, encoding: .utf8)
        else { return nil }
        return password
    }
}

protocol PacketTunnelEngine: AnyObject {
    func start(
        provider: NEPacketTunnelProvider,
        configuration: PacketTunnelConfiguration,
        completionHandler: @escaping (Error?) -> Void
    )

    func stop(
        provider: NEPacketTunnelProvider,
        reason: NEProviderStopReason,
        completionHandler: @escaping () -> Void
    )
}

final class DemoPacketTunnelEngine: PacketTunnelEngine {
    private let logger = Logger(subsystem: "com.kafeifei.xdvpn.ios", category: "DemoPacketTunnel")

    func start(
        provider: NEPacketTunnelProvider,
        configuration: PacketTunnelConfiguration,
        completionHandler: @escaping (Error?) -> Void
    ) {
        let settings = makeNetworkSettings(for: configuration)
        provider.setTunnelNetworkSettings(settings) { [logger] error in
            if let error {
                logger.error("Demo tunnel failed to apply settings: \(error.localizedDescription, privacy: .public)")
                completionHandler(error)
                return
            }

            logger.info("Demo tunnel started server=\(configuration.server, privacy: .private) mode=\(configuration.runningMode, privacy: .public) cidrs=\(configuration.splitCIDRs.count, privacy: .public) domains=\(configuration.splitDomains.count, privacy: .public)")
            completionHandler(nil)
        }
    }

    func stop(
        provider: NEPacketTunnelProvider,
        reason: NEProviderStopReason,
        completionHandler: @escaping () -> Void
    ) {
        logger.info("Demo tunnel stopped with reason \(reason.rawValue, privacy: .public)")
        provider.setTunnelNetworkSettings(nil) { _ in
            completionHandler()
        }
    }

    private func makeNetworkSettings(for configuration: PacketTunnelConfiguration) -> NEPacketTunnelNetworkSettings {
        let settings = NEPacketTunnelNetworkSettings(tunnelRemoteAddress: configuration.server)
        settings.mtu = 1280

        let ipv4 = NEIPv4Settings(addresses: ["198.18.0.2"], subnetMasks: ["255.255.0.0"])
        if configuration.runningMode == "split" {
            let routes = configuration.splitCIDRs.compactMap(Self.route(fromCIDR:))
            ipv4.includedRoutes = routes.isEmpty ? [Self.demoRoute] : routes
        } else {
            ipv4.includedRoutes = [Self.demoRoute]
        }
        settings.ipv4Settings = ipv4

        if !configuration.splitDomains.isEmpty {
            let dns = NEDNSSettings(servers: ["198.18.0.1"])
            dns.matchDomains = configuration.splitDomains
            settings.dnsSettings = dns
        }

        return settings
    }

    private static var demoRoute: NEIPv4Route {
        NEIPv4Route(destinationAddress: "198.18.0.0", subnetMask: "255.254.0.0")
    }

    private static func route(fromCIDR cidr: String) -> NEIPv4Route? {
        let parts = cidr.split(separator: "/", maxSplits: 1, omittingEmptySubsequences: false)
        guard parts.count == 2,
              let prefixLength = Int(parts[1]),
              (0...32).contains(prefixLength),
              let mask = subnetMask(prefixLength: prefixLength)
        else { return nil }

        return NEIPv4Route(destinationAddress: String(parts[0]), subnetMask: mask)
    }

    private static func subnetMask(prefixLength: Int) -> String? {
        guard (0...32).contains(prefixLength) else { return nil }
        let mask = prefixLength == 0 ? UInt32(0) : UInt32.max << UInt32(32 - prefixLength)
        return [
            (mask >> 24) & 0xff,
            (mask >> 16) & 0xff,
            (mask >> 8) & 0xff,
            mask & 0xff,
        ]
        .map(String.init)
        .joined(separator: ".")
    }
}

final class OpenConnectPacketTunnelEngine: PacketTunnelEngine {
    private let logger = Logger(subsystem: "com.kafeifei.xdvpn.ios", category: "OpenConnectPacketTunnel")
    private var runtime: XDOpenConnectRuntime?

    func start(
        provider: NEPacketTunnelProvider,
        configuration: PacketTunnelConfiguration,
        completionHandler: @escaping (Error?) -> Void
    ) {
        guard !configuration.password.isEmpty else {
            completionHandler(PacketTunnelStartFailure.missingPassword.nsError)
            return
        }

        logger.info("Starting OpenConnect runtime protocol=\(configuration.protocolName, privacy: .public) mode=\(configuration.runningMode, privacy: .public) cidrs=\(configuration.splitCIDRs.count, privacy: .public) domains=\(configuration.splitDomains.count, privacy: .public)")
        let runtime = XDOpenConnectRuntime()
        self.runtime = runtime
        runtime.start(
            provider: provider,
            packetFlow: provider.packetFlow,
            configuration: configuration.runtimeDictionary
        ) { [weak self] error in
            if let error {
                self?.logger.error("OpenConnect runtime failed: \(error.localizedDescription, privacy: .public)")
            } else {
                self?.logger.info("OpenConnect runtime started")
            }
            completionHandler(error)
        }
    }

    func stop(
        provider: NEPacketTunnelProvider,
        reason: NEProviderStopReason,
        completionHandler: @escaping () -> Void
    ) {
        logger.info("OpenConnect tunnel stopped with reason \(reason.rawValue, privacy: .public)")
        let runtime = runtime
        self.runtime = nil
        runtime?.stop(completion: completionHandler) ?? completionHandler()
    }
}

private enum PacketTunnelStartFailure {
    case missingPassword

    var nsError: NSError {
        switch self {
        case .missingPassword:
            return NSError(
                domain: "com.kafeifei.xdvpn.ios.PacketTunnel",
                code: 2,
                userInfo: [
                    NSLocalizedDescriptionKey: "缺少 VPN 密码",
                    NSLocalizedFailureReasonErrorKey: "Packet Tunnel extension 没有拿到 Keychain passwordReference 对应的密码。",
                    NSLocalizedRecoverySuggestionErrorKey: "请在 iOS App 里重新输入密码并保存后再连接。",
                ]
            )
        }
    }
}
