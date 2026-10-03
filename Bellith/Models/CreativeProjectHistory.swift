import Foundation

struct CreativeRecentProject: Codable, Identifiable, Equatable {
    let url: URL
    let openedAt: Date
    var id: String {
        var parts: [Substring] = []
        for part in url.path.split(separator: "/") {
            if part == "." { continue }
            if part == ".." { if !parts.isEmpty { parts.removeLast() }; continue }
            parts.append(part)
        }
        return "/" + parts.joined(separator: "/")
    }
    var name: String { url.lastPathComponent }
}

/// Local navigation history only. Reading history never opens or scans a project.
struct CreativeProjectHistory {
    let defaults: UserDefaults
    static let key = "creativeRecentProjects.v1"

    func read() -> [CreativeRecentProject] {
        guard let data = defaults.data(forKey: Self.key), data.count <= 100_000,
              let projects = try? JSONDecoder().decode([CreativeRecentProject].self, from: data) else { return [] }
        var seen = Set<String>()
        return Array(projects.filter { $0.url.isFileURL && seen.insert($0.id).inserted }.prefix(8))
    }

    @discardableResult func remember(_ url: URL) -> [CreativeRecentProject] {
        guard url.isFileURL else { return read() }
        let identity = CreativeRecentProject(url: url, openedAt: Date()).id
        let project = CreativeRecentProject(url: URL(fileURLWithPath: identity, isDirectory: true), openedAt: Date())
        let projects = Array(([project] + read().filter { $0.id != project.id }).prefix(8))
        if let data = try? JSONEncoder().encode(projects) { defaults.set(data, forKey: Self.key) }
        return projects
    }

    func clear() { defaults.removeObject(forKey: Self.key) }
}
