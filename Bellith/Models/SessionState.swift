import Foundation

// MARK: - Session State

struct SessionState: Codable {
    struct TabState: Codable {
        enum Kind: String, Codable {
            case terminal
            case smart
        }

        let title: String
        let kind: Kind
        let splitTree: SplitNodeState?
        let smartPanelID: String?
        let terminalContext: TerminalContext?
        let sshProfileID: UUID?

        init(
            title: String,
            splitTree: SplitNodeState,
            terminalContext: TerminalContext? = nil,
            sshProfileID: UUID? = nil
        ) {
            self.title = title
            self.kind = .terminal
            self.splitTree = splitTree
            self.smartPanelID = nil
            self.terminalContext = terminalContext
            self.sshProfileID = sshProfileID
        }

        init(title: String, smartPanelID: String) {
            self.title = title
            self.kind = .smart
            self.splitTree = nil
            self.smartPanelID = smartPanelID
            self.terminalContext = nil
            self.sshProfileID = nil
        }

        private enum CodingKeys: String, CodingKey {
            case title
            case kind
            case splitTree
            case smartPanelID
            case terminalContext
            case sshProfileID
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            title = try container.decode(String.self, forKey: .title)
            kind = try container.decodeIfPresent(Kind.self, forKey: .kind) ?? .terminal
            splitTree = try container.decodeIfPresent(SplitNodeState.self, forKey: .splitTree)
            smartPanelID = try container.decodeIfPresent(String.self, forKey: .smartPanelID)
            terminalContext = try container.decodeIfPresent(TerminalContext.self, forKey: .terminalContext)
            sshProfileID = try container.decodeIfPresent(UUID.self, forKey: .sshProfileID)
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
}
