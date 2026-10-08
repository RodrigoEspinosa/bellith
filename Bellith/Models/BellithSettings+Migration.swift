import Foundation

extension BellithSettings {
    enum WindowPaddingDefaults {
        static let migrationKey = "didMigrateWindowPaddingDefaults"
        static let legacyX = 10
        static let legacyY = 38
        static let current = 0
    }

    enum BuiltInSettingsWindowDefaults {
        static let migrationKey = "didMigrateBuiltInSettingsWindowDefault"
        static let legacyDefault = false
        static let currentDefault = true
    }

    func migrateBuiltInSettingsWindowDefaultIfNeeded() {
        guard !defaults.bool(forKey: BuiltInSettingsWindowDefaults.migrationKey) else { return }

        var flags = storedFeatureFlags
        let storedValue = flags[BellithFeatureFlag.builtInSettingsWindow.rawValue]
        defer { defaults.set(true, forKey: BuiltInSettingsWindowDefaults.migrationKey) }

        guard storedValue == nil || storedValue == BuiltInSettingsWindowDefaults.legacyDefault else {
            return
        }

        flags[BellithFeatureFlag.builtInSettingsWindow.rawValue] = BuiltInSettingsWindowDefaults.currentDefault
        defaults.set(flags, forKey: PersistedKeys.featureFlags)
    }

    func migrateLegacyWindowPaddingIfNeeded() {
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

    /// Pull the default profile's appearance fields (opacity/tint) back up into
    /// the global settings now that frame translucency and wallpaper tint are
    /// window-level. Runs once per install and only if the user had customized
    /// the default profile.
    func migrateLegacyProfileAppearanceToGlobalIfNeeded() {
        let list = profiles
        guard let defaultProfile = list.first(where: { $0.id == TerminalProfile.defaultID }) else {
            return
        }
        if let opacity = defaultProfile.legacyBackgroundOpacity,
           defaults.object(forKey: "backgroundOpacity") == nil {
            backgroundOpacity = opacity
        }
        if let tint = defaultProfile.legacyWallpaperTint,
           defaults.object(forKey: "wallpaperTint") == nil {
            wallpaperTint = tint
        }
    }
}
