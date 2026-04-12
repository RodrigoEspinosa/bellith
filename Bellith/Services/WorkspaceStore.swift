import Foundation
import os

final class WorkspaceStore {
    static let shared = WorkspaceStore()
    static let didChangeNotification = Notification.Name("WorkspaceStoreDidChange")

    private let defaults: UserDefaults
    private let storageKey = "namedWorkspaces"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var workspaces: [WorkspaceDefinition] {
        loadWorkspaces()
    }

    func workspace(id: UUID) -> WorkspaceDefinition? {
        workspaces.first { $0.id == id }
    }

    func workspace(named name: String) -> WorkspaceDefinition? {
        let lower = name.lowercased()
        return workspaces.first { $0.name.lowercased() == lower }
    }

    func save(_ workspace: WorkspaceDefinition) {
        var all = workspaces
        if let index = all.firstIndex(where: { $0.id == workspace.id }) {
            all[index] = workspace
        } else {
            all.append(workspace)
        }
        persist(all)
    }

    func delete(id: UUID) {
        persist(workspaces.filter { $0.id != id })
    }

    func rename(id: UUID, to newName: String) {
        var all = workspaces
        guard let index = all.firstIndex(where: { $0.id == id }) else { return }
        all[index].name = newName
        all[index].updatedAt = Date()
        persist(all)
    }

    func updateSession(id: UUID, session: SessionState) {
        var all = workspaces
        guard let index = all.firstIndex(where: { $0.id == id }) else { return }
        all[index].session = session
        all[index].updatedAt = Date()
        persist(all)
    }

    private func persist(_ workspaces: [WorkspaceDefinition]) {
        do {
            let data = try JSONEncoder().encode(workspaces)
            defaults.set(data, forKey: storageKey)
            NotificationCenter.default.post(name: Self.didChangeNotification, object: nil)
        } catch {
            Logger.config.error("Failed to persist workspaces: \(error.localizedDescription)")
        }
    }

    private func loadWorkspaces() -> [WorkspaceDefinition] {
        guard let data = defaults.data(forKey: storageKey) else { return [] }
        do {
            return try JSONDecoder().decode([WorkspaceDefinition].self, from: data)
        } catch {
            Logger.config.error("Failed to decode workspaces: \(error.localizedDescription)")
            return []
        }
    }
}
