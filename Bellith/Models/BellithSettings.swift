import AppKit

// MARK: - User Settings

final class BellithSettings {
    static let shared = BellithSettings()
    static let didChangeNotification = Notification.Name("BellithSettingsDidChange")
    static let defaultTerminalTerm = "xterm-ghostty"

    let defaults: UserDefaults
    private let smartPanelRegistry: SmartPanelRegistry

    init(defaults: UserDefaults = .standard, smartPanelRegistry: SmartPanelRegistry = .shared) {
        self.defaults = defaults
        self.smartPanelRegistry = smartPanelRegistry
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

    var darkThemeName: String {
        get { defaults.string(forKey: "darkThemeName") ?? defaults.string(forKey: "themeName") ?? "Tokyo Night" }
        set { defaults.set(newValue, forKey: "darkThemeName"); notify() }
    }

    var lightThemeName: String {
        get { defaults.string(forKey: "lightThemeName") ?? "Tokyo Night Light" }
        set { defaults.set(newValue, forKey: "lightThemeName"); notify() }
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

    var terminalTerm: String {
        get { defaults.string(forKey: "terminalTerm") ?? "" } // empty = Ghostty default TERM
        set {
            defaults.set(newValue.trimmingCharacters(in: .whitespacesAndNewlines), forKey: "terminalTerm")
            notify()
        }
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

    var shellIntegrationEnabled: Bool {
        get {
            if defaults.object(forKey: "shellIntegrationEnabled") != nil {
                return defaults.bool(forKey: "shellIntegrationEnabled")
            }
            return true
        }
        set { defaults.set(newValue, forKey: "shellIntegrationEnabled"); notify() }
    }

    var shellIntegrationCursor: Bool {
        get {
            if defaults.object(forKey: "shellIntegrationCursor") != nil {
                return defaults.bool(forKey: "shellIntegrationCursor")
            }
            return true
        }
        set { defaults.set(newValue, forKey: "shellIntegrationCursor"); notify() }
    }

    var shellIntegrationTitle: Bool {
        get {
            if defaults.object(forKey: "shellIntegrationTitle") != nil {
                return defaults.bool(forKey: "shellIntegrationTitle")
            }
            return true
        }
        set { defaults.set(newValue, forKey: "shellIntegrationTitle"); notify() }
    }

    var shellIntegrationPath: Bool {
        get {
            if defaults.object(forKey: "shellIntegrationPath") != nil {
                return defaults.bool(forKey: "shellIntegrationPath")
            }
            return true
        }
        set { defaults.set(newValue, forKey: "shellIntegrationPath"); notify() }
    }

    var shellIntegrationSSHEnv: Bool {
        get {
            if defaults.object(forKey: "shellIntegrationSSHEnv") != nil {
                return defaults.bool(forKey: "shellIntegrationSSHEnv")
            }
            return true
        }
        set { defaults.set(newValue, forKey: "shellIntegrationSSHEnv"); notify() }
    }

    var shellIntegrationSSHTerminfo: Bool {
        get {
            if defaults.object(forKey: "shellIntegrationSSHTerminfo") != nil {
                return defaults.bool(forKey: "shellIntegrationSSHTerminfo")
            }
            return false
        }
        set { defaults.set(newValue, forKey: "shellIntegrationSSHTerminfo"); notify() }
    }

    var commandCompletionNotificationsEnabled: Bool {
        get {
            if defaults.object(forKey: "commandCompletionNotificationsEnabled") != nil {
                return defaults.bool(forKey: "commandCompletionNotificationsEnabled")
            }
            return true
        }
        set { defaults.set(newValue, forKey: "commandCompletionNotificationsEnabled"); notify() }
    }

    var commandCompletionNotificationThreshold: Int {
        get {
            let value = defaults.integer(forKey: "commandCompletionNotificationThreshold")
            return value > 0 ? value : 10
        }
        set { defaults.set(max(1, newValue), forKey: "commandCompletionNotificationThreshold"); notify() }
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

    var sidebarAutoHide: Bool {
        get {
            if defaults.object(forKey: "sidebarAutoHide") != nil {
                return defaults.bool(forKey: "sidebarAutoHide")
            }
            return false
        }
        set { defaults.set(newValue, forKey: "sidebarAutoHide"); notify() }
    }

    /// Which tools to display in the sidebar quick-access section.
    /// Stored as an array of smart panel plugin identifiers.
    /// Defaults to all built-in tool plugins enabled.
    var sidebarTools: [String] {
        get {
            if let arr = defaults.stringArray(forKey: "sidebarTools") { return arr }
            return smartPanelRegistry.allPlugins
                .filter(\.sidebarEnabledByDefault)
                .map(\.id)
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

    /// Whether the system is currently in dark mode.
    var systemIsDark: Bool {
        NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
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

    var noiseIntensity: Double {
        get {
            if defaults.object(forKey: "noiseIntensity") != nil {
                return defaults.double(forKey: "noiseIntensity")
            }
            return 0.6
        }
        set { defaults.set(newValue, forKey: "noiseIntensity"); notify() }
    }

    var showStatusBar: Bool {
        get {
            if defaults.object(forKey: "showStatusBar") != nil {
                return defaults.bool(forKey: "showStatusBar")
            }
            return true
        }
        set { defaults.set(newValue, forKey: "showStatusBar"); notify() }
    }

    var showStatusBarContext: Bool {
        get {
            if defaults.object(forKey: "showStatusBarContext") != nil {
                return defaults.bool(forKey: "showStatusBarContext")
            }
            return false
        }
        set { defaults.set(newValue, forKey: "showStatusBarContext"); notify() }
    }

    var showStatusBarPath: Bool {
        get {
            if defaults.object(forKey: "showStatusBarPath") != nil {
                return defaults.bool(forKey: "showStatusBarPath")
            }
            return false
        }
        set { defaults.set(newValue, forKey: "showStatusBarPath"); notify() }
    }

    var showStatusBarGitWorktree: Bool {
        get {
            if defaults.object(forKey: "showStatusBarGitWorktree") != nil {
                return defaults.bool(forKey: "showStatusBarGitWorktree")
            }
            return false
        }
        set { defaults.set(newValue, forKey: "showStatusBarGitWorktree"); notify() }
    }

    var showStatusBarGitBranch: Bool {
        get {
            if defaults.object(forKey: "showStatusBarGitBranch") != nil {
                return defaults.bool(forKey: "showStatusBarGitBranch")
            }
            return true
        }
        set { defaults.set(newValue, forKey: "showStatusBarGitBranch"); notify() }
    }

    var showStatusBarProcess: Bool {
        get {
            if defaults.object(forKey: "showStatusBarProcess") != nil {
                return defaults.bool(forKey: "showStatusBarProcess")
            }
            return false
        }
        set { defaults.set(newValue, forKey: "showStatusBarProcess"); notify() }
    }

    var showStatusBarGitHub: Bool {
        get {
            if defaults.object(forKey: "showStatusBarGitHub") != nil {
                return defaults.bool(forKey: "showStatusBarGitHub")
            }
            return true
        }
        set { defaults.set(newValue, forKey: "showStatusBarGitHub"); notify() }
    }

    var showStatusBarSize: Bool {
        get {
            if defaults.object(forKey: "showStatusBarSize") != nil {
                return defaults.bool(forKey: "showStatusBarSize")
            }
            return false
        }
        set { defaults.set(newValue, forKey: "showStatusBarSize"); notify() }
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
                        shortcut: KeyShortcut(key: "e", command: true, shift: true, option: false, control: false)),
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
        let name = systemIsDark ? darkThemeName : lightThemeName
        return ThemeColors.allThemes.first { $0.name == name } ?? .tokyonight
    }

    var shellIntegrationMode: String {
        shellIntegrationEnabled ? "detect" : "none"
    }

    var shellIntegrationFeatures: String {
        [
            (shellIntegrationCursor, "cursor"),
            (shellIntegrationTitle, "title"),
            (shellIntegrationPath, "path"),
            (shellIntegrationSSHEnv, "ssh-env"),
            (shellIntegrationSSHTerminfo, "ssh-terminfo")
        ]
        .map { $0.0 ? $0.1 : "no-\($0.1)" }
        .joined(separator: ",")
    }

    var effectiveTerminalTerm: String {
        let trimmed = terminalTerm.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? Self.defaultTerminalTerm : trimmed
    }
}
