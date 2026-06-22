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

    var displayName: String {
        switch self {
        case .anyconnect:
            return "AnyConnect"
        case .nc:
            return "NC"
        case .gp:
            return "GlobalProtect"
        case .pulse:
            return "Pulse"
        case .f5:
            return "F5"
        case .fortinet:
            return "Fortinet"
        case .array:
            return "Array"
        }
    }
}

struct VPNProfile: Codable, Equatable {
    var protocolName: OpenConnectProtocol = .anyconnect
    var server: String = ""
    var username: String = ""
    var routePolicy: RoutePolicy = RoutePolicy()

    init(
        protocolName: OpenConnectProtocol = .anyconnect,
        server: String = "",
        username: String = "",
        routePolicy: RoutePolicy = RoutePolicy()
    ) {
        self.protocolName = protocolName
        self.server = server
        self.username = username
        self.routePolicy = routePolicy
    }

    var canConnect: Bool {
        !server.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var keychainAccount: String {
        "\(username)@\(server)"
    }

    var providerConfiguration: [String: Any] {
        let includedCIDRs = routePolicy.isEnabled ? routePolicy.includedCIDRs : []
        let includedDomains = routePolicy.isEnabled ? routePolicy.includedDomainSuffixes : []
        let policyHasRules = !includedCIDRs.isEmpty || !includedDomains.isEmpty
        let splitEnabled = routePolicy.isEnabled && policyHasRules

        return [
            "configurationVersion": SharedConstants.providerConfigurationVersion,
            "protocol": protocolName.rawValue,
            "server": server,
            "username": username,
            "runningMode": splitEnabled ? "split" : "full",
            "splitEnabled": splitEnabled,
            "splitCIDRs": includedCIDRs,
            "splitDomains": includedDomains,
            "routePolicyEnabled": routePolicy.isEnabled,
            "routePolicyMode": "vpn-included",
        ]
    }
}

extension VPNProfile {
    private enum CodingKeys: String, CodingKey {
        case protocolName
        case server
        case username
        case routePolicy
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        protocolName = try container.decodeIfPresent(OpenConnectProtocol.self, forKey: .protocolName) ?? .anyconnect
        server = try container.decodeIfPresent(String.self, forKey: .server) ?? ""
        username = try container.decodeIfPresent(String.self, forKey: .username) ?? ""
        routePolicy = try container.decodeIfPresent(RoutePolicy.self, forKey: .routePolicy) ?? RoutePolicy()
    }
}
