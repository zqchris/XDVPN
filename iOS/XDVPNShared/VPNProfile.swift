import Foundation

enum OpenConnectProtocol: String, CaseIterable, Codable, Identifiable {
    case anyconnect
    case nc
    case gp
    case pulse
    case f5
    case fortinet
    case array

    var id: String { rawValue }
}

struct VPNProfile: Codable, Equatable {
    var protocolName: OpenConnectProtocol = .anyconnect
    var server: String = ""
    var username: String = ""

    var canConnect: Bool {
        !server.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var keychainAccount: String {
        "\(username)@\(server)"
    }

    var providerConfiguration: [String: Any] {
        [
            "configurationVersion": SharedConstants.providerConfigurationVersion,
            "protocol": protocolName.rawValue,
            "server": server,
            "username": username,
            "runningMode": "full",
        ]
    }
}
