import AppKit
import Darwin

enum TerminalOptionKeyBehavior: String, CaseIterable {
    case disabled
    case left
    case right
    case both

    var title: String {
        switch self {
        case .disabled: "Disabled"
        case .left: "Left Option"
        case .right: "Right Option"
        case .both: "Both Options"
        }
    }

    var ghosttyConfigValue: String {
        switch self {
        case .disabled: "false"
        case .left: "left"
        case .right: "right"
        case .both: "true"
        }
    }
}

// MARK: - Appearance Mode

enum AppAppearanceMode: String, CaseIterable {
    case system
    case dark
    case light

    var title: String {
        switch self {
        case .system: "System"
        case .dark: "Dark"
        case .light: "Light"
        }
    }
}

// MARK: - User Settings

final class BellithSettings {
    static let shared = BellithSettings()
    static let didChangeNotification = Notification.Name("BellithSettingsDidChange")
    static let defaultTerminalTerm = "xterm-ghostty"
    enum PersistedKeys {
        static let stringKeys: Set<String> = [
            "fontFamily", "cursorStyle", "darkThemeName", "lightThemeName", "tabMode",
            "shell", "terminalTerm", "visorPosition", "workingDirectory",
            "bellMode", "shortcutPreset", "localSessionBootstrap",
            "terminalOptionKeyBehavior", "appearanceMode",
            "activeTerminalProfileID",
        ]
        static let intKeys: Set<String> = [
            "fontSize", "scrollbackLines", "commandCompletionNotificationThreshold",
            "windowPaddingX", "windowPaddingY",
        ]
        static let doubleKeys: Set<String> = [
            "backgroundOpacity", "visorWidthPercent", "visorHeightPercent", "noiseIntensity",
        ]
        static let boolKeys: Set<String> = [
            "mouseHideWhileTyping", "confirmClose", "restoreSession", "cursorBlink",
            "inlineImagesEnabled",
            "scrollbackMinimapEnabled",
            "shellIntegrationEnabled", "shellIntegrationCursor", "shellIntegrationTitle",
            "shellIntegrationPath", "shellIntegrationSSHEnv", "shellIntegrationSSHTerminfo",
            "commandCompletionNotificationsEnabled", "errorFixSuggestionsEnabled",
            "sidebarPinned", "sidebarAutoHide",
            "sidebarShowTools", "visorHideOnFocusLoss", "trafficLightAutoHide",
            "oledChromeForDarkThemes", "wallpaperTint",
            "legacyPaneSupport",
            "showStatusBar", "showStatusBarContext", "showStatusBarPath",
            "showStatusBarGitWorktree", "showStatusBarGitBranch", "showStatusBarProcess",
            "showStatusBarGitHub", "showStatusBarSize",
            "fontLigaturesEnabled",
            "useRebrandShell", "openRebrandPanesByDefault",
            "showModifierHints",
        ]
        static let stringArrayKeys: Set<String> = [
            "sidebarTools",
        ]
        static let featureFlags = "featureFlags"
        static let keybindings = "keybindings"
        static let terminalProfiles = "terminalProfiles"
        static let all: Set<String> = stringKeys
            .union(intKeys)
            .union(doubleKeys)
            .union(boolKeys)
            .union(stringArrayKeys)
            .union([featureFlags, keybindings, terminalProfiles])
    }

    let defaults: UserDefaults
    private let smartPanelRegistry: SmartPanelRegistry
    let settingsFileURL: URL?
    var settingsFileObserver: DispatchSourceFileSystemObject?
    var lastPersistedSettingsFileData: Data?

    init(
        defaults: UserDefaults = .standard,
        smartPanelRegistry: SmartPanelRegistry = .shared,
        settingsFileURL: URL? = nil
    ) {
        self.defaults = defaults
        self.smartPanelRegistry = smartPanelRegistry
        self.settingsFileURL = settingsFileURL ?? Self.defaultSettingsFileURL(for: defaults)
        loadSettingsFileIfNeeded()
        migrateBuiltInSettingsWindowDefaultIfNeeded()
        migrateLegacyWindowPaddingIfNeeded()
        migrateLegacyProfileAppearanceToGlobalIfNeeded()
        persistSettingsFileIfNeeded()
        startObservingSettingsFileIfNeeded()
    }

    deinit {
        settingsFileObserver?.cancel()
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

    /// Programming ligatures (`calt`/`liga`/`clig`/`dlig` OpenType features).
    /// Default is `true` — most programming fonts ship ligatures on and users
    /// who chose Fira Code/JetBrains Mono/etc. expect them. When `false`,
    /// the generated Ghostty config emits negative `font-feature` directives
    /// to disable the common ligature feature tags.
    var fontLigaturesEnabled: Bool {
        get {
            if defaults.object(forKey: "fontLigaturesEnabled") == nil { return true }
            return defaults.bool(forKey: "fontLigaturesEnabled")
        }
        set { defaults.set(newValue, forKey: "fontLigaturesEnabled"); notify() }
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

    /// When true, a muted accent derived from the desktop wallpaper is overlaid
    /// on the translucent window chrome. Only visible when the frame is at all
    /// translucent (`backgroundOpacity < 1`).
    var wallpaperTint: Bool {
        get { defaults.bool(forKey: "wallpaperTint") }
        set { defaults.set(newValue, forKey: "wallpaperTint"); notify() }
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

    var scrollbackMinimapEnabled: Bool {
        get {
            if defaults.object(forKey: "scrollbackMinimapEnabled") != nil {
                return defaults.bool(forKey: "scrollbackMinimapEnabled")
            }
            return false
        }
        set { defaults.set(newValue, forKey: "scrollbackMinimapEnabled"); notify() }
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

    /// Enables Ghostty's inline image protocols (Kitty graphics + Sixel).
    /// When disabled, Ghostty's image storage limit is forced to 0 so tools
    /// like `icat`, `chafa`, `timg`, and Sixel emitters skip rendering.
    var inlineImagesEnabled: Bool {
        get {
            if defaults.object(forKey: "inlineImagesEnabled") != nil {
                return defaults.bool(forKey: "inlineImagesEnabled")
            }
            return true
        }
        set { defaults.set(newValue, forKey: "inlineImagesEnabled"); notify() }
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

    var errorFixSuggestionsEnabled: Bool {
        get {
            if defaults.object(forKey: "errorFixSuggestionsEnabled") != nil {
                return defaults.bool(forKey: "errorFixSuggestionsEnabled")
            }
            return true
        }
        set { defaults.set(newValue, forKey: "errorFixSuggestionsEnabled"); notify() }
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

    var appearanceMode: AppAppearanceMode {
        get {
            guard let rawValue = defaults.string(forKey: "appearanceMode"),
                  let mode = AppAppearanceMode(rawValue: rawValue) else {
                return .system
            }
            return mode
        }
        set { defaults.set(newValue.rawValue, forKey: "appearanceMode"); notify() }
    }

    /// Whether the system itself is currently in dark mode.
    var systemIsDark: Bool {
        let globalDefaults = UserDefaults.standard.persistentDomain(forName: UserDefaults.globalDomain)
        return (globalDefaults?["AppleInterfaceStyle"] as? String) == "Dark"
    }

    var resolvedIsDark: Bool {
        switch appearanceMode {
        case .system:
            systemIsDark
        case .dark:
            true
        case .light:
            false
        }
    }

    // Quick Terminal
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

    var localSessionBootstrap: SSHSessionBootstrap {
        get {
            guard let rawValue = defaults.string(forKey: "localSessionBootstrap"),
                  let bootstrap = SSHSessionBootstrap(rawValue: rawValue) else {
                return .none
            }
            return bootstrap
        }
        set { defaults.set(newValue.rawValue, forKey: "localSessionBootstrap"); notify() }
    }

    var terminalOptionKeyBehavior: TerminalOptionKeyBehavior {
        get {
            guard let rawValue = defaults.string(forKey: "terminalOptionKeyBehavior"),
                  let behavior = TerminalOptionKeyBehavior(rawValue: rawValue) else {
                return .left
            }
            return behavior
        }
        set { defaults.set(newValue.rawValue, forKey: "terminalOptionKeyBehavior"); notify() }
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

    /// Force true-black chrome for dark themes, regardless of the theme's own default.
    /// Has no effect on light themes or on themes that already declare OLED chrome.
    var oledChromeForDarkThemes: Bool {
        get { defaults.bool(forKey: "oledChromeForDarkThemes") }
        set { defaults.set(newValue, forKey: "oledChromeForDarkThemes"); notify() }
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

    /// Toggle for the from-scratch chrome rewrite. When true, windows render
    /// `RebrandShellView` instead of the legacy chrome built into
    /// `TerminalContainerView`. Default true while the rebrand is being
    /// stood up — flip via `defaults write com.rec.bellith useRebrandShell -bool NO`
    /// to fall back to the legacy chrome.
    var useRebrandShell: Bool {
        get {
            if defaults.object(forKey: "useRebrandShell") != nil {
                return defaults.bool(forKey: "useRebrandShell")
            }
            return true
        }
        set { defaults.set(newValue, forKey: "useRebrandShell"); notify() }
    }

    var openRebrandPanesByDefault: Bool {
        get {
            if defaults.object(forKey: "openRebrandPanesByDefault") != nil {
                return defaults.bool(forKey: "openRebrandPanesByDefault")
            }
            return true
        }
        set { defaults.set(newValue, forKey: "openRebrandPanesByDefault"); notify() }
    }

    /// When true, holding modifier keys (⌘, ⌥, ⌃, ⇧) reveals the contextual
    /// shortcut hint popover. Off by default — flip via
    /// `defaults write com.rec.bellith showModifierHints -bool YES`.
    var showModifierHints: Bool {
        get {
            if defaults.object(forKey: "showModifierHints") != nil {
                return defaults.bool(forKey: "showModifierHints")
            }
            return false
        }
        set { defaults.set(newValue, forKey: "showModifierHints"); notify() }
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
        get {
            if defaults.object(forKey: "windowPaddingX") != nil {
                return defaults.integer(forKey: "windowPaddingX")
            }
            return WindowPaddingDefaults.current
        }
        set { defaults.set(newValue, forKey: "windowPaddingX"); notify() }
    }

    var windowPaddingY: Int {
        get {
            if defaults.object(forKey: "windowPaddingY") != nil {
                return defaults.integer(forKey: "windowPaddingY")
            }
            return WindowPaddingDefaults.current
        }
        set { defaults.set(newValue, forKey: "windowPaddingY"); notify() }
    }

    var legacyPaneSupport: Bool {
        get {
            if useRebrandShell { return true }
            return defaults.bool(forKey: "legacyPaneSupport")
        }
        set { defaults.set(newValue, forKey: "legacyPaneSupport"); notify() }
    }

    var builtInSettingsWindowEnabled: Bool {
        get { isFeatureEnabled(.builtInSettingsWindow) }
        set { setFeature(.builtInSettingsWindow, enabled: newValue) }
    }

    var settingsFileLocation: URL? {
        settingsFileURL
    }

    func isFeatureEnabled(_ feature: BellithFeatureFlag) -> Bool {
        storedFeatureFlags[feature.rawValue] ?? feature.defaultValue
    }

    func setFeature(_ feature: BellithFeatureFlag, enabled: Bool) {
        var flags = storedFeatureFlags
        flags[feature.rawValue] = enabled
        defaults.set(flags, forKey: PersistedKeys.featureFlags)
        notify()
    }

    var shortcutPreset: ShortcutPresetID {
        get {
            guard let raw = defaults.string(forKey: "shortcutPreset"),
                  let preset = ShortcutPresetID(rawValue: raw) else { return .bellithHybrid }
            return preset
        }
        set { defaults.set(newValue.rawValue, forKey: "shortcutPreset"); notify() }
    }


    func notify() {
        persistSettingsFileIfNeeded()
        NotificationCenter.default.post(name: Self.didChangeNotification, object: self)
    }

    var resolvedTheme: ThemeColors {
        // Honor the macOS "Increase Contrast" accessibility setting by promoting
        // to a high-contrast variant. Users who have explicitly picked a
        // high-contrast theme already get it unchanged.
        if NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast {
            return resolvedIsDark ? .highContrastDark : .highContrastLight
        }
        let name = resolvedIsDark ? darkThemeName : lightThemeName
        var theme = ThemeColors.allThemes.first { $0.name == name } ?? .tokyonight
        if resolvedIsDark && !theme.isLight && oledChromeForDarkThemes {
            theme.darkChromeStyle = .oled
        }
        return theme
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

    private static func defaultSettingsFileURL(for defaults: UserDefaults) -> URL? {
        guard defaults === UserDefaults.standard else { return nil }
        return TerminalConfig.settingsConfigurationDirectory()?
            .appendingPathComponent("settings.json", isDirectory: false)
    }

    var storedFeatureFlags: [String: Bool] {
        guard let object = defaults.dictionary(forKey: PersistedKeys.featureFlags) else { return [:] }
        return Self.featureFlags(from: object)
    }

}
