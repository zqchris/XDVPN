import Foundation

struct RoutePolicy: Codable, Equatable {
    var isEnabled: Bool = false
    var includePrivate10: Bool = true
    var includePrivate172: Bool = true
    var includePrivate192: Bool = false
    var customCIDRText: String = ""
    var domainSuffixText: String = ""

    var includedCIDRs: [String] {
        var output: [String] = []
        if includePrivate10 { output.append("10.0.0.0/8") }
        if includePrivate172 { output.append("172.16.0.0/12") }
        if includePrivate192 { output.append("192.168.0.0/16") }

        output.append(contentsOf: customCIDRText
            .components(separatedBy: CharacterSet(charactersIn: ",\n"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .filter(Self.isValidCIDR))

        return Self.deduplicated(output)
    }

    var includedDomainSuffixes: [String] {
        Self.deduplicated(domainSuffixText
            .components(separatedBy: CharacterSet(charactersIn: ",\n"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .map { $0.hasPrefix("*.") ? String($0.dropFirst(2)) : $0 }
            .filter { !$0.isEmpty && !$0.hasPrefix("#") && Self.isValidDomainSuffix($0) })
    }

    var hasRules: Bool {
        !includedCIDRs.isEmpty || !includedDomainSuffixes.isEmpty
    }

    static func isValidDomainSuffix(_ value: String) -> Bool {
        let labels = value.split(separator: ".", omittingEmptySubsequences: false)
        guard !labels.isEmpty else { return false }
        return labels.allSatisfy { label in
            !label.isEmpty && label.count <= 63
                && label.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-") }
                && !label.hasPrefix("-") && !label.hasSuffix("-")
        }
    }

    static func isValidCIDR(_ value: String) -> Bool {
        let parts = value.split(separator: "/", maxSplits: 1, omittingEmptySubsequences: false)
        guard parts.count == 2,
              let maskLength = Int(parts[1]),
              (0...32).contains(maskLength) else { return false }

        let octets = parts[0].split(separator: ".", omittingEmptySubsequences: false)
        guard octets.count == 4 else { return false }
        return octets.allSatisfy { segment in
            guard let number = Int(segment) else { return false }
            return (0...255).contains(number)
        }
    }

    private static func deduplicated(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values.filter { seen.insert($0).inserted }
    }
}
