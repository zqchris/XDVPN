import Foundation
import NetworkExtension
import os.log

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

        let rawMode = providerConfiguration["engineMode"] as? String ?? "openconnect"
        engineMode = PacketTunnelEngineMode(rawValue: rawMode) ?? .openconnect
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

    func start(
        provider: NEPacketTunnelProvider,
        configuration: PacketTunnelConfiguration,
        completionHandler: @escaping (Error?) -> Void
    ) {
        logger.error("OpenConnect engine is not linked. server=\(configuration.server, privacy: .private) protocol=\(configuration.protocolName, privacy: .public) mode=\(configuration.runningMode, privacy: .public) cidrs=\(configuration.splitCIDRs.count, privacy: .public) domains=\(configuration.splitDomains.count, privacy: .public)")
        completionHandler(PacketTunnelStartFailure.openConnectEngineUnavailable(
            server: configuration.server,
            protocolName: configuration.protocolName
        ).nsError)
    }

    func stop(
        provider: NEPacketTunnelProvider,
        reason: NEProviderStopReason,
        completionHandler: @escaping () -> Void
    ) {
        logger.info("OpenConnect tunnel stopped with reason \(reason.rawValue, privacy: .public)")
        completionHandler()
    }
}

private enum PacketTunnelStartFailure {
    case openConnectEngineUnavailable(server: String, protocolName: String)

    var nsError: NSError {
        switch self {
        case .openConnectEngineUnavailable(let server, let protocolName):
            return NSError(
                domain: "com.kafeifei.xdvpn.ios.PacketTunnel",
                code: 1,
                userInfo: [
                    NSLocalizedDescriptionKey: "OpenConnect iOS 引擎尚未接入",
                    NSLocalizedFailureReasonErrorKey: "iOS 不能像 macOS 版一样启动 openconnect 进程；Packet Tunnel extension 必须内嵌协议实现。",
                    NSLocalizedRecoverySuggestionErrorKey: "需要把 \(protocolName) 协议引擎移植为 extension 内可调用库后，才能连接 \(server)。",
                ]
            )
        }
    }
}
