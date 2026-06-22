import Foundation
import NetworkExtension
import os.log

final class PacketTunnelProvider: NEPacketTunnelProvider {
    private let logger = Logger(subsystem: "com.kafeifei.xdvpn.ios", category: "PacketTunnel")

    override func startTunnel(
        options: [String: NSObject]?,
        completionHandler: @escaping (Error?) -> Void
    ) {
        let tunnelProtocol = protocolConfiguration as? NETunnelProviderProtocol
        let configuration = tunnelProtocol?.providerConfiguration ?? [:]
        let server = configuration["server"] as? String ?? tunnelProtocol?.serverAddress ?? "unknown"
        let protocolName = configuration["protocol"] as? String ?? "anyconnect"

        logger.error("OpenConnect engine is not linked. server=\(server, privacy: .private) protocol=\(protocolName, privacy: .public)")
        completionHandler(PacketTunnelStartFailure.openConnectEngineUnavailable(
            server: server,
            protocolName: protocolName
        ).nsError)
    }

    override func stopTunnel(
        with reason: NEProviderStopReason,
        completionHandler: @escaping () -> Void
    ) {
        logger.info("Packet tunnel stopped with reason \(reason.rawValue, privacy: .public)")
        completionHandler()
    }

    override func handleAppMessage(
        _ messageData: Data,
        completionHandler: ((Data?) -> Void)?
    ) {
        completionHandler?(nil)
    }

    override func sleep(completionHandler: @escaping () -> Void) {
        completionHandler()
    }

    override func wake() {}
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
