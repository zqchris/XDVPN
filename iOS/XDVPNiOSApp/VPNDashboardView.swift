import NetworkExtension
import SwiftUI

struct VPNDashboardView: View {
    @StateObject private var controller: IOSVPNController
    @FocusState private var focusedField: Field?
    @State private var ringRotation: Double = 0
    @State private var presentedError: PresentedError?

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
                    HeaderView(isBusy: controller.isBusy || isPowerTransitioning) {
                        Task { await controller.reload() }
                    }
                    .padding(.top, 18)

                    VStack(spacing: 20) {
                        Text(statusText)
                            .font(.system(size: 30, weight: .semibold, design: .rounded))
                            .foregroundStyle(statusColor)

                        Button {
                            focusedField = nil
                            handlePowerTap()
                        } label: {
                            PowerControlView(
                                isConnected: isTunnelConnected,
                                isBusy: isPowerTransitioning,
                                isEnabled: canUsePowerButton,
                                showsRing: isPowerTransitioning || isTunnelConnected,
                                tone: powerRingTone,
                                ringRotation: ringRotation
                            )
                        }
                        .buttonStyle(.plain)
                        .disabled(!canUsePowerButton || isPowerTransitioning)
                        .accessibilityLabel(powerAccessibilityLabel)
                    }

                    if let lastError = controller.lastError {
                        ConnectionErrorBanner(message: lastError)
                            .transition(.opacity.combined(with: .move(edge: .top)))
                    }

                    ServerSummaryView(
                        server: displayServer,
                        mode: routeModeTitle
                    )

                    SettingsPanelView(
                        profile: $controller.profile,
                        password: $controller.password,
                        demoTunnelEnabled: $controller.demoTunnelEnabled,
                        focusedField: $focusedField
                    )

                    RoutePolicyPanelView(
                        policy: $controller.profile.routePolicy,
                        focusedField: $focusedField
                    )
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
        .onChange(of: controller.lastError) { _, message in
            guard let message, !message.isEmpty else { return }
            presentedError = PresentedError(message: message)
        }
        .alert(item: $presentedError) { error in
            Alert(
                title: Text("连接失败"),
                message: Text(error.message),
                dismissButton: .default(Text("知道了"))
            )
        }
    }

    private var canUsePowerButton: Bool {
        true
    }

    private var isPowerTransitioning: Bool {
        controller.status == .connecting ||
        controller.status == .reasserting ||
        controller.status == .disconnecting
    }

    private var isTunnelConnected: Bool {
        controller.status == .connected
    }

    private var displayServer: String {
        if controller.demoTunnelEnabled && controller.profile.server.isEmpty { return "demo.xdvpn.local" }
        return controller.profile.server.isEmpty ? "vpn.example.com" : controller.profile.server
    }

    private var routeModeTitle: String {
        if controller.demoTunnelEnabled { return "Simulator Preview" }
        return controller.profile.routePolicy.isEnabled && controller.profile.routePolicy.hasRules
            ? "Split VPN"
            : "Global VPN"
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

    private var powerAccessibilityLabel: String {
        isTunnelConnected ? "Disconnect VPN" : "Connect VPN"
    }

    private var statusColor: Color {
        if powerRingTone == .danger { return Color(red: 1.0, green: 0.36, blue: 0.34) }
        if powerRingTone == .warning { return Color(red: 1.0, green: 0.76, blue: 0.24) }
        if isTunnelConnected { return Color(red: 0.18, green: 0.82, blue: 1.0) }
        if isPowerTransitioning { return Color(red: 0.18, green: 0.82, blue: 1.0) }
        return .white.opacity(0.72)
    }

    private var powerRingTone: PowerRingTone {
        if controller.status == .reasserting { return .warning }
        if controller.lastError != nil && !isPowerTransitioning { return .danger }
        return .primary
    }

    private func handlePowerTap() {
        Task {
            if isTunnelConnected {
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
        withAnimation(.linear(duration: 0.95).repeatForever(autoreverses: false)) {
            ringRotation = 360
        }
    }
}

private struct PresentedError: Identifiable {
    let id = UUID()
    let message: String
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

private struct ConnectionErrorBanner: View {
    let message: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 19, weight: .semibold))
                .foregroundStyle(Color(red: 1.0, green: 0.54, blue: 0.32))
                .frame(width: 24, height: 24)

            Text(message)
                .font(.system(size: 15, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.9))
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(red: 0.28, green: 0.055, blue: 0.045).opacity(0.86))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color(red: 1.0, green: 0.38, blue: 0.32).opacity(0.28), lineWidth: 1)
        }
    }
}

private enum PowerRingTone: Equatable {
    case primary
    case warning
    case danger

    var ringColors: [Color] {
        switch self {
        case .primary:
            return [
                Color(red: 0.16, green: 0.52, blue: 1.0),
                Color(red: 0.18, green: 0.82, blue: 1.0),
                Color(red: 0.16, green: 0.52, blue: 1.0),
            ]
        case .warning:
            return [
                Color(red: 1.0, green: 0.62, blue: 0.16),
                Color(red: 1.0, green: 0.84, blue: 0.30),
                Color(red: 1.0, green: 0.62, blue: 0.16),
            ]
        case .danger:
            return [
                Color(red: 1.0, green: 0.28, blue: 0.34),
                Color(red: 1.0, green: 0.48, blue: 0.26),
                Color(red: 1.0, green: 0.28, blue: 0.34),
            ]
        }
    }

    var glowColor: Color {
        switch self {
        case .primary:
            return Color(red: 0.12, green: 0.68, blue: 1.0)
        case .warning:
            return Color(red: 1.0, green: 0.68, blue: 0.16)
        case .danger:
            return Color(red: 1.0, green: 0.25, blue: 0.24)
        }
    }

    var solidRingColor: Color {
        switch self {
        case .primary:
            return Color(red: 0.18, green: 0.78, blue: 1.0)
        case .warning:
            return Color(red: 1.0, green: 0.74, blue: 0.22)
        case .danger:
            return Color(red: 1.0, green: 0.34, blue: 0.32)
        }
    }
}

private struct PowerControlView: View {
    let isBusy: Bool
    let isConnected: Bool
    let isEnabled: Bool
    let showsRing: Bool
    let tone: PowerRingTone
    let ringRotation: Double

    init(
        isConnected: Bool,
        isBusy: Bool,
        isEnabled: Bool,
        showsRing: Bool,
        tone: PowerRingTone,
        ringRotation: Double
    ) {
        self.isConnected = isConnected
        self.isBusy = isBusy
        self.isEnabled = isEnabled
        self.showsRing = showsRing
        self.tone = tone
        self.ringRotation = ringRotation
    }

    var body: some View {
        ZStack {
            if showsRing {
                Circle()
                    .stroke(Color.white.opacity(isEnabled ? 0.045 : 0.025), lineWidth: 24)
                    .frame(width: 232, height: 232)

                ringStroke
                    .frame(width: 232, height: 232)
                    .rotationEffect(.degrees(isBusy ? ringRotation - 92 : 0))
                    .shadow(color: glowColor.opacity(isEnabled ? glowOpacity : 0.08), radius: glowRadius)
            }

            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [
                                innerStartColor,
                                innerEndColor,
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
        .animation(.smooth(duration: 0.2), value: isBusy)
        .animation(.smooth(duration: 0.2), value: isConnected)
        .animation(.smooth(duration: 0.2), value: isEnabled)
        .animation(.smooth(duration: 0.2), value: showsRing)
    }

    @ViewBuilder
    private var ringStroke: some View {
        if isBusy {
            Circle()
                .stroke(
                    ringGradient,
                    style: StrokeStyle(lineWidth: 18, lineCap: .butt)
                )
        } else {
            Circle()
                .stroke(
                    ringSolidColor,
                    style: StrokeStyle(lineWidth: 18, lineCap: .butt)
                )
        }
    }

    private var ringGradient: AngularGradient {
        AngularGradient(
            colors: ringColors,
            center: .center,
            startAngle: .degrees(0),
            endAngle: .degrees(360)
        )
    }

    private var ringColors: [Color] {
        guard isEnabled else {
            return [.white.opacity(0.12), .white.opacity(0.08), .white.opacity(0.12)]
        }
        return tone.ringColors
    }

    private var ringSolidColor: Color {
        guard isEnabled else { return .white.opacity(0.1) }
        return tone.solidRingColor
    }

    private var glowColor: Color {
        tone.glowColor
    }

    private var glowOpacity: Double {
        if isBusy { return 0.68 }
        if isConnected { return 0.58 }
        return 0.38
    }

    private var glowRadius: CGFloat {
        isBusy || isConnected ? 18 : 12
    }

    private var innerStartColor: Color {
        if isBusy { return Color(red: 0.09, green: 0.42, blue: 0.84) }
        if isConnected { return Color(red: 0.08, green: 0.34, blue: 0.74) }
        if isEnabled { return Color(red: 0.08, green: 0.27, blue: 0.60) }
        return Color(red: 0.12, green: 0.14, blue: 0.18)
    }

    private var innerEndColor: Color {
        if isBusy { return Color(red: 0.02, green: 0.12, blue: 0.34) }
        if isConnected { return Color(red: 0.018, green: 0.10, blue: 0.30) }
        if isEnabled { return Color(red: 0.018, green: 0.08, blue: 0.24) }
        return Color(red: 0.055, green: 0.06, blue: 0.08)
    }

    private var iconColor: Color {
        if isEnabled { return .white.opacity(isBusy || isConnected ? 0.95 : 0.88) }
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
    @Binding var demoTunnelEnabled: Bool
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

            ProtocolSelectorSection(selection: $profile.protocolName)

            DividerView()

            Toggle(isOn: $profile.allowUntrustedServerCertificate) {
                HStack(spacing: 16) {
                    SettingsIcon(
                        name: profile.allowUntrustedServerCertificate ? "checkmark.shield.fill" : "shield",
                        color: profile.allowUntrustedServerCertificate
                            ? Color(red: 1.0, green: 0.74, blue: 0.22)
                            : Color(red: 0.28, green: 0.72, blue: 1.0)
                    )
                    Text("Trust Certificate")
                        .font(.system(size: 20, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                    Spacer()
                }
            }
            .toggleStyle(.switch)
            .tint(Color(red: 1.0, green: 0.74, blue: 0.22))
            .frame(height: 68)

#if DEBUG
            DividerView()

            Toggle(isOn: $demoTunnelEnabled) {
                HStack(spacing: 16) {
                    SettingsIcon(name: "iphone.gen3.radiowaves.left.and.right", color: demoTunnelEnabled ? Color(red: 0.18, green: 0.82, blue: 1.0) : Color(red: 1.0, green: 0.72, blue: 0.16))
                    Text("Simulator Preview")
                        .font(.system(size: 20, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                    Spacer()
                }
            }
            .toggleStyle(.switch)
            .tint(Color(red: 0.18, green: 0.82, blue: 1.0))
            .frame(height: 68)
#endif
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 8)
        .background(PanelBackground(cornerRadius: 18))
    }
}

private struct ProtocolSelectorSection: View {
    @Binding var selection: OpenConnectProtocol

    private let columns = [
        GridItem(.adaptive(minimum: 128), spacing: 8, alignment: .leading),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 16) {
                SettingsIcon(name: "point.3.connected.trianglepath.dotted")
                Text("Protocol")
                    .font(.system(size: 20, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                Spacer()
                Text(selection.displayName)
                    .font(.system(size: 17, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.58))
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }

            LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
                ForEach(OpenConnectProtocol.allCases) { item in
                    ProtocolChoiceChip(
                        title: item.displayName,
                        isSelected: selection == item
                    ) {
                        selection = item
                    }
                }
            }
        }
        .padding(.vertical, 14)
    }
}

private struct ProtocolChoiceChip: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Spacer(minLength: 4)
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 15, weight: .semibold))
            }
            .foregroundStyle(isSelected ? Color(red: 0.28, green: 0.74, blue: 1.0) : .white.opacity(0.5))
            .frame(maxWidth: .infinity)
            .frame(height: 38)
            .padding(.horizontal, 10)
            .background {
                Capsule()
                    .fill(isSelected ? Color(red: 0.08, green: 0.24, blue: 0.42).opacity(0.72) : Color.white.opacity(0.055))
            }
            .overlay {
                Capsule()
                    .stroke(isSelected ? Color(red: 0.28, green: 0.74, blue: 1.0).opacity(0.38) : .white.opacity(0.08), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
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

private struct RoutePolicyPanelView: View {
    @Binding var policy: RoutePolicy
    var focusedField: FocusState<Field?>.Binding

    var body: some View {
        VStack(spacing: 0) {
            Toggle(isOn: $policy.isEnabled) {
                HStack(spacing: 16) {
                    SettingsIcon(name: "arrow.triangle.branch", color: policyColor)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("VPN Policy")
                            .font(.system(size: 20, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white)
                        Text(policy.isEnabled ? policySummary : "Global VPN")
                            .font(.system(size: 15, weight: .medium, design: .rounded))
                            .foregroundStyle(.white.opacity(0.46))
                            .lineLimit(1)
                            .minimumScaleFactor(0.74)
                    }
                }
            }
            .toggleStyle(.switch)
            .tint(policyColor)
            .frame(height: 72)

            if policy.isEnabled {
                DividerView()

                PolicyPresetSection(policy: $policy)

                DividerView()

                PolicyEditorRow(
                    icon: "number",
                    title: "Custom CIDR",
                    placeholder: "172.20.0.0/16, 10.20.30.0/24",
                    text: $policy.customCIDRText,
                    focusedField: focusedField,
                    field: .customCIDRs
                )

                DividerView()

                PolicyEditorRow(
                    icon: "at",
                    title: "Domain Suffixes",
                    placeholder: "corp.example.com, *.internal.example",
                    text: $policy.domainSuffixText,
                    focusedField: focusedField,
                    field: .domainSuffixes
                )
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 8)
        .background(PanelBackground(cornerRadius: 18))
        .animation(.smooth(duration: 0.18), value: policy.isEnabled)
    }

    private var policyColor: Color {
        Color(red: 0.2, green: 0.88, blue: 0.94)
    }

    private var policySummary: String {
        let cidrCount = policy.includedCIDRs.count
        let domainCount = policy.includedDomainSuffixes.count
        if cidrCount == 0 && domainCount == 0 { return "No rules selected" }

        var parts: [String] = []
        if cidrCount > 0 { parts.append("\(cidrCount) CIDR") }
        if domainCount > 0 { parts.append("\(domainCount) domains") }
        return parts.joined(separator: " · ") + " via VPN"
    }
}

private struct PolicyPresetSection: View {
    @Binding var policy: RoutePolicy

    private let columns = [
        GridItem(.adaptive(minimum: 126), spacing: 8, alignment: .leading),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 16) {
                SettingsIcon(name: "point.topleft.down.curvedto.point.bottomright.up")
                Text("Private CIDR")
                    .font(.system(size: 20, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                Spacer()
            }

            LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
                PolicyChip(label: "10.0.0.0/8", isOn: $policy.includePrivate10)
                PolicyChip(label: "172.16.0.0/12", isOn: $policy.includePrivate172)
                PolicyChip(label: "192.168.0.0/16", isOn: $policy.includePrivate192)
            }
        }
        .padding(.vertical, 14)
    }
}

private struct PolicyChip: View {
    let label: String
    @Binding var isOn: Bool

    var body: some View {
        Button {
            isOn.toggle()
        } label: {
            HStack(spacing: 7) {
                Text(label)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
                Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 15, weight: .semibold))
            }
            .foregroundStyle(isOn ? Color(red: 0.2, green: 0.9, blue: 0.95) : .white.opacity(0.48))
            .frame(maxWidth: .infinity)
            .frame(height: 38)
            .padding(.horizontal, 10)
            .background(
                Capsule()
                    .fill(isOn ? Color(red: 0.08, green: 0.34, blue: 0.42).opacity(0.72) : Color.white.opacity(0.055))
            )
            .overlay {
                Capsule()
                    .stroke(isOn ? Color(red: 0.2, green: 0.9, blue: 0.95).opacity(0.38) : .white.opacity(0.08), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
    }
}

private struct PolicyEditorRow: View {
    let icon: String
    let title: String
    let placeholder: String
    @Binding var text: String
    var focusedField: FocusState<Field?>.Binding
    let field: Field

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack(spacing: 16) {
                SettingsIcon(name: icon)
                Text(title)
                    .font(.system(size: 20, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                Spacer()
            }

            TextField(placeholder, text: $text, axis: .vertical)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .focused(focusedField, equals: field)
                .font(.system(size: 16, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.78))
                .lineLimit(3, reservesSpace: true)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(.black.opacity(0.2))
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(.white.opacity(0.08), lineWidth: 1)
                }
        }
        .padding(.vertical, 14)
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
    case customCIDRs
    case domainSuffixes
}

#Preview("Disconnected") {
    VPNDashboardView(controller: .preview())
}

#Preview("Connected") {
    VPNDashboardView(controller: .preview(status: .connected))
}
