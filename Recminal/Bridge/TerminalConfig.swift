import Foundation
import GhosttyKit

/// Wraps ghostty_config_t with automatic lifecycle management.
final class TerminalConfig {
    private(set) var config: ghostty_config_t?

    init() {
        config = ghostty_config_new()
        guard config != nil else { return }

        // Load ONLY our config — not user's ghostty config.
        // This gives us full control over the appearance.
        let configPath = Self.writeConfigFile()
        if let path = configPath {
            path.withCString { ghostty_config_load_file(config, $0) }
        }

        ghostty_config_finalize(config)
    }

    /// Clone an existing config (e.g. for a new surface with overrides).
    init(cloning other: TerminalConfig) {
        guard let src = other.config else {
            config = nil
            return
        }
        config = ghostty_config_clone(src)
    }

    deinit {
        if let config { ghostty_config_free(config) }
    }

    func get<T>(_ key: String, _ out: UnsafeMutablePointer<T>) -> Bool {
        guard let config else { return false }
        return key.withCString { cKey in
            ghostty_config_get(config, out, cKey, UInt(MemoryLayout<T>.size))
        }
    }

    /// Write the full Recminal config file.
    private static func writeConfigFile() -> String? {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("recminal", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let file = dir.appendingPathComponent("config.conf")
        let content = [
            "font-family = Hack Nerd Font Mono",
            "font-size = 15",
            "theme = tokyonight",
            "background-opacity = 1.0",
            "window-padding-x = 10",
            "window-padding-y = 38,2",
            "window-padding-balance = false",
            "cursor-style = block",
            "cursor-style-blink = false",
            "shell-integration-features = no-cursor",
            "window-decoration = false",
            "window-save-state = never",
            "mouse-hide-while-typing = true",
            "confirm-close-surface = false",
        ].joined(separator: "\n")

        do {
            try content.write(to: file, atomically: true, encoding: .utf8)
            return file.path
        } catch {
            return nil
        }
    }
}
