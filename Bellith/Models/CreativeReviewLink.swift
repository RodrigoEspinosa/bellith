import Foundation

/// Navigation only: no command, path, approval, or host operation can be encoded.
struct CreativeReviewLink: Equatable {
    enum Tool: String { case resolve, logic; case logicTrack = "logic-track" }
    let tool: Tool
    let proposalID: UUID

    var url: URL {
        var components = URLComponents()
        components.scheme = "bellith"
        components.host = "review"
        components.queryItems = [URLQueryItem(name: "tool", value: tool.rawValue),
                                 URLQueryItem(name: "proposal", value: proposalID.uuidString)]
        return components.url!
    }

    init(tool: Tool, proposalID: UUID) { self.tool = tool; self.proposalID = proposalID }

    init?(url: URL) {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.scheme == "bellith", components.host == "review", components.path.isEmpty,
              components.user == nil, components.password == nil, components.port == nil, components.fragment == nil,
              let items = components.queryItems, items.count == 2,
              Set(items.map(\.name)) == Set(["tool", "proposal"]),
              let tool = items.first(where: { $0.name == "tool" })?.value.flatMap(Tool.init(rawValue:)),
              let id = items.first(where: { $0.name == "proposal" })?.value.flatMap(UUID.init(uuidString:)) else { return nil }
        self.init(tool: tool, proposalID: id)
    }
}

struct CreativeReviewRequest: Equatable {
    let id = UUID()
    let proposalID: UUID?
}
