import Foundation
import GhosttyKit

// MARK: - Ghostty Config Wrapper

enum TerminalConfigError: LocalizedError {
    case failedToCreateGhosttyConfig
    case configurationDirectoryUnavailable
    case failedToCreateConfigDirectory(URL, underlying: Error)
    case failedToWriteConfigFile(URL, underlying: Error)
    case failedToWriteThemeFile(URL, underlying: Error)

    var errorDescription: String? {
        switch self {
        case .failedToCreateGhosttyConfig:
            return "Bellith could not initialize Ghostty's configuration."
        case .configurationDirectoryUnavailable:
            return "Bellith could not locate its configuration directory."
        case .failedToCreateConfigDirectory(let url, _):
            return "Bellith could not create its configuration directory at \(url.path)."
        case .failedToWriteConfigFile(let url, _):
            return "Bellith could not write its configuration file at \(url.path)."
        case .failedToWriteThemeFile(let url, _):
            return "Bellith could not write its generated theme file at \(url.path)."
        }
    }

    var failureReason: String? {
        switch self {
        case .failedToCreateGhosttyConfig, .configurationDirectoryUnavailable:
            return nil
        case .failedToCreateConfigDirectory(_, let underlying),
             .failedToWriteConfigFile(_, let underlying),
             .failedToWriteThemeFile(_, let underlying):
            return underlying.localizedDescription
        }
    }
}

extension Notification.Name {
    static let terminalConfigDidFail = Notification.Name("TerminalConfigDidFail")
}

final class TerminalConfig {
    private enum Padding {
        static let minimumHorizontalInset = 4
        static let minimumTopInset = 8
    }
    private enum RuntimeConfig {
        static let generatedFileName = "generated.conf"
        static let generatedThemePrefix = "ghostty-theme-"
        static let generatedThemeExtension = "theme"
        static let applicationSupportDirectoryName = "com.rec.bellith"
    }

    private enum macOSTerminalCompatibility {
        static let keybinds = [
            // Common shell/readline/zle word navigation and deletion shortcuts.
            "keybind = alt+left=esc:b",
            "keybind = alt+right=esc:f",
            "keybind = alt+backspace=text:\\x17",
            "keybind = alt+delete=esc:d",

            // Common macOS line editing expectations.
            "keybind = cmd+left=text:\\x01",
            "keybind = cmd+right=text:\\x05",
            "keybind = cmd+backspace=text:\\x15",
            "keybind = cmd+delete=text:\\x0b",
        ]
    }

    struct ConfigPaths: Equatable {
        let directory: URL
        let generatedConfigFile: URL
    }

    private(set) var config: ghostty_config_t?
    private(set) var configurationError: TerminalConfigError?

    init(configurationDirectory: URL? = nil) {
        config = ghostty_config_new()
        guard config != nil else {
            report(.failedToCreateGhosttyConfig)
            return
        }

        do {
            let generatedConfigPath = try Self.writeConfigFile(configurationDirectory: configurationDirectory)
            generatedConfigPath.withCString { ghostty_config_load_file(config, $0) }
        } catch let error as TerminalConfigError {
            report(error)
        } catch {
            report(.configurationDirectoryUnavailable)
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

    static func writeConfigFile(
        settings: BellithSettings = .shared,
        configurationDirectory: URL? = nil
    ) throws -> String {
        let paths = try configPaths(configurationDirectory: configurationDirectory)
        let dir = paths.directory

        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        } catch {
            throw TerminalConfigError.failedToCreateConfigDirectory(dir, underlying: error)
        }

        let s = settings
        let file = paths.generatedConfigFile
        let themeReference = try ghosttyThemeReference(for: s.resolvedTheme, in: dir)
        var lines = [
            "font-family = \(s.fontFamily)",
            "font-size = \(s.fontSize)",
            "theme = \(themeReference)",
            "term = \(s.effectiveTerminalTerm)",
            "background-opacity = \(s.backgroundOpacity)",
            "window-padding-x = \(Self.windowPaddingXValue(for: s))",
            "window-padding-y = \(Self.windowPaddingYValue(for: s))",
            "window-padding-balance = false",
            "cursor-style = \(s.cursorStyle)",
            "cursor-style-blink = \(s.cursorBlink)",
            "scrollback-limit = \(s.scrollbackLines)",
            "shell-integration = \(s.shellIntegrationMode)",
            "shell-integration-features = \(s.shellIntegrationFeatures)",
            "macos-option-as-alt = \(s.terminalOptionKeyBehavior.ghosttyConfigValue)",
            "window-decoration = false",
            "window-save-state = never",
            "mouse-hide-while-typing = \(s.mouseHideWhileTyping)",
            "link-url = true",
            "confirm-close-surface = \(s.confirmClose)",
            "keybind = clear",
        ]
        if !s.shell.isEmpty {
            lines.append("command = \(s.shell)")
        }
        if !s.inlineImagesEnabled {
            lines.append("image-storage-limit = 0")
        }
        lines.append(contentsOf: macOSTerminalCompatibility.keybinds)

        do {
            try lines.joined(separator: "\n").write(to: file, atomically: true, encoding: .utf8)
            return file.path
        } catch {
            throw TerminalConfigError.failedToWriteConfigFile(file, underlying: error)
        }
    }

    static func configPaths(
        configurationDirectory: URL? = nil,
        fileManager: FileManager = .default
    ) throws -> ConfigPaths {
        let directory: URL
        if let configurationDirectory {
            directory = configurationDirectory
        } else if let resolved = generatedConfigurationDirectory(fileManager: fileManager) {
            directory = resolved
        } else {
            throw TerminalConfigError.configurationDirectoryUnavailable
        }

        return ConfigPaths(
            directory: directory,
            generatedConfigFile: directory.appendingPathComponent(RuntimeConfig.generatedFileName)
        )
    }

    static func settingsConfigurationDirectory(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        fileManager: FileManager = .default
    ) -> URL? {
        if let xdgConfigHome = environment["XDG_CONFIG_HOME"]?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !xdgConfigHome.isEmpty {
            return URL(fileURLWithPath: NSString(string: xdgConfigHome).expandingTildeInPath, isDirectory: true)
                .appendingPathComponent("bellith", isDirectory: true)
        }

        let homeDirectory = fileManager.homeDirectoryForCurrentUser
        return homeDirectory
            .appendingPathComponent(".config", isDirectory: true)
            .appendingPathComponent("bellith", isDirectory: true)
    }

    static func runtimeConfigurationDirectory(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        fileManager: FileManager = .default
    ) -> URL? {
        settingsConfigurationDirectory(environment: environment, fileManager: fileManager)
    }

    static func generatedConfigurationDirectory(fileManager: FileManager = .default) -> URL? {
        fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent(RuntimeConfig.applicationSupportDirectoryName, isDirectory: true)
    }

    private static func ghosttyThemeReference(for theme: ThemeColors, in directory: URL) throws -> String {
        guard let definition = theme.ghosttyThemeDefinition else {
            return theme.ghosttyTheme
        }

        let file = directory
            .appendingPathComponent(RuntimeConfig.generatedThemePrefix + definition.fileStem)
            .appendingPathExtension(RuntimeConfig.generatedThemeExtension)

        do {
            try definition.contents.write(to: file, atomically: true, encoding: .utf8)
            return file.path
        } catch {
            throw TerminalConfigError.failedToWriteThemeFile(file, underlying: error)
        }
    }

    private static func windowPaddingXValue(for settings: BellithSettings) -> Int {
        max(Padding.minimumHorizontalInset, settings.windowPaddingX)
    }

    private static func windowPaddingYValue(for settings: BellithSettings) -> String {
        let bottomPadding = settings.windowPaddingY
        let topPadding = max(Padding.minimumTopInset, bottomPadding)
        return "\(topPadding),\(bottomPadding)"
    }

    private func report(_ error: TerminalConfigError) {
        configurationError = error
        NotificationCenter.default.post(name: .terminalConfigDidFail, object: error)
    }
}
