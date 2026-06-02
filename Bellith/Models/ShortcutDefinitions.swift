import Foundation

enum ShortcutDefinitionLibrary {
    static func bindings(
        for preset: ShortcutPresetID,
        legacyPaneSupport: Bool
    ) -> [KeyBindingEntry] {
        var bindings = baseBindings(for: preset)

        if legacyPaneSupport {
            bindings.insert(contentsOf: paneBindings(for: preset), at: 5)
        }

        return bindings
    }

    private static func baseBindings(for preset: ShortcutPresetID) -> [KeyBindingEntry] {
        [
            KeyBindingEntry(
                id: "preferences",
                label: "Open Settings",
                category: "App",
                scope: .globalApp,
                discoverabilityText: "Open Bellith settings from anywhere",
                primaryShortcut: shortcut(",", command: true),
                presetSource: preset
            ),
            KeyBindingEntry(
                id: "showKeyboardShortcuts",
                label: "Show Keyboard Shortcuts",
                category: "App",
                scope: .windowChrome,
                discoverabilityText: "Open the contextual keyboard cheat sheet",
                primaryShortcut: shortcut("/", command: true, shift: true),
                presetSource: preset
            ),
            KeyBindingEntry(
                id: "newWindow",
                label: "New Window",
                category: "Window",
                scope: .globalApp,
                discoverabilityText: "Open a new terminal window",
                primaryShortcut: shortcut("n", command: true),
                presetSource: preset
            ),
            KeyBindingEntry(
                id: "toggleFullscreen",
                label: "Toggle Fullscreen",
                category: "Window",
                scope: .windowChrome,
                discoverabilityText: "Enter or exit full screen",
                primaryShortcut: shortcut("f", command: true, control: true),
                presetSource: preset
            ),
            KeyBindingEntry(
                id: "toggleSidebar",
                label: "Toggle Sidebar",
                category: "Window",
                scope: .windowChrome,
                discoverabilityText: "Show or hide the sidebar",
                primaryShortcut: shortcut("s", command: true, shift: true),
                presetSource: preset
            ),
            KeyBindingEntry(
                id: "newTab",
                label: "New Tab",
                category: "Tabs",
                scope: .windowChrome,
                discoverabilityText: "Open a new terminal tab",
                primaryShortcut: shortcut("t", command: true),
                presetSource: preset
            ),
            KeyBindingEntry(
                id: "closeTab",
                label: "Close Tab",
                category: "Tabs",
                scope: .windowChrome,
                discoverabilityText: "Close the selected tab",
                primaryShortcut: shortcut("w", command: true),
                presetSource: preset
            ),
            KeyBindingEntry(
                id: "nextTab",
                label: "Next Tab",
                category: "Tabs",
                scope: .windowChrome,
                discoverabilityText: "Move to the next tab",
                primaryShortcut: shortcut("]", command: true, shift: true),
                alternateShortcuts: preset == .macNative ? [] : [shortcut("rightArrow", command: true, option: true)],
                presetSource: preset
            ),
            KeyBindingEntry(
                id: "prevTab",
                label: "Previous Tab",
                category: "Tabs",
                scope: .windowChrome,
                discoverabilityText: "Move to the previous tab",
                primaryShortcut: shortcut("[", command: true, shift: true),
                alternateShortcuts: preset == .macNative ? [] : [shortcut("leftArrow", command: true, option: true)],
                presetSource: preset
            ),
            KeyBindingEntry(
                id: "reopenTab",
                label: "Reopen Closed Tab",
                category: "Tabs",
                scope: .windowChrome,
                discoverabilityText: "Restore the most recently closed tab",
                primaryShortcut: shortcut("t", command: true, shift: true),
                presetSource: preset
            ),
            KeyBindingEntry(
                id: "renameTab",
                label: "Rename Tab",
                category: "Tabs",
                scope: .windowChrome,
                discoverabilityText: "Rename the current tab",
                primaryShortcut: shortcut("e", command: true),
                presetSource: preset
            ),
            KeyBindingEntry(
                id: "commandPalette",
                label: "Command Palette",
                category: "Navigation",
                scope: .windowChrome,
                discoverabilityText: "Search commands, tools, and actions",
                primaryShortcut: shortcut("p", command: true, shift: true),
                presetSource: preset
            ),
            KeyBindingEntry(
                id: "copy",
                label: "Copy",
                category: "Edit",
                scope: .terminalFocused,
                discoverabilityText: "Copy the current selection",
                primaryShortcut: shortcut("c", command: true),
                presetSource: preset
            ),
            KeyBindingEntry(
                id: "paste",
                label: "Paste",
                category: "Edit",
                scope: .terminalFocused,
                discoverabilityText: "Paste from the clipboard",
                primaryShortcut: shortcut("v", command: true),
                presetSource: preset
            ),
            KeyBindingEntry(
                id: "selectAll",
                label: "Select All",
                category: "Edit",
                scope: .terminalFocused,
                discoverabilityText: "Select all visible text",
                primaryShortcut: shortcut("a", command: true),
                presetSource: preset
            ),
            KeyBindingEntry(
                id: "search",
                label: "Find",
                category: "Search",
                scope: .terminalFocused,
                discoverabilityText: "Open search in the current terminal",
                primaryShortcut: shortcut("f", command: true),
                presetSource: preset
            ),
            KeyBindingEntry(
                id: "searchNext",
                label: "Next Match",
                category: "Search",
                scope: .modalOverlay,
                discoverabilityText: "Jump to the next search result while search is open",
                primaryShortcut: shortcut("g", command: true),
                presetSource: preset
            ),
            KeyBindingEntry(
                id: "searchPrev",
                label: "Previous Match",
                category: "Search",
                scope: .modalOverlay,
                discoverabilityText: "Jump to the previous search result while search is open",
                primaryShortcut: shortcut("g", command: true, shift: true),
                presetSource: preset
            ),
            KeyBindingEntry(
                id: "dismissOverlay",
                label: "Dismiss Overlay",
                category: "Search",
                scope: .modalOverlay,
                isReserved: true,
                discoverabilityText: "Close the active overlay",
                primaryShortcut: shortcut("escape"),
                presetSource: preset
            ),
            KeyBindingEntry(
                id: "clearBuffer",
                label: "Clear Buffer",
                category: "Edit",
                scope: .terminalFocused,
                discoverabilityText: "Clear terminal output without closing the session",
                primaryShortcut: shortcut("k", command: true),
                presetSource: preset
            ),
            KeyBindingEntry(
                id: "reloadConfig",
                label: "Reload Config",
                category: "Terminal",
                scope: .windowChrome,
                discoverabilityText: "Reload the generated Ghostty configuration",
                primaryShortcut: shortcut("r", command: true, shift: true),
                presetSource: preset
            ),
            KeyBindingEntry(
                id: "fontSizeUp",
                label: "Increase Font Size",
                category: "View",
                scope: .windowChrome,
                discoverabilityText: "Increase terminal font size",
                primaryShortcut: shortcut("=", command: true),
                presetSource: preset
            ),
            KeyBindingEntry(
                id: "fontSizeDown",
                label: "Decrease Font Size",
                category: "View",
                scope: .windowChrome,
                discoverabilityText: "Decrease terminal font size",
                primaryShortcut: shortcut("-", command: true),
                presetSource: preset
            ),
            KeyBindingEntry(
                id: "fontSizeReset",
                label: "Reset Font Size",
                category: "View",
                scope: .windowChrome,
                discoverabilityText: "Reset the terminal font size to default",
                primaryShortcut: shortcut("0", command: true),
                presetSource: preset
            ),
        ]
    }

    private static func paneBindings(for preset: ShortcutPresetID) -> [KeyBindingEntry] {
        let primaryNavKeys: [String]
        let alternateNavKeys: [String]

        switch preset {
        case .bellithHybrid:
            primaryNavKeys = ["leftArrow", "downArrow", "upArrow", "rightArrow"]
            alternateNavKeys = ["h", "j", "k", "l"]
        case .macNative:
            primaryNavKeys = ["leftArrow", "downArrow", "upArrow", "rightArrow"]
            alternateNavKeys = []
        case .vimNavigation:
            primaryNavKeys = ["h", "j", "k", "l"]
            alternateNavKeys = ["leftArrow", "downArrow", "upArrow", "rightArrow"]
        }

        func navShortcut(_ key: String) -> KeyShortcut {
            shortcut(key, command: true, option: true)
        }

        func commandShiftArrowShortcut(_ key: String) -> KeyShortcut {
            shortcut(key, command: true, shift: true)
        }

        func navAlternates(for index: Int) -> [KeyShortcut] {
            var alternates = [commandShiftArrowShortcut(["leftArrow", "downArrow", "upArrow", "rightArrow"][index])]
            if !alternateNavKeys.isEmpty {
                alternates.append(navShortcut(alternateNavKeys[index]))
            }
            return alternates
        }

        func resizeShortcut(_ key: String) -> KeyShortcut {
            shortcut(key, command: true, option: true, control: true)
        }

        return [
            KeyBindingEntry(
                id: "splitRight",
                label: "Split Right",
                category: "Panes",
                scope: .windowChrome,
                discoverabilityText: "Split the active pane vertically",
                primaryShortcut: shortcut("d", command: true),
                alternateShortcuts: [shortcut("d", command: true, option: true)],
                presetSource: preset
            ),
            KeyBindingEntry(
                id: "splitDown",
                label: "Split Down",
                category: "Panes",
                scope: .windowChrome,
                discoverabilityText: "Split the active pane horizontally",
                primaryShortcut: shortcut("d", command: true, shift: true),
                alternateShortcuts: [shortcut("d", command: true, shift: true, option: true)],
                presetSource: preset
            ),
            KeyBindingEntry(
                id: "closePane",
                label: "Close Pane",
                category: "Panes",
                scope: .windowChrome,
                discoverabilityText: "Close the active pane",
                primaryShortcut: shortcut("w", command: true, option: true),
                presetSource: preset
            ),
            KeyBindingEntry(
                id: "navLeft",
                label: "Focus Left Pane",
                category: "Panes",
                scope: .windowChrome,
                discoverabilityText: "Move focus to the pane on the left",
                primaryShortcut: navShortcut(primaryNavKeys[0]),
                alternateShortcuts: navAlternates(for: 0),
                presetSource: preset
            ),
            KeyBindingEntry(
                id: "navDown",
                label: "Focus Down Pane",
                category: "Panes",
                scope: .windowChrome,
                discoverabilityText: "Move focus to the pane below",
                primaryShortcut: navShortcut(primaryNavKeys[1]),
                alternateShortcuts: navAlternates(for: 1),
                presetSource: preset
            ),
            KeyBindingEntry(
                id: "navUp",
                label: "Focus Up Pane",
                category: "Panes",
                scope: .windowChrome,
                discoverabilityText: "Move focus to the pane above",
                primaryShortcut: navShortcut(primaryNavKeys[2]),
                alternateShortcuts: navAlternates(for: 2),
                presetSource: preset
            ),
            KeyBindingEntry(
                id: "navRight",
                label: "Focus Right Pane",
                category: "Panes",
                scope: .windowChrome,
                discoverabilityText: "Move focus to the pane on the right",
                primaryShortcut: navShortcut(primaryNavKeys[3]),
                alternateShortcuts: navAlternates(for: 3),
                presetSource: preset
            ),
            KeyBindingEntry(
                id: "resizeLeft",
                label: "Resize Pane Left",
                category: "Panes",
                scope: .windowChrome,
                discoverabilityText: "Shrink or grow the pane boundary to the left",
                primaryShortcut: resizeShortcut(primaryNavKeys[0]),
                alternateShortcuts: alternateNavKeys.isEmpty ? [] : [resizeShortcut(alternateNavKeys[0])],
                presetSource: preset
            ),
            KeyBindingEntry(
                id: "resizeDown",
                label: "Resize Pane Down",
                category: "Panes",
                scope: .windowChrome,
                discoverabilityText: "Resize the pane boundary downward",
                primaryShortcut: resizeShortcut(primaryNavKeys[1]),
                alternateShortcuts: alternateNavKeys.isEmpty ? [] : [resizeShortcut(alternateNavKeys[1])],
                presetSource: preset
            ),
            KeyBindingEntry(
                id: "resizeUp",
                label: "Resize Pane Up",
                category: "Panes",
                scope: .windowChrome,
                discoverabilityText: "Resize the pane boundary upward",
                primaryShortcut: resizeShortcut(primaryNavKeys[2]),
                alternateShortcuts: alternateNavKeys.isEmpty ? [] : [resizeShortcut(alternateNavKeys[2])],
                presetSource: preset
            ),
            KeyBindingEntry(
                id: "resizeRight",
                label: "Resize Pane Right",
                category: "Panes",
                scope: .windowChrome,
                discoverabilityText: "Shrink or grow the pane boundary to the right",
                primaryShortcut: resizeShortcut(primaryNavKeys[3]),
                alternateShortcuts: alternateNavKeys.isEmpty ? [] : [resizeShortcut(alternateNavKeys[3])],
                presetSource: preset
            ),
            KeyBindingEntry(
                id: "zoomPane",
                label: "Zoom Pane",
                category: "Panes",
                scope: .windowChrome,
                discoverabilityText: "Temporarily maximize the active pane",
                primaryShortcut: shortcut("return", command: true, shift: true),
                presetSource: preset
            ),
            KeyBindingEntry(
                id: "equalizePanes",
                label: "Equalize Panes",
                category: "Panes",
                scope: .windowChrome,
                discoverabilityText: "Reset pane sizes evenly",
                primaryShortcut: shortcut("0", command: true, option: true),
                presetSource: preset
            ),
            KeyBindingEntry(
                id: "broadcastInput",
                label: "Broadcast Input",
                category: "Panes",
                scope: .windowChrome,
                discoverabilityText: "Send input to every pane in the current tab",
                primaryShortcut: shortcut("b", command: true, option: true),
                presetSource: preset
            ),
        ]
    }

    private static func shortcut(
        _ key: String,
        command: Bool = false,
        shift: Bool = false,
        option: Bool = false,
        control: Bool = false
    ) -> KeyShortcut {
        KeyShortcut(
            key: key,
            command: command,
            shift: shift,
            option: option,
            control: control
        )
    }
}
