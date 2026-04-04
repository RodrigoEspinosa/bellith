import AppKit
import Foundation
import GhosttyKit

// MARK: - Keybinding Definition

struct KeyShortcut: Codable, Equatable {
    var key: String        // character, e.g. "t", "]", "d"
    var command: Bool
    var shift: Bool
    var option: Bool
    var control: Bool

    var displayString: String {
        var parts: [String] = []
        if control { parts.append("⌃") }
        if option { parts.append("⌥") }
        if shift { parts.append("⇧") }
        if command { parts.append("⌘") }
        parts.append(key.count == 1 ? key.uppercased() : key)
        return parts.joined()
    }

    /// Returns individual keycap strings for rendering as separate key badges.
    var keycapStrings: [String] {
        var caps: [String] = []
        if control { caps.append("⌃") }
        if option { caps.append("⌥") }
        if shift { caps.append("⇧") }
        if command { caps.append("⌘") }
        caps.append(key.count == 1 ? key.uppercased() : key)
        return caps
    }

    var modifierFlags: NSEvent.ModifierFlags {
        var flags: NSEvent.ModifierFlags = []
        if command { flags.insert(.command) }
        if shift { flags.insert(.shift) }
        if option { flags.insert(.option) }
        if control { flags.insert(.control) }
        return flags
    }

    static func from(event: NSEvent) -> KeyShortcut? {
        let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let key = event.charactersIgnoringModifiers ?? ""
        guard !key.isEmpty else { return nil }
        return KeyShortcut(
            key: key, command: mods.contains(.command), shift: mods.contains(.shift),
            option: mods.contains(.option), control: mods.contains(.control)
        )
    }
}

struct KeyBindingEntry: Codable {
    let id: String
    let label: String
    let category: String
    var shortcut: KeyShortcut
}

// MARK: - User Settings

final class BellithSettings {
    static let shared = BellithSettings()
    static let didChangeNotification = Notification.Name("BellithSettingsDidChange")

    private let defaults = UserDefaults.standard

    // Appearance
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

    var tabMode: String {
        get { defaults.string(forKey: "tabMode") ?? "sidebar" }
        set { defaults.set(newValue, forKey: "tabMode"); notify() }
    }

    // Terminal
    var shell: String {
        get { defaults.string(forKey: "shell") ?? "" } // empty = login shell
        set { defaults.set(newValue, forKey: "shell"); notify() }
    }

    var scrollbackLines: Int {
        get { let v = defaults.integer(forKey: "scrollbackLines"); return v > 0 ? v : 10000 }
        set { defaults.set(newValue, forKey: "scrollbackLines"); notify() }
    }

    var mouseHideWhileTyping: Bool {
        get {
            if defaults.object(forKey: "mouseHideWhileTyping") != nil {
                return defaults.bool(forKey: "mouseHideWhileTyping")
            }
            return true
        }
        set { defaults.set(newValue, forKey: "mouseHideWhileTyping"); notify() }
    }

    var confirmClose: Bool {
        get { defaults.bool(forKey: "confirmClose") }
        set { defaults.set(newValue, forKey: "confirmClose"); notify() }
    }

    var cursorBlink: Bool {
        get { defaults.bool(forKey: "cursorBlink") }
        set { defaults.set(newValue, forKey: "cursorBlink"); notify() }
    }

    var windowPaddingX: Int {
        get { let v = defaults.integer(forKey: "windowPaddingX"); return v > 0 ? v : 10 }
        set { defaults.set(newValue, forKey: "windowPaddingX"); notify() }
    }

    var windowPaddingY: Int {
        get { let v = defaults.integer(forKey: "windowPaddingY"); return v > 0 ? v : 38 }
        set { defaults.set(newValue, forKey: "windowPaddingY"); notify() }
    }

    // Keybindings
    var keybindings: [KeyBindingEntry] {
        get {
            if let data = defaults.data(forKey: "keybindings"),
               let decoded = try? JSONDecoder().decode([KeyBindingEntry].self, from: data) {
                // Merge with defaults in case new actions were added
                var map = Dictionary(uniqueKeysWithValues: decoded.map { ($0.id, $0) })
                for def in Self.defaultKeybindings {
                    if map[def.id] == nil { map[def.id] = def }
                }
                return Self.defaultKeybindings.map { map[$0.id] ?? $0 }
            }
            return Self.defaultKeybindings
        }
        set {
            if let data = try? JSONEncoder().encode(newValue) {
                defaults.set(data, forKey: "keybindings")
            }
            notify()
        }
    }

    func shortcut(for actionId: String) -> KeyShortcut? {
        keybindings.first { $0.id == actionId }?.shortcut
    }

    static let defaultKeybindings: [KeyBindingEntry] = [
        // Tabs
        KeyBindingEntry(id: "newTab", label: "New Tab", category: "Tabs",
                        shortcut: KeyShortcut(key: "t", command: true, shift: false, option: false, control: false)),
        KeyBindingEntry(id: "closeTab", label: "Close Tab", category: "Tabs",
                        shortcut: KeyShortcut(key: "w", command: true, shift: false, option: false, control: false)),
        KeyBindingEntry(id: "nextTab", label: "Next Tab", category: "Tabs",
                        shortcut: KeyShortcut(key: "]", command: true, shift: true, option: false, control: false)),
        KeyBindingEntry(id: "prevTab", label: "Previous Tab", category: "Tabs",
                        shortcut: KeyShortcut(key: "[", command: true, shift: true, option: false, control: false)),
        // Panes
        KeyBindingEntry(id: "splitRight", label: "Split Right", category: "Panes",
                        shortcut: KeyShortcut(key: "d", command: true, shift: false, option: false, control: false)),
        KeyBindingEntry(id: "splitDown", label: "Split Down", category: "Panes",
                        shortcut: KeyShortcut(key: "d", command: true, shift: true, option: false, control: false)),
        KeyBindingEntry(id: "closePane", label: "Close Pane", category: "Panes",
                        shortcut: KeyShortcut(key: "w", command: true, shift: true, option: false, control: false)),
        // View
        KeyBindingEntry(id: "toggleSidebar", label: "Toggle Sidebar", category: "View",
                        shortcut: KeyShortcut(key: "b", command: true, shift: false, option: false, control: false)),
        KeyBindingEntry(id: "commandPalette", label: "Command Palette", category: "View",
                        shortcut: KeyShortcut(key: "k", command: true, shift: false, option: false, control: false)),
        KeyBindingEntry(id: "showHUD", label: "Show HUD", category: "View",
                        shortcut: KeyShortcut(key: "s", command: false, shift: false, option: true, control: false)),
        // Edit
        KeyBindingEntry(id: "copy", label: "Copy", category: "Edit",
                        shortcut: KeyShortcut(key: "c", command: true, shift: false, option: false, control: false)),
        KeyBindingEntry(id: "paste", label: "Paste", category: "Edit",
                        shortcut: KeyShortcut(key: "v", command: true, shift: false, option: false, control: false)),
    ]

    private func notify() {
        NotificationCenter.default.post(name: Self.didChangeNotification, object: self)
    }

    var resolvedTheme: ThemeColors {
        ThemeColors.allThemes.first { $0.name == themeName } ?? .tokyonight
    }
}

// MARK: - Ghostty Config Wrapper

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

    init(cloning other: TerminalConfig) {
        guard let src = other.config else { config = nil; return }
        config = ghostty_config_clone(src)
    }

    deinit { if let config { ghostty_config_free(config) } }

    func get<T>(_ key: String, _ out: UnsafeMutablePointer<T>) -> Bool {
        guard let config else { return false }
        return key.withCString { cKey in
            ghostty_config_get(config, out, cKey, UInt(MemoryLayout<T>.size))
        }
    }

    static func writeConfigFile() -> String? {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("bellith", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let s = BellithSettings.shared
        let file = dir.appendingPathComponent("config.conf")
        var lines = [
            "font-family = \(s.fontFamily)",
            "font-size = \(s.fontSize)",
            "theme = \(s.resolvedTheme.ghosttyTheme)",
            "background-opacity = \(s.backgroundOpacity)",
            "window-padding-x = \(s.windowPaddingX)",
            "window-padding-y = \(s.windowPaddingY),2",
            "window-padding-balance = false",
            "cursor-style = \(s.cursorStyle)",
            "cursor-style-blink = \(s.cursorBlink)",
            "scrollback-limit = \(s.scrollbackLines)",
            "shell-integration-features = no-cursor",
            "window-decoration = false",
            "window-save-state = never",
            "mouse-hide-while-typing = \(s.mouseHideWhileTyping)",
            "confirm-close-surface = \(s.confirmClose)",
        ]
        if !s.shell.isEmpty {
            lines.append("command = \(s.shell)")
        }

        do {
            try lines.joined(separator: "\n").write(to: file, atomically: true, encoding: .utf8)
            return file.path
        } catch {
            return nil
        }
    }
}
