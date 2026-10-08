import AppKit
import Foundation

extension TerminalContainerView {
    /// Lightweight projection of the active tabs for the rebrand shell. Kept
    /// flat / immutable so consumers can't mutate internal state.
    struct EmbeddedTabSummary {
        let id: UUID
        let title: String
        let paneCount: Int
        let isSmart: Bool
        let sourceIndex: Int
    }

    struct EmbeddedStatusSummary {
        let muxName: String?
        let paneCount: Int
        let focusedPaneIndex: Int
        let cwdDisplay: String?
        let gitBranch: String?
        let processDisplay: String?
        let isBroadcasting: Bool
    }

    static func rebrandDisplayTitle(for entry: TerminalTabEntry) -> String {
        let trimmedTitle = entry.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedTitle.isEmpty, !isGenericShellTitle(trimmedTitle) {
            return trimmedTitle
        }

        let cwd = entry.focusedSurface?.currentCwd ?? entry.cwd
        if let cwd, let name = rebrandWorkspaceName(from: cwd) {
            return name
        }
        return trimmedTitle.isEmpty ? "session" : trimmedTitle
    }

    static func rebrandWorkspaceName(from cwd: String) -> String? {
        let trimmed = cwd.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if trimmed == NSHomeDirectory() || trimmed == "~" { return "~" }
        let normalized = trimmed.hasPrefix("~") ? NSString(string: trimmed).expandingTildeInPath : trimmed
        let lastComponent = URL(fileURLWithPath: normalized).lastPathComponent
        return lastComponent.isEmpty ? nil : lastComponent
    }

    static func isGenericShellTitle(_ title: String) -> Bool {
        let normalized = title.lowercased()
        return ["zsh", "bash", "fish", "sh", "shell", "terminal"].contains(normalized)
    }

    static func compactPath(_ path: String?) -> String? {
        guard let path, !path.isEmpty else { return nil }
        let home = NSHomeDirectory()
        let normalized: String
        if path.hasPrefix(home) {
            normalized = "~" + path.dropFirst(home.count)
        } else {
            normalized = path
        }
        let pieces = normalized.split(separator: "/", omittingEmptySubsequences: false)
        guard pieces.count > 3 else { return String(normalized) }
        return pieces.suffix(3).joined(separator: "/")
    }

    /// Compact pane title for the header — first word of the foreground process,
    /// falling back to "zsh" so the header always has a label.
    static func paneHeaderTitle(from presentation: ForegroundProcessPresentation?) -> String {
        guard let presentation else { return "zsh" }
        let firstSegment = presentation.text.split(separator: " ").first.map(String.init) ?? presentation.text
        return firstSegment.isEmpty ? "zsh" : firstSegment
    }

    /// A pane is "running" (warning-tinted dot) whenever a non-shell foreground
    /// process is present — matches the design's distinction between idle shells
    /// and active long-runners (dev servers, watchers, REPLs).
    static func paneHeaderIsRunning(from presentation: ForegroundProcessPresentation?) -> Bool {
        guard let presentation else { return false }
        let lower = presentation.text.lowercased()
        let shellNames = ["zsh", "bash", "fish", "sh", "dash", "ksh"]
        return !shellNames.contains(where: { lower == $0 || lower.hasPrefix("\($0) ") })
    }

    static func editorCommand(for fileURL: URL) -> String {
        let escapedPath = shellQuoted(fileURL.path)
        return """
        if [ -n "${EDITOR:-}" ]; then
          eval "$EDITOR \(escapedPath)"
        elif [ -n "${VISUAL:-}" ]; then
          eval "$VISUAL \(escapedPath)"
        else
          open -t \(escapedPath)
        fi
        """
    }

    static func shellQuoted(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "'\\''"))'"
    }

    static func matchesShortcut(
        _ event: NSEvent,
        key: String,
        command: Bool = false,
        shift: Bool = false,
        option: Bool = false,
        control: Bool = false
    ) -> Bool {
        let shortcut = KeyShortcut(key: key, command: command, shift: shift, option: option, control: control)
        return shortcut.matches(event: event)
    }
}
