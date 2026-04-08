import Foundation
import GhosttyKit

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
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("com.rec.bellith", isDirectory: true)
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
            return nil
        }
    }
}
