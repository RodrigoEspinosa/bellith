import Foundation

enum SSHSessionBootstrap: String, Codable, CaseIterable {
    case none
    case tmux
    case zellij

    var title: String {
        switch self {
        case .none:
            return "None"
        case .tmux:
            return "tmux"
        case .zellij:
            return "zellij"
        }
    }
}

enum SSHTransport: String, Codable, CaseIterable {
    case ssh
    case mosh

    var title: String {
        switch self {
        case .ssh:
            return "SSH"
        case .mosh:
            return "Mosh"
        }
    }
}

struct SSHProfile: Codable, Equatable, Identifiable {
    let id: UUID
    var name: String
    var host: String
    var user: String
    var transport: SSHTransport
    var port: Int
    var identityPath: String
    var proxyJump: String
    var proxyJumpProfileIDs: [UUID]
    var defaultDirectory: String
    var startupCommand: String
    var sessionBootstrap: SSHSessionBootstrap
    var sessionName: String
    var environmentTag: String
    var isSensitive: Bool
    var notes: String

    init(
        id: UUID = UUID(),
        name: String = "New Host",
        host: String = "",
        user: String = "",
        transport: SSHTransport = .ssh,
        port: Int = 22,
        identityPath: String = "",
        proxyJump: String = "",
        proxyJumpProfileIDs: [UUID] = [],
        defaultDirectory: String = "",
        startupCommand: String = "",
        sessionBootstrap: SSHSessionBootstrap = .none,
        sessionName: String = "",
        tmuxSession: String? = nil,
        environmentTag: String = "",
        isSensitive: Bool = false,
        notes: String = ""
    ) {
        let resolvedBootstrap: SSHSessionBootstrap
        let resolvedSessionName: String
        if let tmuxSession,
           !Self.trimmed(tmuxSession).isEmpty,
           Self.trimmed(sessionName).isEmpty,
           sessionBootstrap == .none {
            resolvedBootstrap = .tmux
            resolvedSessionName = tmuxSession
        } else {
            resolvedBootstrap = sessionBootstrap
            resolvedSessionName = sessionName
        }

        self.id = id
        self.name = name
        self.host = host
        self.user = user
        self.transport = transport
        self.port = port
        self.identityPath = identityPath
        self.proxyJump = proxyJump
        self.proxyJumpProfileIDs = Self.normalizedProxyJumpProfileIDs(proxyJumpProfileIDs, excluding: id)
        self.defaultDirectory = defaultDirectory
        self.startupCommand = startupCommand
        self.sessionBootstrap = resolvedBootstrap
        self.sessionName = resolvedSessionName
        self.environmentTag = environmentTag
        self.isSensitive = isSensitive
        self.notes = notes
    }

    var displayName: String {
        if !trimmedName.isEmpty {
            return trimmedName
        }
        if !trimmedHost.isEmpty {
            return trimmedHost
        }
        return "Untitled Host"
    }

    var destination: String {
        if !trimmedUser.isEmpty {
            return "\(trimmedUser)@\(trimmedHost)"
        }
        return trimmedHost
    }

    var isValid: Bool {
        !trimmedHost.isEmpty
    }

    var launchContext: TerminalContext {
        TerminalContext(
            source: .sshProfile,
            host: trimmedHost,
            user: trimmedUser,
            environmentTag: trimmedEnvironmentTag,
            isSensitive: isSensitive,
            sshProfileID: id
        )
    }

    func sanitized() -> SSHProfile {
        SSHProfile(
            id: id,
            name: displayName,
            host: trimmedHost,
            user: trimmedUser,
            transport: transport,
            port: max(1, min(65_535, port)),
            identityPath: trimmedIdentityPath,
            proxyJump: trimmedProxyJump,
            proxyJumpProfileIDs: Self.normalizedProxyJumpProfileIDs(proxyJumpProfileIDs, excluding: id),
            defaultDirectory: trimmedDefaultDirectory,
            startupCommand: trimmedStartupCommand,
            sessionBootstrap: trimmedSessionName.isEmpty ? .none : sessionBootstrap,
            sessionName: trimmedSessionName,
            environmentTag: trimmedEnvironmentTag,
            isSensitive: isSensitive,
            notes: trimmedNotes
        )
    }

    var hasProxyJumpProfileChain: Bool {
        !proxyJumpProfileIDs.isEmpty
    }

    var legacyProxyJumpHops: [String] {
        guard !hasProxyJumpProfileChain else { return [] }
        return trimmedProxyJump
            .split(separator: ",")
            .map { Self.trimmed(String($0)) }
            .filter { !$0.isEmpty }
    }

    func resolvedProxyJumpArgument(using profiles: [SSHProfile]) -> String {
        guard hasProxyJumpProfileChain else { return trimmedProxyJump }

        let lookup = Dictionary(uniqueKeysWithValues: profiles.map { ($0.id, $0) })
        let resolved = proxyJumpProfileIDs.compactMap { profileID in
            lookup[profileID]?.destination
        }
        .map(Self.trimmed)
        .filter { !$0.isEmpty }

        if resolved.count == proxyJumpProfileIDs.count, !resolved.isEmpty {
            return resolved.joined(separator: ",")
        }

        return trimmedProxyJump
    }

    mutating func updateProxyJumpChain(profileIDs: [UUID], availableProfiles: [SSHProfile]) {
        let normalizedProfileIDs = Self.normalizedProxyJumpProfileIDs(profileIDs, excluding: id)
        let lookup = Dictionary(uniqueKeysWithValues: availableProfiles.map { ($0.id, $0) })
        let resolvedChain = normalizedProfileIDs.compactMap { profileID in
            lookup[profileID]?.destination
        }
        .map(Self.trimmed)
        .filter { !$0.isEmpty }

        proxyJumpProfileIDs = normalizedProfileIDs
        proxyJump = resolvedChain.joined(separator: ",")
    }

    private var trimmedName: String { Self.trimmed(name) }
    private var trimmedHost: String { Self.trimmed(host) }
    private var trimmedUser: String { Self.trimmed(user) }
    private var trimmedIdentityPath: String { Self.trimmed(identityPath) }
    private var trimmedProxyJump: String { Self.trimmed(proxyJump) }
    private var trimmedDefaultDirectory: String { Self.trimmed(defaultDirectory) }
    private var trimmedStartupCommand: String { Self.trimmed(startupCommand) }
    private var trimmedSessionName: String { Self.trimmed(sessionName) }
    private var trimmedEnvironmentTag: String { Self.trimmed(environmentTag) }
    private var trimmedNotes: String { Self.trimmed(notes) }

    private static func trimmed(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func normalizedProxyJumpProfileIDs(_ profileIDs: [UUID], excluding excludedID: UUID) -> [UUID] {
        var seen = Set<UUID>()
        return profileIDs.filter { profileID in
            guard profileID != excludedID else { return false }
            return seen.insert(profileID).inserted
        }
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case host
        case user
        case transport
        case port
        case identityPath
        case proxyJump
        case proxyJumpProfileIDs
        case defaultDirectory
        case startupCommand
        case sessionBootstrap
        case sessionName
        case tmuxSession
        case environmentTag
        case isSensitive
        case notes
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let legacyTmuxSession = try container.decodeIfPresent(String.self, forKey: .tmuxSession) ?? ""
        let decodedBootstrap = try container.decodeIfPresent(SSHSessionBootstrap.self, forKey: .sessionBootstrap) ?? .none
        let decodedSessionName = try container.decodeIfPresent(String.self, forKey: .sessionName) ?? ""
        let migratedSessionName = Self.trimmed(decodedSessionName).isEmpty ? legacyTmuxSession : decodedSessionName
        let migratedBootstrap: SSHSessionBootstrap
        if !Self.trimmed(legacyTmuxSession).isEmpty && Self.trimmed(decodedSessionName).isEmpty {
            migratedBootstrap = .tmux
        } else {
            migratedBootstrap = decodedBootstrap
        }

        self.init(
            id: try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID(),
            name: try container.decodeIfPresent(String.self, forKey: .name) ?? "New Host",
            host: try container.decodeIfPresent(String.self, forKey: .host) ?? "",
            user: try container.decodeIfPresent(String.self, forKey: .user) ?? "",
            transport: try container.decodeIfPresent(SSHTransport.self, forKey: .transport) ?? .ssh,
            port: try container.decodeIfPresent(Int.self, forKey: .port) ?? 22,
            identityPath: try container.decodeIfPresent(String.self, forKey: .identityPath) ?? "",
            proxyJump: try container.decodeIfPresent(String.self, forKey: .proxyJump) ?? "",
            proxyJumpProfileIDs: try container.decodeIfPresent([UUID].self, forKey: .proxyJumpProfileIDs) ?? [],
            defaultDirectory: try container.decodeIfPresent(String.self, forKey: .defaultDirectory) ?? "",
            startupCommand: try container.decodeIfPresent(String.self, forKey: .startupCommand) ?? "",
            sessionBootstrap: migratedBootstrap,
            sessionName: migratedSessionName,
            environmentTag: try container.decodeIfPresent(String.self, forKey: .environmentTag) ?? "",
            isSensitive: try container.decodeIfPresent(Bool.self, forKey: .isSensitive) ?? false,
            notes: try container.decodeIfPresent(String.self, forKey: .notes) ?? ""
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(host, forKey: .host)
        try container.encode(user, forKey: .user)
        try container.encode(transport, forKey: .transport)
        try container.encode(port, forKey: .port)
        try container.encode(identityPath, forKey: .identityPath)
        try container.encode(proxyJump, forKey: .proxyJump)
        try container.encode(proxyJumpProfileIDs, forKey: .proxyJumpProfileIDs)
        try container.encode(defaultDirectory, forKey: .defaultDirectory)
        try container.encode(startupCommand, forKey: .startupCommand)
        try container.encode(sessionBootstrap, forKey: .sessionBootstrap)
        try container.encode(sessionName, forKey: .sessionName)
        try container.encode(environmentTag, forKey: .environmentTag)
        try container.encode(isSensitive, forKey: .isSensitive)
        try container.encode(notes, forKey: .notes)
    }
}
