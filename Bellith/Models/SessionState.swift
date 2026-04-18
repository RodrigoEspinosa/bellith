import Foundation

// MARK: - Session State

struct SessionState: Codable {
    struct TerminalSnapshot: Codable, Equatable {
        let cwd: String?
        let hadScrollback: Bool
        let localSessionBootstrap: SSHSessionBootstrap?
        let localSessionName: String?
        let scrollbackText: String?

        init(
            cwd: String?,
            hadScrollback: Bool,
            localSessionBootstrap: SSHSessionBootstrap? = nil,
            localSessionName: String? = nil,
            scrollbackText: String? = nil
        ) {
            let trimmedSessionName = localSessionName?.trimmingCharacters(in: .whitespacesAndNewlines)
            let normalizedBootstrap = localSessionBootstrap == SSHSessionBootstrap.none ? nil : localSessionBootstrap
            let normalizedScrollback = scrollbackText?.isEmpty == false ? scrollbackText : nil

            self.cwd = cwd
            self.hadScrollback = hadScrollback
            self.localSessionBootstrap = normalizedBootstrap
            self.localSessionName = normalizedBootstrap == nil ? nil : trimmedSessionName
            self.scrollbackText = normalizedScrollback
        }
    }

    struct TabState: Codable {
        enum Kind: String, Codable {
            case terminal
            case smart
        }

        let title: String
        let kind: Kind
        let terminalSnapshot: TerminalSnapshot?
        let smartPanelID: String?
        let terminalContext: TerminalContext?
        let sshProfileID: UUID?
        let isPinned: Bool
        let isUserRenamed: Bool

        init(
            title: String,
            terminalSnapshot: TerminalSnapshot,
            terminalContext: TerminalContext? = nil,
            sshProfileID: UUID? = nil,
            isPinned: Bool = false,
            isUserRenamed: Bool = false
        ) {
            self.title = title
            self.kind = .terminal
            self.terminalSnapshot = terminalSnapshot
            self.smartPanelID = nil
            self.terminalContext = terminalContext
            self.sshProfileID = sshProfileID
            self.isPinned = isPinned
            self.isUserRenamed = isUserRenamed
        }

        init(title: String, smartPanelID: String, isPinned: Bool = false) {
            self.title = title
            self.kind = .smart
            self.terminalSnapshot = nil
            self.smartPanelID = smartPanelID
            self.terminalContext = nil
            self.sshProfileID = nil
            self.isPinned = isPinned
            self.isUserRenamed = false
        }

        private enum CodingKeys: String, CodingKey {
            case title
            case kind
            case terminalSnapshot
            case smartPanelID
            case terminalContext
            case sshProfileID
            case splitTree
            case isPinned
            case isUserRenamed
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            title = try container.decode(String.self, forKey: .title)
            kind = try container.decodeIfPresent(Kind.self, forKey: .kind) ?? .terminal
            smartPanelID = try container.decodeIfPresent(String.self, forKey: .smartPanelID)
            terminalContext = try container.decodeIfPresent(TerminalContext.self, forKey: .terminalContext)
            sshProfileID = try container.decodeIfPresent(UUID.self, forKey: .sshProfileID)
            isPinned = try container.decodeIfPresent(Bool.self, forKey: .isPinned) ?? false
            isUserRenamed = try container.decodeIfPresent(Bool.self, forKey: .isUserRenamed) ?? false
            if let snapshot = try container.decodeIfPresent(TerminalSnapshot.self, forKey: .terminalSnapshot) {
                terminalSnapshot = snapshot
            } else if let legacySplitTree = try container.decodeIfPresent(SplitNodeState.self, forKey: .splitTree) {
                terminalSnapshot = legacySplitTree.flattenedSnapshot()
            } else {
                terminalSnapshot = nil
            }
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(title, forKey: .title)
            try container.encode(kind, forKey: .kind)
            try container.encodeIfPresent(terminalSnapshot, forKey: .terminalSnapshot)
            try container.encodeIfPresent(smartPanelID, forKey: .smartPanelID)
            try container.encodeIfPresent(terminalContext, forKey: .terminalContext)
            try container.encodeIfPresent(sshProfileID, forKey: .sshProfileID)
            if isPinned {
                try container.encode(isPinned, forKey: .isPinned)
            }
            if isUserRenamed {
                try container.encode(isUserRenamed, forKey: .isUserRenamed)
            }
        }
    }

    let tabs: [TabState]
    let selectedTabIndex: Int
    let sidebarExpanded: Bool?
}

struct WindowSessionState: Codable {
    let session: SessionState
    let frameDescriptor: String?
}

struct WindowLaunchRequest {
    let session: SessionState?
    let initialWorkingDirectory: String?

    init(session: SessionState? = nil, initialWorkingDirectory: String? = nil) {
        self.session = session
        self.initialWorkingDirectory = initialWorkingDirectory
    }
}

extension Notification.Name {
    static let bellithCreateNewWindow = Notification.Name("BellithCreateNewWindow")
}

indirect enum SplitNodeState: Codable {
    case leaf(cwd: String?, scrollbackText: String?)
    case branch(orientation: String, ratio: Double, first: SplitNodeState, second: SplitNodeState)

    private enum CodingKeys: String, CodingKey {
        case type, cwd, scrollbackText, orientation, ratio, first, second
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .leaf(let cwd, let scrollbackText):
            try c.encode("leaf", forKey: .type)
            try c.encodeIfPresent(cwd, forKey: .cwd)
            try c.encodeIfPresent(scrollbackText, forKey: .scrollbackText)
        case .branch(let orientation, let ratio, let first, let second):
            try c.encode("branch", forKey: .type)
            try c.encode(orientation, forKey: .orientation)
            try c.encode(ratio, forKey: .ratio)
            try c.encode(first, forKey: .first)
            try c.encode(second, forKey: .second)
        }
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let type = try c.decode(String.self, forKey: .type)
        switch type {
        case "branch":
            let orientation = try c.decode(String.self, forKey: .orientation)
            let ratio = try c.decode(Double.self, forKey: .ratio)
            let first = try c.decode(SplitNodeState.self, forKey: .first)
            let second = try c.decode(SplitNodeState.self, forKey: .second)
            self = .branch(orientation: orientation, ratio: ratio, first: first, second: second)
        default:
            let cwd = try c.decodeIfPresent(String.self, forKey: .cwd)
            let scrollbackText = try c.decodeIfPresent(String.self, forKey: .scrollbackText)
            self = .leaf(cwd: cwd, scrollbackText: scrollbackText)
        }
    }

    func flattenedSnapshot() -> SessionState.TerminalSnapshot {
        switch self {
        case .leaf(let cwd, let scrollbackText):
            return SessionState.TerminalSnapshot(
                cwd: cwd,
                hadScrollback: !(scrollbackText?.isEmpty ?? true),
                scrollbackText: scrollbackText
            )
        case .branch(_, _, let first, let second):
            let firstSnapshot = first.flattenedSnapshot()
            let secondSnapshot = second.flattenedSnapshot()
            return SessionState.TerminalSnapshot(
                cwd: firstSnapshot.cwd ?? secondSnapshot.cwd,
                hadScrollback: firstSnapshot.hadScrollback || secondSnapshot.hadScrollback,
                scrollbackText: firstSnapshot.scrollbackText ?? secondSnapshot.scrollbackText
            )
        }
    }
}
