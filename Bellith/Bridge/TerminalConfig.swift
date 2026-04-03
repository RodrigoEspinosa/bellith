import Foundation
import GhosttyKit

// MARK: - User Settings (persisted to disk)

final class BellithSettings {
    static let shared = BellithSettings()
    static let didChangeNotification = Notification.Name("BellithSettingsDidChange")

    private let defaults = UserDefaults.standard

    var fontFamily: String {
        get { defaults.string(forKey: "fontFamily") ?? "Hack Nerd Font Mono" }
        set { defaults.set(newValue, forKey: "fontFamily"); notify() }
    }

    var fontSize: Int {
        get { let v = defaults.integer(forKey: "fontSize"); return v > 0 ? v : 15 }
        set { defaults.set(newValue, forKey: "fontSize"); notify() }
    }

    var backgroundOpacity: Double {
        get {
            if defaults.object(forKey: "backgroundOpacity") != nil {
                return defaults.double(forKey: "backgroundOpacity")
            }
            return 1.0
        }
        set { defaults.set(newValue, forKey: "backgroundOpacity"); notify() }
    }

    var cursorStyle: String {
        get { defaults.string(forKey: "cursorStyle") ?? "block" }
        set { defaults.set(newValue, forKey: "cursorStyle"); notify() }
    }

    var themeName: String {
        get { defaults.string(forKey: "themeName") ?? "Tokyo Night" }
        set { defaults.set(newValue, forKey: "themeName"); notify() }
    }

    /// "sidebar" or "tabbar"
    var tabMode: String {
        get { defaults.string(forKey: "tabMode") ?? "sidebar" }
        set { defaults.set(newValue, forKey: "tabMode"); notify() }
    }

    private func notify() {
        NotificationCenter.default.post(name: Self.didChangeNotification, object: self)
    }

    /// Resolve the ThemeColors for the current themeName.
    var resolvedTheme: ThemeColors {
        ThemeColors.allThemes.first { $0.name == themeName } ?? .tokyonight
    }
}

// MARK: - Ghostty Config Wrapper

/// Wraps ghostty_config_t with automatic lifecycle management.
final class TerminalConfig {
    private(set) var config: ghostty_config_t?

    init() {
        config = ghostty_config_new()
        guard config != nil else { return }

        let configPath = Self.writeConfigFile()
        if let path = configPath {
            path.withCString { ghostty_config_load_file(config, $0) }
        }

        ghostty_config_finalize(config)
    }

    /// Clone an existing config (e.g. for a new surface with overrides).
    init(cloning other: TerminalConfig) {
        guard let src = other.config else {
            config = nil
            return
        }
        config = ghostty_config_clone(src)
    }

    deinit {
        if let config { ghostty_config_free(config) }
    }

    func get<T>(_ key: String, _ out: UnsafeMutablePointer<T>) -> Bool {
        guard let config else { return false }
        return key.withCString { cKey in
            ghostty_config_get(config, out, cKey, UInt(MemoryLayout<T>.size))
        }
    }

    /// Write the full Bellith config file based on current BellithSettings.
    static func writeConfigFile() -> String? {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("bellith", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let s = BellithSettings.shared
        let file = dir.appendingPathComponent("config.conf")
        let content = [
            "font-family = \(s.fontFamily)",
            "font-size = \(s.fontSize)",
            "theme = \(s.resolvedTheme.ghosttyTheme)",
            "background-opacity = \(s.backgroundOpacity)",
            "window-padding-x = 10",
            "window-padding-y = 38,2",
            "window-padding-balance = false",
            "cursor-style = \(s.cursorStyle)",
            "cursor-style-blink = false",
            "shell-integration-features = no-cursor",
            "window-decoration = false",
            "window-save-state = never",
            "mouse-hide-while-typing = true",
            "confirm-close-surface = false",
        ].joined(separator: "\n")

        do {
            try content.write(to: file, atomically: true, encoding: .utf8)
            return file.path
        } catch {
            return nil
        }
    }
}
