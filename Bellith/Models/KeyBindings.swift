import AppKit

// MARK: - Keybinding Definition

struct KeyShortcut: Codable, Equatable {
    var key: String        // character, e.g. "t", "]", "d"
    var command: Bool
    var shift: Bool
    var option: Bool
    var control: Bool

    var displayString: String {
        var parts: [String] = []
        if control { parts.append("⌃") }
        if option { parts.append("⌥") }
        if shift { parts.append("⇧") }
        if command { parts.append("⌘") }
        parts.append(key.count == 1 ? key.uppercased() : key)
        return parts.joined()
    }

    /// Returns individual keycap strings for rendering as separate key badges.
    var keycapStrings: [String] {
        var caps: [String] = []
        if control { caps.append("⌃") }
        if option { caps.append("⌥") }
        if shift { caps.append("⇧") }
        if command { caps.append("⌘") }
        caps.append(key.count == 1 ? key.uppercased() : key)
        return caps
    }

    var modifierFlags: NSEvent.ModifierFlags {
        var flags: NSEvent.ModifierFlags = []
        if command { flags.insert(.command) }
        if shift { flags.insert(.shift) }
        if option { flags.insert(.option) }
        if control { flags.insert(.control) }
        return flags
    }

    static func from(event: NSEvent) -> KeyShortcut? {
        let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let key = event.charactersIgnoringModifiers ?? ""
        guard !key.isEmpty else { return nil }
        return KeyShortcut(
            key: key, command: mods.contains(.command), shift: mods.contains(.shift),
            option: mods.contains(.option), control: mods.contains(.control)
        )
    }
}

struct KeyBindingEntry: Codable {
    let id: String
    let label: String
    let category: String
    var shortcut: KeyShortcut
}
