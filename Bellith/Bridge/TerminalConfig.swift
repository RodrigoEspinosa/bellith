import Foundation
import GhosttyKit

// MARK: - Ghostty Config Wrapper

enum TerminalConfigError: LocalizedError {
    case failedToCreateGhosttyConfig
    case applicationSupportDirectoryUnavailable
    case failedToCreateConfigDirectory(URL, underlying: Error)
    case failedToWriteConfigFile(URL, underlying: Error)

    var errorDescription: String? {
        switch self {
        case .failedToCreateGhosttyConfig:
            return "Bellith could not initialize Ghostty's configuration."
        case .applicationSupportDirectoryUnavailable:
            return "Bellith could not locate the Application Support directory."
        case .failedToCreateConfigDirectory(let url, _):
            return "Bellith could not create its configuration directory at \(url.path)."
        case .failedToWriteConfigFile(let url, _):
            return "Bellith could not write its configuration file at \(url.path)."
        }
    }

    var failureReason: String? {
        switch self {
        case .failedToCreateGhosttyConfig, .applicationSupportDirectoryUnavailable:
            return nil
        case .failedToCreateConfigDirectory(_, let underlying), .failedToWriteConfigFile(_, let underlying):
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

    private(set) var config: ghostty_config_t?
    private(set) var configurationError: TerminalConfigError?

    init(configurationDirectory: URL? = nil) {
        config = ghostty_config_new()
        guard config != nil else {
            report(.failedToCreateGhosttyConfig)
            return
        }

        do {
            let path = try Self.writeConfigFile(configurationDirectory: configurationDirectory)
            path.withCString { ghostty_config_load_file(config, $0) }
        } catch let error as TerminalConfigError {
            report(error)
        } catch {
            report(.applicationSupportDirectoryUnavailable)
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
        let defaultDirectory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        guard let dir = configurationDirectory ?? defaultDirectory?.appendingPathComponent("com.rec.bellith", isDirectory: true) else {
            throw TerminalConfigError.applicationSupportDirectoryUnavailable
        }

        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        } catch {
            throw TerminalConfigError.failedToCreateConfigDirectory(dir, underlying: error)
        }

        let s = settings
        let file = dir.appendingPathComponent("config.conf")
        var lines = [
            "font-family = \(s.fontFamily)",
            "font-size = \(s.fontSize)",
            "theme = \(s.resolvedTheme.ghosttyTheme)",
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

        do {
            try lines.joined(separator: "\n").write(to: file, atomically: true, encoding: .utf8)
            return file.path
        } catch {
            throw TerminalConfigError.failedToWriteConfigFile(file, underlying: error)
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
