import AppKit

enum ShortcutScope: String, Codable, CaseIterable {
    case globalApp
    case windowChrome
    case terminalFocused
    case modalOverlay

    var title: String {
        switch self {
        case .globalApp: "App"
        case .windowChrome: "Window"
        case .terminalFocused: "Terminal"
        case .modalOverlay: "Overlay"
        }
    }
}

enum ShortcutPresetID: String, Codable, CaseIterable {
    case bellithHybrid
    case macNative
    case vimNavigation

    var title: String {
        switch self {
        case .bellithHybrid: "Bellith Hybrid"
        case .macNative: "Mac Native"
        case .vimNavigation: "Vim Navigation"
        }
    }

    var subtitle: String {
        switch self {
        case .bellithHybrid: "Mac defaults with directional terminal navigation"
        case .macNative: "Mac-first shortcuts with minimal alternates"
        case .vimNavigation: "Vim-oriented pane movement with Mac basics preserved"
        }
    }
}

struct KeyShortcut: Codable, Equatable, Hashable {
    var key: String
    var command: Bool
    var shift: Bool
    var option: Bool
    var control: Bool

    private static let specialKeysByKeyCode: [UInt16: String] = [
        36: "return",
        48: "tab",
        49: "space",
        51: "delete",
        53: "escape",
        117: "forwardDelete",
        123: "leftArrow",
        124: "rightArrow",
        125: "downArrow",
        126: "upArrow",
    ]

    private static let displayKeys: [String: String] = [
        "leftArrow": "←",
        "rightArrow": "→",
        "upArrow": "↑",
        "downArrow": "↓",
        "return": "↩",
        "tab": "⇥",
        "space": "Space",
        "delete": "⌫",
        "forwardDelete": "⌦",
        "escape": "Esc",
    ]

    var normalizedKey: String { Self.normalize(key) }

    var displayString: String {
        var parts: [String] = []
        if control { parts.append("⌃") }
        if option { parts.append("⌥") }
        if shift { parts.append("⇧") }
        if command { parts.append("⌘") }
        parts.append(Self.displayKey(for: normalizedKey))
        return parts.joined()
    }

    var keycapStrings: [String] {
        var caps: [String] = []
        if control { caps.append("⌃") }
        if option { caps.append("⌥") }
        if shift { caps.append("⇧") }
        if command { caps.append("⌘") }
        caps.append(Self.displayKey(for: normalizedKey))
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

    var menuKeyEquivalent: String {
        switch normalizedKey {
        case "leftArrow":
            return String(Character(UnicodeScalar(NSLeftArrowFunctionKey)!))
        case "rightArrow":
            return String(Character(UnicodeScalar(NSRightArrowFunctionKey)!))
        case "upArrow":
            return String(Character(UnicodeScalar(NSUpArrowFunctionKey)!))
        case "downArrow":
            return String(Character(UnicodeScalar(NSDownArrowFunctionKey)!))
        case "return":
            return "\r"
        case "tab":
            return "\t"
        case "space":
            return " "
        case "delete":
            return String(Character(UnicodeScalar(NSDeleteCharacter)!))
        case "forwardDelete":
            return String(Character(UnicodeScalar(NSDeleteFunctionKey)!))
        case "escape":
            return "\u{1b}"
        default:
            return normalizedKey
        }
    }

    static func from(event: NSEvent) -> KeyShortcut? {
        let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard let key = canonicalKey(from: event) else { return nil }
        return KeyShortcut(
            key: key,
            command: mods.contains(.command),
            shift: mods.contains(.shift),
            option: mods.contains(.option),
            control: mods.contains(.control)
        )
    }

    func matches(event: NSEvent) -> Bool {
        let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard mods == modifierFlags,
              let eventKey = Self.canonicalKey(from: event) else { return false }
        return eventKey == normalizedKey
    }

    static func canonicalKey(from event: NSEvent) -> String? {
        if let special = specialKeysByKeyCode[event.keyCode] {
            return special
        }

        guard var key = event.charactersIgnoringModifiers, !key.isEmpty else { return nil }
        key = key.trimmingCharacters(in: .controlCharacters)
        guard !key.isEmpty else { return nil }
        return normalize(key)
    }

    static func normalize(_ rawKey: String) -> String {
        rawKey.count == 1 ? rawKey.lowercased() : rawKey
    }

    static func displayKey(for rawKey: String) -> String {
        if let display = displayKeys[rawKey] {
            return display
        }
        return rawKey.count == 1 ? rawKey.uppercased() : rawKey
    }
}

struct KeyBindingEntry: Codable {
    let id: String
    let label: String
    let category: String
    let scope: ShortcutScope
    let isReserved: Bool
    let discoverabilityText: String
    var primaryShortcut: KeyShortcut?
    var alternateShortcuts: [KeyShortcut]
    var presetSource: ShortcutPresetID

    init(
        id: String,
        label: String,
        category: String,
        scope: ShortcutScope,
        isReserved: Bool = true,
        discoverabilityText: String = "",
        primaryShortcut: KeyShortcut?,
        alternateShortcuts: [KeyShortcut] = [],
        presetSource: ShortcutPresetID = .bellithHybrid
    ) {
        self.id = id
        self.label = label
        self.category = category
        self.scope = scope
        self.isReserved = isReserved
        self.discoverabilityText = discoverabilityText
        self.primaryShortcut = primaryShortcut
        self.alternateShortcuts = Self.normalizedShortcutList(alternateShortcuts, excluding: primaryShortcut)
        self.presetSource = presetSource
    }

    var allShortcuts: [KeyShortcut] {
        Self.normalizedShortcutList(alternateShortcuts, excluding: primaryShortcut, prefixing: primaryShortcut)
    }

    var shortcutSummary: String {
        let summaries = allShortcuts.map(\.displayString)
        return summaries.joined(separator: "  ·  ")
    }

    func matches(event: NSEvent) -> Bool {
        allShortcuts.contains { $0.matches(event: event) }
    }

    mutating func setAlternateShortcut(_ shortcut: KeyShortcut?, at index: Int) {
        if let shortcut {
            if index < alternateShortcuts.count {
                alternateShortcuts[index] = shortcut
            } else if index == alternateShortcuts.count {
                alternateShortcuts.append(shortcut)
            }
        } else if index < alternateShortcuts.count {
            alternateShortcuts.remove(at: index)
        }
        alternateShortcuts = Self.normalizedShortcutList(alternateShortcuts, excluding: primaryShortcut)
    }

    private static func normalizedShortcutList(
        _ shortcuts: [KeyShortcut],
        excluding primary: KeyShortcut?,
        prefixing prefixedPrimary: KeyShortcut? = nil
    ) -> [KeyShortcut] {
        var seen: Set<KeyShortcut> = []
        var normalized: [KeyShortcut] = []

        if let prefixedPrimary {
            let primary = prefixedPrimary.withNormalizedKey
            seen.insert(primary)
            normalized.append(primary)
        }

        if let primary {
            seen.insert(primary.withNormalizedKey)
        }

        for shortcut in shortcuts {
            let normalizedShortcut = shortcut.withNormalizedKey
            if seen.insert(normalizedShortcut).inserted {
                normalized.append(normalizedShortcut)
            }
        }

        return normalized
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case label
        case category
        case scope
        case isReserved
        case discoverabilityText
        case primaryShortcut
        case alternateShortcuts
        case presetSource
        case shortcut
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let id = try container.decode(String.self, forKey: .id)
        let label = try container.decode(String.self, forKey: .label)
        let category = try container.decode(String.self, forKey: .category)
        let scope = try container.decodeIfPresent(ShortcutScope.self, forKey: .scope) ?? .windowChrome
        let isReserved = try container.decodeIfPresent(Bool.self, forKey: .isReserved) ?? true
        let discoverabilityText = try container.decodeIfPresent(String.self, forKey: .discoverabilityText) ?? ""
        let decodedPrimary = try container.decodeIfPresent(KeyShortcut.self, forKey: .primaryShortcut)
        let legacyPrimary = try container.decodeIfPresent(KeyShortcut.self, forKey: .shortcut)
        let primaryShortcut = decodedPrimary ?? legacyPrimary
        let alternateShortcuts = try container.decodeIfPresent([KeyShortcut].self, forKey: .alternateShortcuts) ?? []
        let presetSource = try container.decodeIfPresent(ShortcutPresetID.self, forKey: .presetSource) ?? .bellithHybrid

        self.init(
            id: id,
            label: label,
            category: category,
            scope: scope,
            isReserved: isReserved,
            discoverabilityText: discoverabilityText,
            primaryShortcut: primaryShortcut?.withNormalizedKey,
            alternateShortcuts: alternateShortcuts.map(\.withNormalizedKey),
            presetSource: presetSource
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(label, forKey: .label)
        try container.encode(category, forKey: .category)
        try container.encode(scope, forKey: .scope)
        try container.encode(isReserved, forKey: .isReserved)
        try container.encode(discoverabilityText, forKey: .discoverabilityText)
        try container.encodeIfPresent(primaryShortcut, forKey: .primaryShortcut)
        try container.encode(alternateShortcuts, forKey: .alternateShortcuts)
        try container.encode(presetSource, forKey: .presetSource)
    }
}

extension KeyShortcut {
    fileprivate var withNormalizedKey: KeyShortcut {
        KeyShortcut(
            key: normalizedKey,
            command: command,
            shift: shift,
            option: option,
            control: control
        )
    }
}

struct ShortcutConflict: Equatable {
    let shortcut: KeyShortcut
    let actionIDs: [String]
}
