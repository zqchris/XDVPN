import NetworkExtension
import SwiftUI

struct VPNDashboardView: View {
    @StateObject private var controller: IOSVPNController
    @FocusState private var focusedField: Field?
    @State private var ringRotation: Double = 0

    init() {
        _controller = StateObject(wrappedValue: IOSVPNController())
    }

    init(controller: IOSVPNController) {
        _controller = StateObject(wrappedValue: controller)
    }

    var body: some View {
        ZStack {
            BackgroundView()

            ScrollView {
                VStack(spacing: 24) {
                    HeaderView(isBusy: isPowerTransitioning) {
                        Task { await controller.reload() }
                    }
                    .padding(.top, 18)

                    VStack(spacing: 18) {
                        Text(statusText)
                            .font(.system(size: 30, weight: .semibold, design: .rounded))
                            .foregroundStyle(statusColor.opacity(controller.isConnected ? 1 : 0.72))

                        Button {
                            focusedField = nil
                            handlePowerTap()
                        } label: {
                            PowerControlView(
                                isConnected: controller.isConnected,
                                isBusy: isPowerTransitioning,
                                isEnabled: canUsePowerButton,
                                ringRotation: ringRotation
                            )
                        }
                        .buttonStyle(.plain)
                        .disabled(!canUsePowerButton || isPowerTransitioning)
                        .accessibilityLabel(powerAccessibilityLabel)

                        Text(powerActionTitle)
                            .font(.system(size: 34, weight: .bold, design: .rounded))
                            .foregroundStyle(actionColor)
                    }

                    ServerSummaryView(
                        server: displayServer,
                        mode: "Global VPN"
                    )

                    SettingsPanelView(
                        profile: $controller.profile,
                        password: $controller.password,
                        focusedField: $focusedField
                    )

                    PacketTunnelNoteView(lastError: controller.lastError)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 34)
            }
            .scrollDismissesKeyboard(.immediately)
        }
        .preferredColorScheme(.dark)
        .task {
            await controller.reload()
        }
        .onAppear {
            startRingAnimationIfNeeded()
        }
        .onChange(of: controller.isBusy) { _, _ in
            startRingAnimationIfNeeded()
        }
        .onChange(of: controller.status) { _, _ in
            startRingAnimationIfNeeded()
        }
    }

    private var canUsePowerButton: Bool {
        controller.isConnected || controller.profile.canConnect
    }

    private var isPowerTransitioning: Bool {
        controller.isBusy ||
        controller.status == .connecting ||
        controller.status == .reasserting ||
        controller.status == .disconnecting
    }

    private var displayServer: String {
        controller.profile.server.isEmpty ? "vpn.example.com" : controller.profile.server
    }

    private var statusText: String {
        switch controller.status {
        case .connected:
            return "Connected"
        case .connecting:
            return "Connecting..."
        case .disconnecting:
            return "Disconnecting..."
        case .reasserting:
            return "Reconnecting..."
        default:
            return "Disconnected"
        }
    }

    private var powerActionTitle: String {
        if controller.status == .disconnecting {
            return "Disconnecting"
        }
        if isPowerTransitioning {
            return "Connecting"
        }
        return controller.isConnected ? "Disconnect" : "Connect"
    }

    private var powerAccessibilityLabel: String {
        controller.isConnected ? "Disconnect VPN" : "Connect VPN"
    }

    private var statusColor: Color {
        if controller.isConnected { return .white }
        if isPowerTransitioning { return .cyan }
        return .white.opacity(0.7)
    }

    private var actionColor: Color {
        if !canUsePowerButton { return .white.opacity(0.28) }
        if controller.isConnected { return Color(red: 0.38, green: 0.94, blue: 0.74) }
        return Color(red: 0.18, green: 0.82, blue: 1.0)
    }

    private func handlePowerTap() {
        Task {
            if controller.isConnected {
                controller.disconnect()
            } else {
                await controller.connect()
            }
        }
    }

    private func startRingAnimationIfNeeded() {
        guard isPowerTransitioning else {
            ringRotation = 0
            return
        }
        withAnimation(.linear(duration: 1.25).repeatForever(autoreverses: false)) {
            ringRotation = 360
        }
    }
}

private struct BackgroundView: View {
    var body: some View {
        LinearGradient(
            colors: [
                Color(red: 0.035, green: 0.055, blue: 0.085),
                Color(red: 0.075, green: 0.095, blue: 0.135),
                Color(red: 0.035, green: 0.045, blue: 0.07),
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
        .overlay(alignment: .top) {
            Color.white.opacity(0.05)
                .frame(height: 1)
                .padding(.top, 96)
        }
    }
}

private struct HeaderView: View {
    let isBusy: Bool
    let refresh: () -> Void

    var body: some View {
        HStack {
            Spacer()
            Text("XDVPN")
                .font(.system(size: 34, weight: .bold, design: .rounded))
                .tracking(1.2)
                .foregroundStyle(.white)
            Spacer()
            Button(action: refresh) {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 23, weight: .semibold))
                    .foregroundStyle(.white.opacity(isBusy ? 0.35 : 0.9))
                    .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .disabled(isBusy)
                .accessibilityLabel("Refresh VPN status")
        }
        .overlay(alignment: .leading) {
            Color.clear.frame(width: 44, height: 44)
        }
    }
}

private struct PowerControlView: View {
    let isBusy: Bool
    let isConnected: Bool
    let isEnabled: Bool
    let ringRotation: Double

    init(isConnected: Bool, isBusy: Bool, isEnabled: Bool, ringRotation: Double) {
        self.isConnected = isConnected
        self.isBusy = isBusy
        self.isEnabled = isEnabled
        self.ringRotation = ringRotation
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.08), lineWidth: 24)
                .frame(width: 232, height: 232)

            Circle()
                .trim(from: 0.08, to: trimEnd)
                .stroke(
                    AngularGradient(
                        colors: ringColors,
                        center: .center,
                        startAngle: .degrees(0),
                        endAngle: .degrees(360)
                    ),
                    style: StrokeStyle(lineWidth: 17, lineCap: .round)
                )
                .frame(width: 232, height: 232)
                .rotationEffect(.degrees(isBusy ? ringRotation - 92 : -92))
                .shadow(color: glowColor.opacity(isEnabled ? 0.58 : 0.08), radius: 18)

            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 0.15, green: 0.18, blue: 0.24),
                                Color(red: 0.065, green: 0.075, blue: 0.105),
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 184, height: 184)
                    .shadow(color: .black.opacity(0.52), radius: 22, y: 18)
                    .overlay {
                        Circle()
                            .stroke(.white.opacity(0.08), lineWidth: 1)
                    }

                Image(systemName: "power")
                    .font(.system(size: 70, weight: .regular))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(iconColor)
            }
        }
        .opacity(isEnabled ? 1 : 0.52)
        .frame(width: 260, height: 260)
        .contentShape(Circle())
    }

    private var trimEnd: CGFloat {
        if isBusy { return 0.78 }
        if isConnected { return 0.99 }
        return 0.82
    }

    private var ringColors: [Color] {
        guard isEnabled else {
            return [.white.opacity(0.12), .white.opacity(0.08), .white.opacity(0.12)]
        }
        if isConnected {
            return [
                Color(red: 0.42, green: 0.98, blue: 0.74),
                Color(red: 0.15, green: 0.82, blue: 1.0),
                Color(red: 0.42, green: 0.98, blue: 0.74),
            ]
        }
        return [
            Color(red: 0.12, green: 0.82, blue: 1.0),
            Color(red: 0.16, green: 0.46, blue: 1.0),
            Color(red: 0.16, green: 0.9, blue: 0.94),
        ]
    }

    private var glowColor: Color {
        isConnected ? Color(red: 0.34, green: 0.98, blue: 0.74) : Color(red: 0.1, green: 0.78, blue: 1.0)
    }

    private var iconColor: Color {
        if isConnected { return Color(red: 0.45, green: 1.0, blue: 0.76) }
        if isEnabled { return .white.opacity(0.48) }
        return .white.opacity(0.2)
    }
}

private struct ServerSummaryView: View {
    let server: String
    let mode: String

    var body: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 5) {
                Text(server)
                    .font(.system(size: 22, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text(mode)
                    .font(.system(size: 17, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.58))
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(.white.opacity(0.45))
        }
        .padding(.horizontal, 22)
        .frame(height: 84)
        .background(PanelBackground(cornerRadius: 18))
    }
}

private struct SettingsPanelView: View {
    @Binding var profile: VPNProfile
    @Binding var password: String
    var focusedField: FocusState<Field?>.Binding

    var body: some View {
        VStack(spacing: 0) {
            SettingsTextRow(
                icon: "globe",
                title: "Server",
                placeholder: "vpn.example.com",
                text: $profile.server,
                focusedField: focusedField,
                field: .server,
                keyboardType: .URL
            )

            DividerView()

            SettingsTextRow(
                icon: "person",
                title: "Username",
                placeholder: "chris",
                text: $profile.username,
                focusedField: focusedField,
                field: .username,
                keyboardType: .default
            )

            DividerView()

            SettingsSecureRow(
                password: $password,
                focusedField: focusedField
            )

            DividerView()

            HStack(spacing: 16) {
                SettingsIcon(name: "point.3.connected.trianglepath.dotted")
                Text("Protocol")
                    .font(.system(size: 20, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                Spacer()
                Picker("Protocol", selection: $profile.protocolName) {
                    ForEach(OpenConnectProtocol.allCases) { item in
                        Text(item.rawValue).tag(item)
                    }
                }
                .labelsHidden()
                .tint(.white.opacity(0.62))
            }
            .frame(height: 68)

            DividerView()

            HStack(spacing: 16) {
                SettingsIcon(name: "waveform.path.ecg", color: Color(red: 1.0, green: 0.72, blue: 0.16))
                Text("Packet Tunnel")
                    .font(.system(size: 20, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                Spacer()
                Text("Pending Engine")
                    .font(.system(size: 17, weight: .medium, design: .rounded))
                    .foregroundStyle(Color(red: 1.0, green: 0.72, blue: 0.16))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .frame(height: 68)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 8)
        .background(PanelBackground(cornerRadius: 18))
    }
}

private struct SettingsTextRow: View {
    let icon: String
    let title: String
    let placeholder: String
    @Binding var text: String
    var focusedField: FocusState<Field?>.Binding
    let field: Field
    let keyboardType: UIKeyboardType

    var body: some View {
        HStack(spacing: 16) {
            SettingsIcon(name: icon)
            Text(title)
                .font(.system(size: 20, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
            Spacer(minLength: 12)
            TextField(placeholder, text: $text)
                .keyboardType(keyboardType)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .focused(focusedField, equals: field)
                .font(.system(size: 17, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.78))
                .multilineTextAlignment(.trailing)
                .submitLabel(.next)
        }
        .frame(height: 68)
    }
}

private struct SettingsSecureRow: View {
    @Binding var password: String
    var focusedField: FocusState<Field?>.Binding

    var body: some View {
        HStack(spacing: 16) {
            SettingsIcon(name: "key.horizontal")
            Text("Password")
                .font(.system(size: 20, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
            Spacer(minLength: 12)
            SecureField("Password", text: $password)
                .textContentType(.password)
                .focused(focusedField, equals: .password)
                .font(.system(size: 17, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.78))
                .multilineTextAlignment(.trailing)
        }
        .frame(height: 68)
    }
}

private struct PacketTunnelNoteView: View {
    let lastError: String?

    var body: some View {
        VStack(spacing: 10) {
            Text(lastError ?? "XDVPN will establish a full-device VPN connection.")
                .font(.system(size: 15, weight: .medium, design: .rounded))
                .multilineTextAlignment(.center)
                .foregroundStyle(lastError == nil ? .white.opacity(0.46) : Color(red: 1.0, green: 0.45, blue: 0.38))
                .lineLimit(3)
                .padding(.horizontal, 20)
        }
        .padding(.top, 2)
    }
}

private struct SettingsIcon: View {
    let name: String
    var color: Color = Color(red: 0.28, green: 0.72, blue: 1.0)

    var body: some View {
        Image(systemName: name)
            .font(.system(size: 24, weight: .medium))
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(color)
            .frame(width: 34)
    }
}

private struct PanelBackground: View {
    let cornerRadius: CGFloat

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [
                        Color.white.opacity(0.085),
                        Color.white.opacity(0.04),
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(.white.opacity(0.07), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.18), radius: 18, y: 10)
    }
}

private struct DividerView: View {
    var body: some View {
        Rectangle()
            .fill(.white.opacity(0.085))
            .frame(height: 1)
            .padding(.leading, 50)
    }
}

private enum Field {
    case server
    case username
    case password
}

#Preview("Disconnected") {
    VPNDashboardView(controller: .preview())
}

#Preview("Connected") {
    VPNDashboardView(controller: .preview(status: .connected))
}
