import Foundation

// MARK: - Profiles

struct TerminalProfile: Codable, Identifiable {
    var id: String  // unique key, e.g. "default", "ssh-prod"
    var name: String
    var fontFamily: String?  // nil = use global setting
    var fontSize: Int?
    var themeName: String?
    var shell: String?
    var workingDirectory: String?
    var cursorStyle: String?

    /// Merge this profile's overrides onto the global settings to produce a config.
    func effectiveFont(fallback: BellithSettings) -> String {
        fontFamily ?? fallback.fontFamily
    }

    func effectiveFontSize(fallback: BellithSettings) -> Int {
        fontSize ?? fallback.fontSize
    }

    func effectiveShell(fallback: BellithSettings) -> String {
        shell ?? fallback.shell
    }

    static let `default` = TerminalProfile(
        id: "default", name: "Default"
    )
}

extension BellithSettings {
    var profiles: [TerminalProfile] {
        get {
            if let data = defaults.data(forKey: "profiles"),
               let decoded = try? JSONDecoder().decode([TerminalProfile].self, from: data) {
                return decoded
            }
            return [.default]
        }
        set {
            if let data = try? JSONEncoder().encode(newValue) {
                defaults.set(data, forKey: "profiles")
            }
            notify()
        }
    }

    func profile(named name: String) -> TerminalProfile? {
        profiles.first { $0.name.lowercased() == name.lowercased() || $0.id == name }
    }
}
