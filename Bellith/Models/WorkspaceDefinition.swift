import Foundation

struct WorkspaceDefinition: Codable, Identifiable {
    let id: UUID
    var name: String
    var session: SessionState
    var createdAt: Date
    var updatedAt: Date

    init(name: String, session: SessionState) {
        self.id = UUID()
        self.name = name
        self.session = session
        self.createdAt = Date()
        self.updatedAt = Date()
    }
}
