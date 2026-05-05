import Foundation

extension BellithSettings {
    // Keybindings
    var keybindings: [KeyBindingEntry] {
        get {
            let visibleDefaults = activeDefaultKeybindings
            if let data = defaults.data(forKey: "keybindings"),
               let decoded = try? JSONDecoder().decode([KeyBindingEntry].self, from: data) {
                let map = Dictionary(uniqueKeysWithValues: decoded.map { ($0.id, $0) })
                return visibleDefaults.map { mergeBinding($0, persisted: map[$0.id]) }
            }
            return visibleDefaults
        }
        set {
            if let data = try? JSONEncoder().encode(newValue) {
                defaults.set(data, forKey: "keybindings")
            }
            notify()
        }
    }

    func shortcut(for actionId: String) -> KeyShortcut? {
        binding(for: actionId)?.primaryShortcut
    }

    func shortcuts(for actionId: String) -> [KeyShortcut] {
        binding(for: actionId)?.allShortcuts ?? []
    }

    func shortcutSummary(for actionId: String) -> String? {
        guard let binding = binding(for: actionId), !binding.allShortcuts.isEmpty else { return nil }
        return binding.shortcutSummary
    }

    func binding(for actionId: String) -> KeyBindingEntry? {
        keybindings.first { $0.id == actionId }
    }

    func effectiveShortcutMap(for scope: ShortcutScope? = nil) -> [String: [KeyShortcut]] {
        keybindings.reduce(into: [String: [KeyShortcut]]()) { map, binding in
            guard scope == nil || binding.scope == scope else { return }
            map[binding.id] = binding.allShortcuts
        }
    }

    func conflicts() -> [ShortcutConflict] {
        let bindings = keybindings
        var groups: [KeyShortcut: [String]] = [:]

        for binding in bindings {
            for shortcut in binding.allShortcuts {
                groups[shortcut, default: []].append(binding.id)
            }
        }

        return groups
            .compactMap { shortcut, actionIDs in
                let uniqueActionIDs = Array(Set(actionIDs)).sorted()
                guard uniqueActionIDs.count > 1 else { return nil }
                return ShortcutConflict(shortcut: shortcut, actionIDs: uniqueActionIDs)
            }
            .sorted { $0.shortcut.displayString < $1.shortcut.displayString }
    }

    func reset(actionId: String) {
        guard let index = keybindings.firstIndex(where: { $0.id == actionId }),
              let defaultBinding = activeDefaultKeybindings.first(where: { $0.id == actionId }) else { return }
        var updated = keybindings
        updated[index] = defaultBinding
        keybindings = updated
    }

    func reset(category: String) {
        let defaultsByID = Dictionary(uniqueKeysWithValues: activeDefaultKeybindings.map { ($0.id, $0) })
        let updated = keybindings.map { binding in
            guard binding.category == category, let defaultBinding = defaultsByID[binding.id] else { return binding }
            return defaultBinding
        }
        keybindings = updated
    }

    func applyPreset(_ preset: ShortcutPresetID) {
        defaults.set(preset.rawValue, forKey: "shortcutPreset")
        keybindings = Self.defaultKeybindings(for: preset, legacyPaneSupport: legacyPaneSupport)
    }

    var activeDefaultKeybindings: [KeyBindingEntry] {
        Self.defaultKeybindings(for: shortcutPreset, legacyPaneSupport: legacyPaneSupport)
    }

    func mergeBinding(_ defaultBinding: KeyBindingEntry, persisted: KeyBindingEntry?) -> KeyBindingEntry {
        guard let persisted else { return defaultBinding }
        var merged = defaultBinding
        merged.primaryShortcut = persisted.primaryShortcut
        merged.alternateShortcuts = persisted.alternateShortcuts.filter {
            persisted.primaryShortcut == nil || $0 != persisted.primaryShortcut
        }
        merged.presetSource = persisted.presetSource
        return merged
    }

    static let defaultKeybindings: [KeyBindingEntry] = defaultKeybindings(for: .bellithHybrid, legacyPaneSupport: false)

    static func defaultKeybindings(
        for preset: ShortcutPresetID,
        legacyPaneSupport: Bool
    ) -> [KeyBindingEntry] {
        ShortcutDefinitionLibrary.bindings(for: preset, legacyPaneSupport: legacyPaneSupport)
    }

    static let legacyPaneActionIDs: Set<String> = [
        "splitRight",
        "splitDown",
        "closePane",
        "navLeft",
        "navDown",
        "navUp",
        "navRight",
        "resizeLeft",
        "resizeDown",
        "resizeUp",
        "resizeRight",
        "zoomPane",
        "equalizePanes",
        "broadcastInput",
    ]
}
