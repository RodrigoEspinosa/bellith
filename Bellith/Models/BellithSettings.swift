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
    private enum WindowPaddingDefaults {
        static let migrationKey = "didMigrateWindowPaddingDefaults"
        static let legacyX = 10
        static let legacyY = 38
        static let current = 0
    }
    private enum PersistedKeys {
        static let stringKeys: Set<String> = [
            "fontFamily", "cursorStyle", "darkThemeName", "lightThemeName", "tabMode",
            "shell", "terminalTerm", "visorHotkey", "visorPosition", "workingDirectory",
            "bellMode", "wordSeparators", "shortcutPreset", "localSessionBootstrap",
            "terminalOptionKeyBehavior", "appearanceMode",
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
            "shellIntegrationEnabled", "shellIntegrationCursor", "shellIntegrationTitle",
            "shellIntegrationPath", "shellIntegrationSSHEnv", "shellIntegrationSSHTerminfo",
            "commandCompletionNotificationsEnabled", "sidebarPinned", "sidebarAutoHide",
            "sidebarShowTools", "visorHideOnFocusLoss", "trafficLightAutoHide",
            "legacyPaneSupport",
            "showStatusBar", "showStatusBarContext", "showStatusBarPath",
            "showStatusBarGitWorktree", "showStatusBarGitBranch", "showStatusBarProcess",
            "showStatusBarGitHub", "showStatusBarSize",
        ]
        static let stringArrayKeys: Set<String> = [
            "sidebarTools",
        ]
        static let featureFlags = "featureFlags"
        static let keybindings = "keybindings"
        static let all: Set<String> = stringKeys
            .union(intKeys)
            .union(doubleKeys)
            .union(boolKeys)
            .union(stringArrayKeys)
            .union([featureFlags, keybindings])
    }

    let defaults: UserDefaults
    private let smartPanelRegistry: SmartPanelRegistry
    private let settingsFileURL: URL?
    private var settingsFileObserver: DispatchSourceFileSystemObject?
    private var lastPersistedSettingsFileData: Data?

    init(
        defaults: UserDefaults = .standard,
        smartPanelRegistry: SmartPanelRegistry = .shared,
        settingsFileURL: URL? = nil
    ) {
        self.defaults = defaults
        self.smartPanelRegistry = smartPanelRegistry
        self.settingsFileURL = settingsFileURL ?? Self.defaultSettingsFileURL(for: defaults)
        loadSettingsFileIfNeeded()
        migrateLegacyWindowPaddingIfNeeded()
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

    var wordSeparators: String {
        get { defaults.string(forKey: "wordSeparators") ?? " \t!@#$%^&*()=+[]{}\\|;:'\",.<>?/`~" }
        set { defaults.set(newValue, forKey: "wordSeparators"); notify() }
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
        get { defaults.bool(forKey: "legacyPaneSupport") }
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

    // Keybindings
    var keybindings: [KeyBindingEntry] {
        get {
            let visibleDefaults = activeDefaultKeybindings
            if let data = defaults.data(forKey: "keybindings"),
               let decoded = try? JSONDecoder().decode([KeyBindingEntry].self, from: data) {
                let map = Dictionary(uniqueKeysWithValues: decoded.map { ($0.id, $0) })
                return visibleDefaults.map { mergeBinding($0, persisted: map[$0.id]) }
            }
            return visibleDefaults
        }
        set {
            if let data = try? JSONEncoder().encode(newValue) {
                defaults.set(data, forKey: "keybindings")
            }
            notify()
        }
    }

    func shortcut(for actionId: String) -> KeyShortcut? {
        binding(for: actionId)?.primaryShortcut
    }

    func shortcuts(for actionId: String) -> [KeyShortcut] {
        binding(for: actionId)?.allShortcuts ?? []
    }

    func shortcutSummary(for actionId: String) -> String? {
        guard let binding = binding(for: actionId), !binding.allShortcuts.isEmpty else { return nil }
        return binding.shortcutSummary
    }

    func binding(for actionId: String) -> KeyBindingEntry? {
        keybindings.first { $0.id == actionId }
    }

    func effectiveShortcutMap(for scope: ShortcutScope? = nil) -> [String: [KeyShortcut]] {
        keybindings.reduce(into: [String: [KeyShortcut]]()) { map, binding in
            guard scope == nil || binding.scope == scope else { return }
            map[binding.id] = binding.allShortcuts
        }
    }

    func conflicts() -> [ShortcutConflict] {
        let bindings = keybindings
        var groups: [KeyShortcut: [String]] = [:]

        for binding in bindings {
            for shortcut in binding.allShortcuts {
                groups[shortcut, default: []].append(binding.id)
            }
        }

        return groups
            .compactMap { shortcut, actionIDs in
                let uniqueActionIDs = Array(Set(actionIDs)).sorted()
                guard uniqueActionIDs.count > 1 else { return nil }
                return ShortcutConflict(shortcut: shortcut, actionIDs: uniqueActionIDs)
            }
            .sorted { $0.shortcut.displayString < $1.shortcut.displayString }
    }

    func reset(actionId: String) {
        guard let index = keybindings.firstIndex(where: { $0.id == actionId }),
              let defaultBinding = activeDefaultKeybindings.first(where: { $0.id == actionId }) else { return }
        var updated = keybindings
        updated[index] = defaultBinding
        keybindings = updated
    }

    func reset(category: String) {
        let defaultsByID = Dictionary(uniqueKeysWithValues: activeDefaultKeybindings.map { ($0.id, $0) })
        let updated = keybindings.map { binding in
            guard binding.category == category, let defaultBinding = defaultsByID[binding.id] else { return binding }
            return defaultBinding
        }
        keybindings = updated
    }

    func applyPreset(_ preset: ShortcutPresetID) {
        defaults.set(preset.rawValue, forKey: "shortcutPreset")
        keybindings = Self.defaultKeybindings(for: preset, legacyPaneSupport: legacyPaneSupport)
    }

    private var activeDefaultKeybindings: [KeyBindingEntry] {
        Self.defaultKeybindings(for: shortcutPreset, legacyPaneSupport: legacyPaneSupport)
    }

    private func mergeBinding(_ defaultBinding: KeyBindingEntry, persisted: KeyBindingEntry?) -> KeyBindingEntry {
        guard let persisted else { return defaultBinding }
        var merged = defaultBinding
        merged.primaryShortcut = persisted.primaryShortcut
        merged.alternateShortcuts = persisted.alternateShortcuts.filter {
            persisted.primaryShortcut == nil || $0 != persisted.primaryShortcut
        }
        merged.presetSource = persisted.presetSource
        return merged
    }

    private func migrateLegacyWindowPaddingIfNeeded() {
        guard !defaults.bool(forKey: WindowPaddingDefaults.migrationKey) else { return }
        guard defaults.object(forKey: "windowPaddingX") != nil,
              defaults.object(forKey: "windowPaddingY") != nil else { return }

        let storedX = defaults.integer(forKey: "windowPaddingX")
        let storedY = defaults.integer(forKey: "windowPaddingY")
        defer { defaults.set(true, forKey: WindowPaddingDefaults.migrationKey) }
        guard storedX == WindowPaddingDefaults.legacyX,
              storedY == WindowPaddingDefaults.legacyY else { return }

        defaults.set(WindowPaddingDefaults.current, forKey: "windowPaddingX")
        defaults.set(WindowPaddingDefaults.current, forKey: "windowPaddingY")
    }

    static let defaultKeybindings: [KeyBindingEntry] = defaultKeybindings(for: .bellithHybrid, legacyPaneSupport: false)

    static func defaultKeybindings(
        for preset: ShortcutPresetID,
        legacyPaneSupport: Bool
    ) -> [KeyBindingEntry] {
        ShortcutDefinitionLibrary.bindings(for: preset, legacyPaneSupport: legacyPaneSupport)
    }

    static let legacyPaneActionIDs: Set<String> = [
        "splitRight",
        "splitDown",
        "closePane",
        "navLeft",
        "navDown",
        "navUp",
        "navRight",
        "resizeLeft",
        "resizeDown",
        "resizeUp",
        "resizeRight",
        "zoomPane",
        "equalizePanes",
        "broadcastInput",
    ]

    func notify() {
        persistSettingsFileIfNeeded()
        NotificationCenter.default.post(name: Self.didChangeNotification, object: self)
    }

    var resolvedTheme: ThemeColors {
        let name = resolvedIsDark ? darkThemeName : lightThemeName
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

    private static func defaultSettingsFileURL(for defaults: UserDefaults) -> URL? {
        guard defaults === UserDefaults.standard else { return nil }
        return TerminalConfig.settingsConfigurationDirectory()?
            .appendingPathComponent("settings.json", isDirectory: false)
    }

    private var storedFeatureFlags: [String: Bool] {
        guard let object = defaults.dictionary(forKey: PersistedKeys.featureFlags) else { return [:] }
        return Self.featureFlags(from: object)
    }

    private static func featureFlags(from object: [String: Any]) -> [String: Bool] {
        object.reduce(into: [String: Bool]()) { result, entry in
            guard let number = entry.value as? NSNumber else { return }
            result[entry.key] = number.boolValue
        }
    }

    private var featureFlagsForSettingsFile: [String: Bool] {
        var flags = storedFeatureFlags
        for feature in BellithFeatureFlag.allCases {
            flags[feature.rawValue] = isFeatureEnabled(feature)
        }
        return flags
    }

    private func loadSettingsFileIfNeeded() {
        guard let settingsFileURL,
              let data = try? Data(contentsOf: settingsFileURL) else {
            return
        }

        applySettingsFileData(data)
    }

    private func applySettingsFileData(_ data: Data) {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return
        }

        PersistedKeys.all.forEach { defaults.removeObject(forKey: $0) }
        for (key, value) in object {
            applyPersistedValue(value, forKey: key)
        }
        lastPersistedSettingsFileData = data
    }

    private func applyPersistedValue(_ value: Any, forKey key: String) {
        switch key {
        case PersistedKeys.keybindings:
            guard JSONSerialization.isValidJSONObject(value),
                  let jsonData = try? JSONSerialization.data(withJSONObject: value),
                  let decoded = try? JSONDecoder().decode([KeyBindingEntry].self, from: jsonData),
                  let encoded = try? JSONEncoder().encode(decoded) else { return }
            defaults.set(encoded, forKey: key)

        case _ where PersistedKeys.stringKeys.contains(key):
            guard let stringValue = value as? String else { return }
            defaults.set(stringValue, forKey: key)

        case _ where PersistedKeys.intKeys.contains(key):
            guard let number = value as? NSNumber else { return }
            defaults.set(number.intValue, forKey: key)

        case _ where PersistedKeys.doubleKeys.contains(key):
            guard let number = value as? NSNumber else { return }
            defaults.set(number.doubleValue, forKey: key)

        case _ where PersistedKeys.boolKeys.contains(key):
            guard let number = value as? NSNumber else { return }
            defaults.set(number.boolValue, forKey: key)

        case PersistedKeys.featureFlags:
            guard let dictionaryValue = value as? [String: Any] else { return }
            defaults.set(Self.featureFlags(from: dictionaryValue), forKey: key)

        case _ where PersistedKeys.stringArrayKeys.contains(key):
            guard let arrayValue = value as? [String] else { return }
            defaults.set(arrayValue, forKey: key)

        default:
            return
        }
    }

    private func persistSettingsFileIfNeeded() {
        guard let settingsFileURL else { return }
        let directory = settingsFileURL.deletingLastPathComponent()

        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let data = try settingsFileData()
            try data.write(to: settingsFileURL, options: .atomic)
            lastPersistedSettingsFileData = data
        } catch {
            return
        }
    }

    private func settingsFileData() throws -> Data {
        let encodedKeybindings: Any
        do {
            let encoded = try JSONEncoder().encode(keybindings)
            encodedKeybindings = try JSONSerialization.jsonObject(with: encoded)
        } catch {
            encodedKeybindings = []
        }

        let object: [String: Any] = [
            "appearanceMode": appearanceMode.rawValue,
            "backgroundOpacity": roundedForSettingsFile(backgroundOpacity),
            "bellMode": bellMode,
            "commandCompletionNotificationThreshold": commandCompletionNotificationThreshold,
            "commandCompletionNotificationsEnabled": commandCompletionNotificationsEnabled,
            "confirmClose": confirmClose,
            "cursorBlink": cursorBlink,
            "cursorStyle": cursorStyle,
            "darkThemeName": darkThemeName,
            "fontFamily": fontFamily,
            "fontSize": fontSize,
            "featureFlags": featureFlagsForSettingsFile,
            "inlineImagesEnabled": inlineImagesEnabled,
            "keybindings": encodedKeybindings,
            "lightThemeName": lightThemeName,
            "mouseHideWhileTyping": mouseHideWhileTyping,
            "noiseIntensity": roundedForSettingsFile(noiseIntensity),
            "restoreSession": restoreSession,
            "scrollbackLines": scrollbackLines,
            "shell": shell,
            "legacyPaneSupport": legacyPaneSupport,
            "localSessionBootstrap": localSessionBootstrap.rawValue,
            "shellIntegrationCursor": shellIntegrationCursor,
            "shellIntegrationEnabled": shellIntegrationEnabled,
            "shellIntegrationPath": shellIntegrationPath,
            "shellIntegrationSSHEnv": shellIntegrationSSHEnv,
            "shellIntegrationSSHTerminfo": shellIntegrationSSHTerminfo,
            "shellIntegrationTitle": shellIntegrationTitle,
            "showStatusBar": showStatusBar,
            "showStatusBarContext": showStatusBarContext,
            "showStatusBarGitBranch": showStatusBarGitBranch,
            "showStatusBarGitHub": showStatusBarGitHub,
            "showStatusBarGitWorktree": showStatusBarGitWorktree,
            "showStatusBarPath": showStatusBarPath,
            "showStatusBarProcess": showStatusBarProcess,
            "showStatusBarSize": showStatusBarSize,
            "shortcutPreset": shortcutPreset.rawValue,
            "sidebarAutoHide": sidebarAutoHide,
            "sidebarPinned": sidebarPinned,
            "sidebarShowTools": sidebarShowTools,
            "sidebarTools": sidebarTools,
            "tabMode": tabMode,
            "terminalOptionKeyBehavior": terminalOptionKeyBehavior.rawValue,
            "terminalTerm": terminalTerm,
            "trafficLightAutoHide": trafficLightAutoHide,
            "visorHeightPercent": roundedForSettingsFile(visorHeightPercent),
            "visorHideOnFocusLoss": visorHideOnFocusLoss,
            "visorHotkey": visorHotkey,
            "visorPosition": visorPosition,
            "visorWidthPercent": roundedForSettingsFile(visorWidthPercent),
            "windowPaddingX": windowPaddingX,
            "windowPaddingY": windowPaddingY,
            "wordSeparators": wordSeparators,
            "workingDirectory": workingDirectory,
        ]

        return try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
    }

    private func roundedForSettingsFile(_ value: Double) -> Double {
        (value * 100).rounded() / 100
    }

    private func startObservingSettingsFileIfNeeded() {
        guard let settingsFileURL else { return }
        let directoryURL = settingsFileURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)

        settingsFileObserver?.cancel()
        settingsFileObserver = nil

        let descriptor = open(directoryURL.path, O_EVTONLY)
        guard descriptor >= 0 else { return }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: [.write, .rename, .delete],
            queue: .main
        )
        source.setEventHandler { [weak self] in
            self?.reloadSettingsFileFromDiskIfNeeded()
        }
        source.setCancelHandler { [descriptor] in
            close(descriptor)
        }
        settingsFileObserver = source
        source.resume()
    }

    private func reloadSettingsFileFromDiskIfNeeded() {
        guard let settingsFileURL,
              let data = try? Data(contentsOf: settingsFileURL),
              data != lastPersistedSettingsFileData else {
            return
        }

        applySettingsFileData(data)
        NotificationCenter.default.post(name: Self.didChangeNotification, object: self)
    }
}
