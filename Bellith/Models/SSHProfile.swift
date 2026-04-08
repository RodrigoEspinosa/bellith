import Foundation

struct SSHProfile: Codable, Equatable, Identifiable {
    let id: UUID
    var name: String
    var host: String
    var user: String
    var port: Int
    var identityPath: String
    var proxyJump: String
    var defaultDirectory: String
    var startupCommand: String
    var tmuxSession: String
    var environmentTag: String
    var isSensitive: Bool
    var notes: String

    init(
        id: UUID = UUID(),
        name: String = "New Host",
        host: String = "",
        user: String = "",
        port: Int = 22,
        identityPath: String = "",
        proxyJump: String = "",
        defaultDirectory: String = "",
        startupCommand: String = "",
        tmuxSession: String = "",
        environmentTag: String = "",
        isSensitive: Bool = false,
        notes: String = ""
    ) {
        self.id = id
        self.name = name
        self.host = host
        self.user = user
        self.port = port
        self.identityPath = identityPath
        self.proxyJump = proxyJump
        self.defaultDirectory = defaultDirectory
        self.startupCommand = startupCommand
        self.tmuxSession = tmuxSession
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
            port: max(1, min(65_535, port)),
            identityPath: trimmedIdentityPath,
            proxyJump: trimmedProxyJump,
            defaultDirectory: trimmedDefaultDirectory,
            startupCommand: trimmedStartupCommand,
            tmuxSession: trimmedTmuxSession,
            environmentTag: trimmedEnvironmentTag,
            isSensitive: isSensitive,
            notes: trimmedNotes
        )
    }

    private var trimmedName: String { Self.trimmed(name) }
    private var trimmedHost: String { Self.trimmed(host) }
    private var trimmedUser: String { Self.trimmed(user) }
    private var trimmedIdentityPath: String { Self.trimmed(identityPath) }
    private var trimmedProxyJump: String { Self.trimmed(proxyJump) }
    private var trimmedDefaultDirectory: String { Self.trimmed(defaultDirectory) }
    private var trimmedStartupCommand: String { Self.trimmed(startupCommand) }
    private var trimmedTmuxSession: String { Self.trimmed(tmuxSession) }
    private var trimmedEnvironmentTag: String { Self.trimmed(environmentTag) }
    private var trimmedNotes: String { Self.trimmed(notes) }

    private static func trimmed(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
