import Foundation

// MARK: - Session State

struct SessionState: Codable {
    struct TabState: Codable {
        let title: String
        let splitTree: SplitNodeState
    }

    let tabs: [TabState]
    let selectedTabIndex: Int
}

indirect enum SplitNodeState: Codable {
    case leaf(cwd: String?)
    case branch(orientation: String, ratio: Double, first: SplitNodeState, second: SplitNodeState)

    private enum CodingKeys: String, CodingKey {
        case type, cwd, orientation, ratio, first, second
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .leaf(let cwd):
            try c.encode("leaf", forKey: .type)
            try c.encodeIfPresent(cwd, forKey: .cwd)
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
            self = .leaf(cwd: cwd)
        }
    }
}
