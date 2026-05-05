import AppKit
import Darwin
import Foundation

extension BellithSettings {
    static func featureFlags(from object: [String: Any]) -> [String: Bool] {
        object.reduce(into: [String: Bool]()) { result, entry in
            guard let number = entry.value as? NSNumber else { return }
            result[entry.key] = number.boolValue
        }
    }

    var featureFlagsForSettingsFile: [String: Bool] {
        var flags = storedFeatureFlags
        for feature in BellithFeatureFlag.allCases {
            flags[feature.rawValue] = isFeatureEnabled(feature)
        }
        return flags
    }

    func loadSettingsFileIfNeeded() {
        guard let settingsFileURL,
              let data = try? Data(contentsOf: settingsFileURL) else {
            return
        }

        applySettingsFileData(data)
    }

    func applySettingsFileData(_ data: Data) {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return
        }

        PersistedKeys.all.forEach { defaults.removeObject(forKey: $0) }
        for (key, value) in object {
            applyPersistedValue(value, forKey: key)
        }
        lastPersistedSettingsFileData = data
    }

    func applyPersistedValue(_ value: Any, forKey key: String) {
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

        case PersistedKeys.terminalProfiles:
            guard JSONSerialization.isValidJSONObject(value),
                  let jsonData = try? JSONSerialization.data(withJSONObject: value),
                  let decoded = try? JSONDecoder().decode([TerminalProfile].self, from: jsonData),
                  let encoded = try? JSONEncoder().encode(decoded) else { return }
            defaults.set(encoded, forKey: key)

        case _ where PersistedKeys.stringArrayKeys.contains(key):
            guard let arrayValue = value as? [String] else { return }
            defaults.set(arrayValue, forKey: key)

        default:
            return
        }
    }

    func persistSettingsFileIfNeeded() {
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

    func settingsFileData() throws -> Data {
        let encodedKeybindings: Any
        do {
            let encoded = try JSONEncoder().encode(keybindings)
            encodedKeybindings = try JSONSerialization.jsonObject(with: encoded)
        } catch {
            encodedKeybindings = []
        }

        let encodedProfiles: Any
        do {
            let encoded = try JSONEncoder().encode(profiles)
            encodedProfiles = try JSONSerialization.jsonObject(with: encoded)
        } catch {
            encodedProfiles = []
        }

        let object: [String: Any] = [
            "activeTerminalProfileID": activeProfileID,
            "appearanceMode": appearanceMode.rawValue,
            "backgroundOpacity": roundedForSettingsFile(backgroundOpacity),
            "bellMode": bellMode,
            "commandCompletionNotificationThreshold": commandCompletionNotificationThreshold,
            "commandCompletionNotificationsEnabled": commandCompletionNotificationsEnabled,
            "errorFixSuggestionsEnabled": errorFixSuggestionsEnabled,
            "confirmClose": confirmClose,
            "cursorBlink": cursorBlink,
            "cursorStyle": cursorStyle,
            "darkThemeName": darkThemeName,
            "fontFamily": fontFamily,
            "fontLigaturesEnabled": fontLigaturesEnabled,
            "fontSize": fontSize,
            "featureFlags": featureFlagsForSettingsFile,
            "inlineImagesEnabled": inlineImagesEnabled,
            "keybindings": encodedKeybindings,
            "lightThemeName": lightThemeName,
            "mouseHideWhileTyping": mouseHideWhileTyping,
            "noiseIntensity": roundedForSettingsFile(noiseIntensity),
            "oledChromeForDarkThemes": oledChromeForDarkThemes,
            "wallpaperTint": wallpaperTint,
            "restoreSession": restoreSession,
            "scrollbackLines": scrollbackLines,
            "scrollbackMinimapEnabled": scrollbackMinimapEnabled,
            "shell": shell,
            "legacyPaneSupport": legacyPaneSupport,
            "localSessionBootstrap": localSessionBootstrap.rawValue,
            "shellIntegrationCursor": shellIntegrationCursor,
            "shellIntegrationEnabled": shellIntegrationEnabled,
            "shellIntegrationPath": shellIntegrationPath,
            "shellIntegrationSSHEnv": shellIntegrationSSHEnv,
            "shellIntegrationSSHTerminfo": shellIntegrationSSHTerminfo,
            "shellIntegrationTitle": shellIntegrationTitle,
            "showModifierHints": showModifierHints,
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
            "terminalProfiles": encodedProfiles,
            "terminalOptionKeyBehavior": terminalOptionKeyBehavior.rawValue,
            "terminalTerm": terminalTerm,
            "trafficLightAutoHide": trafficLightAutoHide,
            "visorHeightPercent": roundedForSettingsFile(visorHeightPercent),
            "visorHideOnFocusLoss": visorHideOnFocusLoss,
            "visorPosition": visorPosition,
            "visorWidthPercent": roundedForSettingsFile(visorWidthPercent),
            "windowPaddingX": windowPaddingX,
            "windowPaddingY": windowPaddingY,
            "workingDirectory": workingDirectory,
        ]

        return try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
    }

    func roundedForSettingsFile(_ value: Double) -> Double {
        (value * 100).rounded() / 100
    }

    func startObservingSettingsFileIfNeeded() {
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

    func reloadSettingsFileFromDiskIfNeeded() {
        guard let settingsFileURL,
              let data = try? Data(contentsOf: settingsFileURL),
              data != lastPersistedSettingsFileData else {
            return
        }

        applySettingsFileData(data)
        NotificationCenter.default.post(name: Self.didChangeNotification, object: self)
    }
}
