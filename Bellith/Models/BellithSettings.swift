import AppKit

// MARK: - User Settings

final class BellithSettings {
    static let shared = BellithSettings()
    static let didChangeNotification = Notification.Name("BellithSettingsDidChange")

    let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

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

    var restoreSession: Bool {
        get {
            if defaults.object(forKey: "restoreSession") != nil {
                return defaults.bool(forKey: "restoreSession")
            }
            return true
        }
        set { defaults.set(newValue, forKey: "restoreSession"); notify() }
    }

    var cursorBlink: Bool {
        get { defaults.bool(forKey: "cursorBlink") }
        set { defaults.set(newValue, forKey: "cursorBlink"); notify() }
    }

    // Sidebar
    var sidebarPinned: Bool {
        get {
            if defaults.object(forKey: "sidebarPinned") != nil {
                return defaults.bool(forKey: "sidebarPinned")
            }
            return true // default to pinned
        }
        set { defaults.set(newValue, forKey: "sidebarPinned"); notify() }
    }

    /// Which tools to display in the sidebar quick-access section.
    /// Stored as an array of SmartPanelKind raw values.
    /// Defaults to all tools enabled.
    var sidebarTools: [String] {
        get {
            if let arr = defaults.stringArray(forKey: "sidebarTools") { return arr }
            return SmartPanelKind.allCases.map { $0.rawValue }
        }
        set { defaults.set(newValue, forKey: "sidebarTools"); notify() }
    }

    /// Whether to show the tools section in the sidebar at all.
    var sidebarShowTools: Bool {
        get {
            if defaults.object(forKey: "sidebarShowTools") != nil {
                return defaults.bool(forKey: "sidebarShowTools")
            }
            return true
        }
        set { defaults.set(newValue, forKey: "sidebarShowTools"); notify() }
    }

    // Appearance mode: "dark", "light", "system"
    var appearanceMode: String {
        get { defaults.string(forKey: "appearanceMode") ?? "dark" }
        set { defaults.set(newValue, forKey: "appearanceMode"); notify() }
    }

    // Quick Terminal
    var visorHotkey: String {
        get { defaults.string(forKey: "visorHotkey") ?? "option+`" }
        set { defaults.set(newValue, forKey: "visorHotkey"); notify() }
    }

    var visorHideOnFocusLoss: Bool {
        get {
            if defaults.object(forKey: "visorHideOnFocusLoss") != nil {
                return defaults.bool(forKey: "visorHideOnFocusLoss")
            }
            return true
        }
        set { defaults.set(newValue, forKey: "visorHideOnFocusLoss"); notify() }
    }

    var visorPosition: String {
        get { defaults.string(forKey: "visorPosition") ?? "top" }
        set { defaults.set(newValue, forKey: "visorPosition"); notify() }
    }

    var visorWidthPercent: Double {
        get {
            let v = defaults.double(forKey: "visorWidthPercent")
            return v > 0 ? v : 0.85
        }
        set { defaults.set(newValue, forKey: "visorWidthPercent"); notify() }
    }

    var visorHeightPercent: Double {
        get {
            let v = defaults.double(forKey: "visorHeightPercent")
            return v > 0 ? v : 0.45
        }
        set { defaults.set(newValue, forKey: "visorHeightPercent"); notify() }
    }

    // Terminal
    var workingDirectory: String {
        get { defaults.string(forKey: "workingDirectory") ?? "" }
        set { defaults.set(newValue, forKey: "workingDirectory"); notify() }
    }

    var bellMode: String {
        get { defaults.string(forKey: "bellMode") ?? "system" } // system, visual, bounce, none
        set { defaults.set(newValue, forKey: "bellMode"); notify() }
    }

    var wordSeparators: String {
        get { defaults.string(forKey: "wordSeparators") ?? " \t!@#$%^&*()=+[]{}\\|;:'\",.<>?/`~" }
        set { defaults.set(newValue, forKey: "wordSeparators"); notify() }
    }

    // Traffic lights
    var trafficLightAutoHide: Bool {
        get {
            if defaults.object(forKey: "trafficLightAutoHide") != nil {
                return defaults.bool(forKey: "trafficLightAutoHide")
            }
            return true
        }
        set { defaults.set(newValue, forKey: "trafficLightAutoHide"); notify() }
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
        KeyBindingEntry(id: "navLeft", label: "Focus Left Pane", category: "Panes",
                        shortcut: KeyShortcut(key: "h", command: true, shift: false, option: true, control: false)),
        KeyBindingEntry(id: "navDown", label: "Focus Down Pane", category: "Panes",
                        shortcut: KeyShortcut(key: "j", command: true, shift: false, option: true, control: false)),
        KeyBindingEntry(id: "navUp", label: "Focus Up Pane", category: "Panes",
                        shortcut: KeyShortcut(key: "k", command: true, shift: false, option: true, control: false)),
        KeyBindingEntry(id: "navRight", label: "Focus Right Pane", category: "Panes",
                        shortcut: KeyShortcut(key: "l", command: true, shift: false, option: true, control: false)),
        KeyBindingEntry(id: "resizeLeft", label: "Resize Pane Left", category: "Panes",
                        shortcut: KeyShortcut(key: "h", command: true, shift: true, option: true, control: false)),
        KeyBindingEntry(id: "resizeDown", label: "Resize Pane Down", category: "Panes",
                        shortcut: KeyShortcut(key: "j", command: true, shift: true, option: true, control: false)),
        KeyBindingEntry(id: "resizeUp", label: "Resize Pane Up", category: "Panes",
                        shortcut: KeyShortcut(key: "k", command: true, shift: true, option: true, control: false)),
        KeyBindingEntry(id: "resizeRight", label: "Resize Pane Right", category: "Panes",
                        shortcut: KeyShortcut(key: "l", command: true, shift: true, option: true, control: false)),
        KeyBindingEntry(id: "zoomPane", label: "Zoom Pane", category: "Panes",
                        shortcut: KeyShortcut(key: "\r", command: true, shift: true, option: false, control: false)),
        KeyBindingEntry(id: "equalizePanes", label: "Equalize Panes", category: "Panes",
                        shortcut: KeyShortcut(key: "=", command: true, shift: false, option: true, control: false)),
        KeyBindingEntry(id: "broadcastInput", label: "Broadcast Input", category: "Panes",
                        shortcut: KeyShortcut(key: "i", command: true, shift: false, option: true, control: false)),
        // View
        KeyBindingEntry(id: "toggleSidebar", label: "Toggle Sidebar", category: "View",
                        shortcut: KeyShortcut(key: "b", command: true, shift: false, option: false, control: false)),
        KeyBindingEntry(id: "commandPalette", label: "Command Palette", category: "View",
                        shortcut: KeyShortcut(key: "k", command: true, shift: false, option: false, control: false)),

        // Edit
        KeyBindingEntry(id: "copy", label: "Copy", category: "Edit",
                        shortcut: KeyShortcut(key: "c", command: true, shift: false, option: false, control: false)),
        KeyBindingEntry(id: "paste", label: "Paste", category: "Edit",
                        shortcut: KeyShortcut(key: "v", command: true, shift: false, option: false, control: false)),
        KeyBindingEntry(id: "search", label: "Find", category: "Edit",
                        shortcut: KeyShortcut(key: "f", command: true, shift: false, option: false, control: false)),
        // Window
        KeyBindingEntry(id: "newWindow", label: "New Window", category: "View",
                        shortcut: KeyShortcut(key: "n", command: true, shift: false, option: false, control: false)),
        KeyBindingEntry(id: "toggleFullscreen", label: "Toggle Fullscreen", category: "View",
                        shortcut: KeyShortcut(key: "f", command: true, shift: false, option: false, control: true)),
        KeyBindingEntry(id: "fontSizeUp", label: "Increase Font Size", category: "View",
                        shortcut: KeyShortcut(key: "=", command: true, shift: false, option: false, control: false)),
        KeyBindingEntry(id: "fontSizeDown", label: "Decrease Font Size", category: "View",
                        shortcut: KeyShortcut(key: "-", command: true, shift: false, option: false, control: false)),
        KeyBindingEntry(id: "fontSizeReset", label: "Reset Font Size", category: "View",
                        shortcut: KeyShortcut(key: "0", command: true, shift: false, option: false, control: false)),
        KeyBindingEntry(id: "reloadConfig", label: "Reload Config", category: "View",
                        shortcut: KeyShortcut(key: ",", command: true, shift: true, option: false, control: false)),
        // New actions
        KeyBindingEntry(id: "reopenTab", label: "Reopen Closed Tab", category: "Tabs",
                        shortcut: KeyShortcut(key: "t", command: true, shift: true, option: false, control: false)),
        KeyBindingEntry(id: "clearBuffer", label: "Clear Buffer", category: "Edit",
                        shortcut: KeyShortcut(key: "k", command: true, shift: true, option: false, control: false)),
        KeyBindingEntry(id: "selectAll", label: "Select All", category: "Edit",
                        shortcut: KeyShortcut(key: "a", command: true, shift: false, option: false, control: false)),
    ]

    func notify() {
        NotificationCenter.default.post(name: Self.didChangeNotification, object: self)
    }

    var resolvedTheme: ThemeColors {
        ThemeColors.allThemes.first { $0.name == themeName } ?? .tokyonight
    }
}
