import Foundation
import NetworkExtension
import os.log

final class PacketTunnelProvider: NEPacketTunnelProvider {
    private let logger = Logger(subsystem: "com.kafeifei.xdvpn.ios", category: "PacketTunnel")
    private var activeEngine: PacketTunnelEngine?

    override func startTunnel(
        options: [String: NSObject]?,
        completionHandler: @escaping (Error?) -> Void
    ) {
        let configuration = PacketTunnelConfiguration(
            protocolConfiguration: protocolConfiguration as? NETunnelProviderProtocol
        )
        let engine = makeEngine(for: configuration.engineMode)
        activeEngine = engine
        logger.info("Starting packet tunnel engine=\(configuration.engineMode.rawValue, privacy: .public)")
        engine.start(
            provider: self,
            configuration: configuration,
            completionHandler: completionHandler
        )
    }

    override func stopTunnel(
        with reason: NEProviderStopReason,
        completionHandler: @escaping () -> Void
    ) {
        logger.info("Packet tunnel stop requested reason=\(reason.rawValue, privacy: .public)")
        let engine = activeEngine
        activeEngine = nil
        engine?.stop(provider: self, reason: reason, completionHandler: completionHandler)
            ?? completionHandler()
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

    private func makeEngine(for mode: PacketTunnelEngineMode) -> PacketTunnelEngine {
        switch mode {
        case .demo:
            return DemoPacketTunnelEngine()
        case .openconnect:
            return OpenConnectPacketTunnelEngine()
        }
    }
}
