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

    /// Frame opacity in [0.0, 1.0]. `nil` falls back to the global setting.
    /// This is the sole knob driving frame translucency: the displayed
    /// "Frame Translucency" slider writes `1 - translucency` here, and the
    /// visual-effect material intensity is derived from it so every slider
    /// position yields a visually coherent frame.
    var backgroundOpacity: Double?

    /// When true, a muted accent derived from the desktop wallpaper is
    /// overlaid on the translucent window chrome.
    var wallpaperTint: Bool?

    func effectiveFont(fallback: BellithSettings) -> String {
        fontFamily ?? fallback.fontFamily
    }

    func effectiveFontSize(fallback: BellithSettings) -> Int {
        fontSize ?? fallback.fontSize
    }

    func effectiveShell(fallback: BellithSettings) -> String {
        shell ?? fallback.shell
    }

    func effectiveBackgroundOpacity(fallback: BellithSettings) -> Double {
        let value = backgroundOpacity ?? fallback.backgroundOpacity
        return min(max(value, 0.0), 1.0)
    }

    /// Derived 0...1 glass strength. 0 means a fully solid frame (no blur
    /// backdrop); 1 means maximum glass. Always co-varies with the frame
    /// opacity so the two can't drift into incoherent combinations.
    func effectiveFrameTranslucency(fallback: BellithSettings) -> Double {
        1.0 - effectiveBackgroundOpacity(fallback: fallback)
    }

    func effectiveWallpaperTint() -> Bool {
        wallpaperTint ?? false
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
