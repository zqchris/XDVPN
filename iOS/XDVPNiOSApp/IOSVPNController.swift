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
    private var connectionWatchdogTask: Task<Void, Never>?

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
        connectionWatchdogTask?.cancel()
    }

    var isConnected: Bool {
        status == .connected
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
        isBusy = true
        defer { isBusy = false }

        do {
            let managers = try await Self.loadManagers()
            manager = managers.first(where: {
                $0.localizedDescription == SharedConstants.managerDescription
            }) ?? managers.first(where: {
                ($0.protocolConfiguration as? NETunnelProviderProtocol)?
                    .providerBundleIdentifier == SharedConstants.providerBundleIdentifier
            })
            status = manager?.connection.status ?? .invalid
        } catch {
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

        if let environmentError = vpnExecutionPreflightMessage() {
            presentError(environmentError)
            return
        }

        guard hasUsablePasswordCredential else {
            presentError("请填写 VPN 密码。iOS 的 Packet Tunnel 只能通过 Keychain passwordReference 把密码交给扩展。")
            return
        }

        if let runtimeError = openConnectRuntimeUnavailableMessage() {
            presentError(runtimeError)
            return
        }

        isConnectionAttemptInFlight = true
        status = .connecting
        startConnectionWatchdog()
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
            connectionWatchdogTask?.cancel()
        }
    }

    func disconnect() {
        isConnectionAttemptInFlight = false
        connectionWatchdogTask?.cancel()
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
            connectionWatchdogTask?.cancel()
            lastError = nil
        case .disconnected, .invalid:
            if previousStatus == .connecting || previousStatus == .reasserting || previousStatus == .connected {
                isConnectionAttemptInFlight = false
                connectionWatchdogTask?.cancel()
                if lastError == nil {
                    Task {
                        let diagnosticMessage = await providerDiagnosticMessage()
                        presentError(diagnosticMessage ?? Self.tunnelExitedMessage)
                    }
                }
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

    private var hasUsablePasswordCredential: Bool {
        if !password.isEmpty { return true }
        let protocolConfiguration = manager?.protocolConfiguration as? NETunnelProviderProtocol
        return protocolConfiguration?.passwordReference != nil
    }

    private func startConnectionWatchdog() {
        connectionWatchdogTask?.cancel()
        connectionWatchdogTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 20_000_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard let self, self.isConnectionAttemptInFlight else { return }
                self.isConnectionAttemptInFlight = false
                self.status = self.manager?.connection.status ?? .disconnected
                self.presentError(Self.connectionTimeoutMessage)
            }
        }
    }

    private func providerDiagnosticMessage() async -> String? {
        guard let session = manager?.connection as? NETunnelProviderSession else { return nil }
        let request = Data("diagnostics".utf8)

        do {
            let response = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Data?, Error>) in
                do {
                    try session.sendProviderMessage(request) { response in
                        continuation.resume(returning: response)
                    }
                } catch {
                    continuation.resume(throwing: error)
                }
            }
            guard let response,
                  let json = try? JSONSerialization.jsonObject(with: response) as? [String: String],
                  let message = json["lastStartError"],
                  !message.isEmpty
            else { return nil }
            return message
        } catch {
            return nil
        }
    }

    private func openConnectRuntimeUnavailableMessage() -> String? {
        let candidates = Self.openConnectRuntimeCandidates()
        let fileManager = FileManager.default
        let found = candidates.contains { candidate in
            var isDirectory: ObjCBool = false
            return fileManager.fileExists(atPath: candidate.path, isDirectory: &isDirectory) && !isDirectory.boolValue
        }
        guard !found else { return nil }

        return """
        连接失败：当前 iOS 构建里还没有嵌入 OpenConnect runtime。
        需要把 libopenconnect.dylib 或 OpenConnect.framework 放进 App/PacketTunnel 的 Frameworks 目录后，Packet Tunnel 才能建立真实 VPN。
        """
    }

    private func vpnExecutionPreflightMessage() -> String? {
        #if targetEnvironment(simulator)
        return "连接失败：当前是 iOS Simulator。Simulator 可以预览 UI，但没有真实 Packet Tunnel 运行环境；请打开 Simulator Preview 测交互，或用带 Network Extension entitlement 的真机签名包测试 VPN。"
        #else
        return nil
        #endif
    }

    private static func openConnectRuntimeCandidates() -> [URL] {
        var candidates: [URL] = []
        let bundleURL = Bundle.main.bundleURL
        let frameworkNames = [
            "libopenconnect.dylib",
            "OpenConnect.framework/OpenConnect",
            "openconnect.framework/openconnect",
        ]

        let searchRoots: [URL?] = [
            Bundle.main.privateFrameworksURL,
            bundleURL.appendingPathComponent("Frameworks"),
            bundleURL.appendingPathComponent("PlugIns/PacketTunnel.appex/Frameworks"),
            bundleURL.appendingPathComponent("PlugIns/PacketTunnel.appex"),
        ]

        for root in searchRoots.compactMap({ $0 }) {
            for name in frameworkNames {
                candidates.append(root.appendingPathComponent(name))
            }
        }
        return candidates
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

    private static var tunnelExitedMessage: String {
        "连接失败：Packet Tunnel 在握手完成前退出。请检查服务器、账号密码、证书信任或二次验证要求；如果当前构建缺少 OpenConnect runtime，连接会在启动阶段直接失败。"
    }

    private static var connectionTimeoutMessage: String {
        "连接超时：Packet Tunnel 20 秒内没有进入已连接状态。请检查服务器是否可达、账号密码、证书信任和二次验证。"
    }

    private static func userFacingMessage(for error: Error) -> String {
        let nsError = error as NSError
        let description = nsError.localizedDescription
        if nsError.localizedDescription.localizedCaseInsensitiveContains("IPC failed") {
            #if targetEnvironment(simulator)
            return "连接失败：当前 iOS Simulator 没有可用的 Network Extension nehelper 服务，真实 Packet Tunnel 不能在这个模拟器里启动。请用 Simulator Preview 测 UI，或用带 packet-tunnel-provider entitlement 的真机包测试真实 VPN。"
            #else
            return "连接失败：系统只返回了 IPC failed，通常表示 Packet Tunnel 扩展启动后立刻失败或当前签名/Network Extension 权限不可用。请重新保存配置后再试。"
            #endif
        }

        if description.localizedCaseInsensitiveContains("entitlement") ||
            description.localizedCaseInsensitiveContains("permission") ||
            description.localizedCaseInsensitiveContains("not allowed") ||
            description.localizedCaseInsensitiveContains("denied") {
            return "连接失败：当前签名或 provisioning profile 没有可用的 Network Extension / packet-tunnel-provider 权限。请用 Apple Developer 证书同时签宿主 App 和 PacketTunnel.appex，并先运行 scripts/check-ios-vpn-signing.sh 检查产物。"
        }

        let parts = [
            description,
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
