import Foundation

// MARK: - Profiles

struct TerminalProfile: Codable, Identifiable, Equatable {
    var id: String  // unique key, e.g. "default", "focus"
    var name: String
    var fontFamily: String?
    var fontSize: Int?
    var themeName: String?
    var shell: String?
    var workingDirectory: String?
    var cursorStyle: String?

    /// Only kept so we can read the value from pre-unification installs and
    /// promote it to the global setting during migration. Never written.
    var legacyBackgroundOpacity: Double?
    var legacyWallpaperTint: Bool?

    private enum CodingKeys: String, CodingKey {
        case id, name, fontFamily, fontSize, themeName, shell, workingDirectory, cursorStyle
        case legacyBackgroundOpacity = "backgroundOpacity"
        case legacyWallpaperTint = "wallpaperTint"
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encodeIfPresent(fontFamily, forKey: .fontFamily)
        try c.encodeIfPresent(fontSize, forKey: .fontSize)
        try c.encodeIfPresent(themeName, forKey: .themeName)
        try c.encodeIfPresent(shell, forKey: .shell)
        try c.encodeIfPresent(workingDirectory, forKey: .workingDirectory)
        try c.encodeIfPresent(cursorStyle, forKey: .cursorStyle)
        // legacy fields are intentionally not re-encoded; migration promotes
        // them to global settings on first launch after the unification.
    }

    func effectiveFont(fallback: BellithSettings) -> String {
        fontFamily ?? fallback.fontFamily
    }

    func effectiveFontSize(fallback: BellithSettings) -> Int {
        fontSize ?? fallback.fontSize
    }

    func effectiveShell(fallback: BellithSettings) -> String {
        shell ?? fallback.shell
    }

    static let defaultID = "default"

    static let `default` = TerminalProfile(id: defaultID, name: "Default")
}


extension BellithSettings {
    private static let profilesKey = "terminalProfiles"
    private static let activeProfileIDKey = "activeTerminalProfileID"

    var profiles: [TerminalProfile] {
        get {
            if let data = defaults.data(forKey: Self.profilesKey),
               let decoded = try? JSONDecoder().decode([TerminalProfile].self, from: data),
               !decoded.isEmpty {
                return decoded
            }
            return [.default]
        }
        set {
            let sanitized = newValue.isEmpty ? [.default] : newValue
            if let data = try? JSONEncoder().encode(sanitized) {
                defaults.set(data, forKey: Self.profilesKey)
            }
            notify()
        }
    }

    var activeProfileID: String {
        get {
            let stored = defaults.string(forKey: Self.activeProfileIDKey) ?? TerminalProfile.defaultID
            return profiles.contains(where: { $0.id == stored }) ? stored : TerminalProfile.defaultID
        }
        set {
            defaults.set(newValue, forKey: Self.activeProfileIDKey)
            notify()
        }
    }

    var activeProfile: TerminalProfile {
        let list = profiles
        return list.first(where: { $0.id == activeProfileID }) ?? list.first ?? .default
    }

    func updateActiveProfile(_ mutate: (inout TerminalProfile) -> Void) {
        var list = profiles
        let id = activeProfileID
        guard let index = list.firstIndex(where: { $0.id == id }) else { return }
        mutate(&list[index])
        profiles = list
    }

    func profile(named name: String) -> TerminalProfile? {
        profiles.first { $0.name.lowercased() == name.lowercased() || $0.id == name }
    }
}
