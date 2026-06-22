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

    private var manager: NETunnelProviderManager?
    private var statusObserver: NSObjectProtocol?

    init(loadOnStart: Bool = true) {
        self.profile = Self.loadStoredProfile()
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
        guard profile.canConnect else {
            lastError = "请先填写服务器和用户名"
            return
        }

        await runBusyTask {
            manager = try await configuredManager()
            try await manager?.saveToPreferencesAsync()
            try await manager?.loadFromPreferencesAsync()
            try manager?.connection.startVPNTunnel()
            status = manager?.connection.status ?? .connecting
        }
    }

    func disconnect() {
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
        tunnelProtocol.serverAddress = profile.server
        tunnelProtocol.username = profile.username
        tunnelProtocol.providerConfiguration = profile.providerConfiguration

        if !password.isEmpty {
            tunnelProtocol.passwordReference = try KeychainPersistentReferenceStore.savePassword(
                password,
                account: profile.keychainAccount
            )
        }

        target.protocolConfiguration = tunnelProtocol
        return target
    }

    private func runBusyTask(_ operation: () async throws -> Void) async {
        isBusy = true
        lastError = nil
        do {
            try await operation()
        } catch {
            lastError = error.localizedDescription
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
                self.status = connection.status
            }
        }
    }

    private func persistProfile() {
        guard let data = try? JSONEncoder().encode(profile) else { return }
        UserDefaults.standard.set(data, forKey: "xdvpn.ios.profile")
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
