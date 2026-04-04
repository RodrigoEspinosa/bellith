import Foundation
import os

/// Structured logging using Apple's `os.Logger`.
/// Zero-cost when not observed — messages are lazily interpolated.
/// View in Console.app with subsystem filter "com.rec.bellith".
extension Logger {
    private static let subsystem = Bundle.main.bundleIdentifier ?? "com.rec.bellith"

    /// Application lifecycle, window management, menus.
    static let app = Logger(subsystem: subsystem, category: "app")

    /// Configuration file generation, settings, keybinding decode.
    static let config = Logger(subsystem: subsystem, category: "config")

    /// Terminal surface creation, focus, rendering.
    static let surface = Logger(subsystem: subsystem, category: "surface")

    /// Theme loading, changes, custom theme import.
    static let theme = Logger(subsystem: subsystem, category: "theme")

    /// ProcessMonitor, NetworkMonitor — libproc interactions.
    static let monitor = Logger(subsystem: subsystem, category: "monitor")

    /// UI events, tab/pane operations, search, command palette.
    static let ui = Logger(subsystem: subsystem, category: "ui")
}
