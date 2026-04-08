import Foundation

struct TerminalContext: Codable, Equatable {
    enum Source: String, Codable {
        case local
        case sshProfile
        case sshCommand
    }

    var source: Source
    var host: String?
    var user: String?
    var environmentTag: String?
    var isSensitive: Bool
    var sshProfileID: UUID?

    static let local = TerminalContext(source: .local)

    init(
        source: Source,
        host: String? = nil,
        user: String? = nil,
        environmentTag: String? = nil,
        isSensitive: Bool = false,
        sshProfileID: UUID? = nil
    ) {
        self.source = source
        self.host = Self.normalized(host)
        self.user = Self.normalized(user)
        self.environmentTag = Self.normalized(environmentTag)
        self.isSensitive = isSensitive
        self.sshProfileID = sshProfileID
    }

    var isRemote: Bool {
        source != .local && host != nil
    }

    var hostDisplayText: String {
        guard isRemote else { return "LOCAL" }
        if let user, let host {
            return "\(user)@\(host)"
        }
        return host ?? "REMOTE"
    }

    var environmentDisplayText: String? {
        environmentTag?.uppercased()
    }

    var profileCommandAlias: String? {
        guard let host else { return nil }
        if let user {
            return "\(user)@\(host)"
        }
        return host
    }

    private static func normalized(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed?.isEmpty == false ? trimmed : nil
    }
}
