import Foundation
import NetworkExtension

@MainActor
final class IOSVPNController: ObservableObject {
    @Published var profile: VPNProfile {
        didSet { persistProfile() }
    }
    @Published var password: String = ""
    @Published private(set) var status: NEVPNStatus = .invalid
    @Published private(set) var isBusy = false
    @Published private(set) var lastError: String?
    @Published var demoTunnelEnabled: Bool {
        didSet {
            UserDefaults.standard.set(demoTunnelEnabled, forKey: "xdvpn.ios.demoTunnelEnabled")
            if demoTunnelEnabled {
                lastError = nil
                if status == .invalid { status = .disconnected }
            } else if oldValue {
                isConnectionAttemptInFlight = false
                isBusy = false
                status = manager?.connection.status ?? .disconnected
            }
        }
    }

    private var manager: NETunnelProviderManager?
    private var statusObserver: NSObjectProtocol?
    private var isConnectionAttemptInFlight = false

    init(loadOnStart: Bool = true) {
        self.profile = Self.loadStoredProfile()
        self.demoTunnelEnabled = UserDefaults.standard.bool(forKey: "xdvpn.ios.demoTunnelEnabled")
        installStatusObserver()
        if loadOnStart {
            Task { await reload() }
        }
    }

    deinit {
        if let statusObserver {
            NotificationCenter.default.removeObserver(statusObserver)
        }
    }

    var isConnected: Bool {
        status == .connected || status == .connecting || status == .reasserting
    }

    var statusTitle: String {
        switch status {
        case .invalid: return "未配置"
        case .disconnected: return "未连接"
        case .connecting: return "连接中"
        case .connected: return "已连接"
        case .reasserting: return "重连中"
        case .disconnecting: return "断开中"
        @unknown default: return "未知状态"
        }
    }

    func reload() async {
        await runBusyTask {
            let managers = try await Self.loadManagers()
            manager = managers.first(where: {
                $0.localizedDescription == SharedConstants.managerDescription
            }) ?? managers.first(where: {
                ($0.protocolConfiguration as? NETunnelProviderProtocol)?
                    .providerBundleIdentifier == SharedConstants.providerBundleIdentifier
            })
            status = manager?.connection.status ?? .invalid
        }
    }

    func saveProfile() async {
        await runBusyTask {
            manager = try await configuredManager()
            try await manager?.saveToPreferencesAsync()
            try await manager?.loadFromPreferencesAsync()
            status = manager?.connection.status ?? .disconnected
        }
    }

    func connect() async {
        if demoTunnelEnabled {
            await connectDemoTunnel()
            return
        }

        guard demoTunnelEnabled || profile.canConnect else {
            presentError("请先填写服务器和用户名")
            return
        }

        isConnectionAttemptInFlight = true
        status = .connecting
        try? await Task.sleep(nanoseconds: 350_000_000)

        await runBusyTask(fallbackStatus: .disconnected) {
            manager = try await configuredManager()
            try await manager?.saveToPreferencesAsync()
            try await manager?.loadFromPreferencesAsync()
            try manager?.connection.startVPNTunnel()
            status = manager?.connection.status ?? .connecting
        }

        if lastError != nil {
            isConnectionAttemptInFlight = false
        }
    }

    func disconnect() {
        isConnectionAttemptInFlight = false
        if demoTunnelEnabled {
            disconnectDemoTunnel()
            return
        }

        status = .disconnecting
        manager?.connection.stopVPNTunnel()
        status = manager?.connection.status ?? .disconnecting
    }

    private func configuredManager() async throws -> NETunnelProviderManager {
        let target = manager ?? NETunnelProviderManager()
        target.localizedDescription = SharedConstants.managerDescription
        target.isEnabled = true

        let tunnelProtocol = (target.protocolConfiguration as? NETunnelProviderProtocol)
            ?? NETunnelProviderProtocol()
        tunnelProtocol.providerBundleIdentifier = SharedConstants.providerBundleIdentifier
        tunnelProtocol.serverAddress = effectiveServer
        tunnelProtocol.username = effectiveUsername
        tunnelProtocol.providerConfiguration = effectiveProviderConfiguration

        if !demoTunnelEnabled && !password.isEmpty {
            tunnelProtocol.passwordReference = try KeychainPersistentReferenceStore.savePassword(
                password,
                account: profile.keychainAccount
            )
        }

        target.protocolConfiguration = tunnelProtocol
        return target
    }

    private func runBusyTask(
        fallbackStatus: NEVPNStatus? = nil,
        _ operation: () async throws -> Void
    ) async {
        isBusy = true
        lastError = nil
        do {
            try await operation()
        } catch {
            presentError(Self.userFacingMessage(for: error))
            if let fallbackStatus {
                status = manager?.connection.status ?? fallbackStatus
            }
        }
        isBusy = false
    }

    private func installStatusObserver() {
        statusObserver = NotificationCenter.default.addObserver(
            forName: .NEVPNStatusDidChange,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self,
                  let connection = notification.object as? NEVPNConnection
            else { return }
            Task { @MainActor in
                let previousStatus = self.status
                self.status = connection.status
                self.handleStatusChange(from: previousStatus, to: connection.status)
            }
        }
    }

    private func handleStatusChange(from previousStatus: NEVPNStatus, to newStatus: NEVPNStatus) {
        guard isConnectionAttemptInFlight else { return }

        switch newStatus {
        case .connected:
            isConnectionAttemptInFlight = false
            lastError = nil
        case .disconnected, .invalid:
            if previousStatus == .connecting || previousStatus == .reasserting || previousStatus == .connected {
                isConnectionAttemptInFlight = false
                presentError(Self.packetTunnelEngineUnavailableMessage)
            }
        default:
            break
        }
    }

    private func presentError(_ message: String) {
        lastError = message
    }

    private func persistProfile() {
        guard let data = try? JSONEncoder().encode(profile) else { return }
        UserDefaults.standard.set(data, forKey: "xdvpn.ios.profile")
    }

    private func connectDemoTunnel() async {
        isConnectionAttemptInFlight = false
        isBusy = true
        lastError = nil
        status = .connecting
        try? await Task.sleep(nanoseconds: 850_000_000)
        guard demoTunnelEnabled else {
            status = manager?.connection.status ?? .disconnected
            isBusy = false
            return
        }
        status = .connected
        isBusy = false
    }

    private func disconnectDemoTunnel() {
        isBusy = true
        status = .disconnecting
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 360_000_000)
            guard self.demoTunnelEnabled else {
                self.status = self.manager?.connection.status ?? .disconnected
                self.isBusy = false
                return
            }
            self.status = .disconnected
            self.isBusy = false
        }
    }

    private var effectiveServer: String {
        if demoTunnelEnabled && profile.server.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "demo.xdvpn.local"
        }
        return profile.server
    }

    private var effectiveUsername: String {
        if demoTunnelEnabled && profile.username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "demo"
        }
        return profile.username
    }

    private var effectiveProviderConfiguration: [String: Any] {
        var configuration = profile.providerConfiguration(
            engineMode: demoTunnelEnabled ? "demo" : "openconnect"
        )
        configuration["server"] = effectiveServer
        configuration["username"] = effectiveUsername
        configuration["demoTunnelEnabled"] = demoTunnelEnabled
        return configuration
    }

    private static func loadStoredProfile() -> VPNProfile {
        guard let data = UserDefaults.standard.data(forKey: "xdvpn.ios.profile"),
              let profile = try? JSONDecoder().decode(VPNProfile.self, from: data)
        else { return VPNProfile() }
        return profile
    }

    private static func loadManagers() async throws -> [NETunnelProviderManager] {
        try await withCheckedThrowingContinuation { continuation in
            NETunnelProviderManager.loadAllFromPreferences { managers, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: managers ?? [])
                }
            }
        }
    }

    static func preview(status: NEVPNStatus = .disconnected) -> IOSVPNController {
        let controller = IOSVPNController(loadOnStart: false)
        controller.profile = VPNProfile(
            protocolName: .anyconnect,
            server: "vpn.example.com",
            username: "chris"
        )
        controller.status = status
        return controller
    }

    private static var packetTunnelEngineUnavailableMessage: String {
        "连接失败：iOS Packet Tunnel 已启动，但 OpenConnect 协议引擎尚未接入。当前版本只能保存配置和路由策略，还不能真正建立 AnyConnect/OpenConnect 隧道。"
    }

    private static func userFacingMessage(for error: Error) -> String {
        let nsError = error as NSError
        if nsError.localizedDescription.localizedCaseInsensitiveContains("IPC failed") {
            return "\(packetTunnelEngineUnavailableMessage)\n系统返回：IPC failed"
        }

        let parts = [
            nsError.localizedDescription,
            nsError.localizedFailureReason,
            nsError.localizedRecoverySuggestion,
        ]
        .compactMap { text -> String? in
            guard let text, !text.isEmpty else { return nil }
            return text
        }

        if parts.isEmpty {
            return "连接失败：\(String(describing: error))"
        }
        return parts.joined(separator: "\n")
    }
}

private extension NETunnelProviderManager {
    func saveToPreferencesAsync() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            saveToPreferences { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }

    func loadFromPreferencesAsync() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            loadFromPreferences { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }
}
