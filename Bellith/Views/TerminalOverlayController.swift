import AppKit
import GhosttyKit

struct ShortcutTabHint {
    let shortcutDigit: Int
    let title: String
    let isSelected: Bool
}

protocol TerminalOverlayControllerHost: AnyObject {
    var overlayContainerView: NSView { get }
    var overlayWindow: NSWindow? { get }
    var activeSurfaceForOverlay: TerminalSurfaceView? { get }
    var terminalTabHintsForOverlay: [ShortcutTabHint] { get }
    func performCommandPaletteCommand(_ text: String)
}

final class TerminalOverlayController {
    private enum Metrics {
        static let modifierHintDelay: TimeInterval = 0.22
    }

    weak var host: TerminalOverlayControllerHost?
    private let commandRegistry: CommandRegistry
    private let settings: BellithSettings

    private(set) var isPaletteVisible = false
    private(set) var isSearchVisible = false
    private(set) var isShortcutCheatSheetVisible = false
    private var searchTotal = 0
    private var commandPalette: CommandPaletteView?
    private var searchBar: SearchBarView?
    private var shortcutCheatSheet: ShortcutCheatSheetView?
    private var modifierHintOverlay: ModifierShortcutHintsView?
    private var pendingModifierHintWorkItem: DispatchWorkItem?
    private var pendingModifierFlags: NSEvent.ModifierFlags = []

    init(
        host: TerminalOverlayControllerHost,
        commandRegistry: CommandRegistry = .shared,
        settings: BellithSettings = .shared
    ) {
        self.host = host
        self.commandRegistry = commandRegistry
        self.settings = settings
    }

    var presentedOverlayView: NSView? {
        commandPalette ?? searchBar ?? shortcutCheatSheet
    }

    func refreshTheme() {
        commandPalette?.refreshTheme()
        searchBar?.refreshTheme()
        shortcutCheatSheet?.refreshTheme()
        modifierHintOverlay?.refreshTheme()
    }

    func toggleCommandPalette() {
        if isPaletteVisible {
            hideCommandPalette()
        } else {
            showCommandPalette()
        }
    }

    func showCommandPalette() {
        guard !isPaletteVisible, let host else { return }
        hideModifierHints()
        hideShortcutCheatSheet()
        isPaletteVisible = true

        let palette = CommandPaletteView(commandRegistry: commandRegistry, settings: settings)
        palette.onSubmit = { [weak self] text in
            self?.host?.performCommandPaletteCommand(text)
        }
        palette.onDismiss = { [weak self] in
            guard let self else { return }
            self.isPaletteVisible = false
            self.commandPalette = nil
            self.host?.overlayWindow?.makeFirstResponder(self.host?.activeSurfaceForOverlay)
        }

        commandPalette = palette
        palette.show(in: host.overlayContainerView)
        (host.overlayWindow as? TerminalWindow)?.showTrafficLights()
    }

    func hideCommandPalette() {
        commandPalette?.hide()
    }

    func toggleShortcutCheatSheet() {
        if isShortcutCheatSheetVisible {
            hideShortcutCheatSheet()
        } else {
            showShortcutCheatSheet()
        }
    }

    func showShortcutCheatSheet() {
        guard !isShortcutCheatSheetVisible, let host else { return }
        hideModifierHints()
        isShortcutCheatSheetVisible = true

        let view = ShortcutCheatSheetView(settings: settings)
        view.onDismiss = { [weak self] in
            guard let self else { return }
            self.isShortcutCheatSheetVisible = false
            self.shortcutCheatSheet = nil
            self.host?.overlayWindow?.makeFirstResponder(self.host?.activeSurfaceForOverlay)
        }
        view.setContext(searchVisible: isSearchVisible, paletteVisible: isPaletteVisible)

        shortcutCheatSheet = view
        view.show(in: host.overlayContainerView)
        host.overlayWindow?.makeFirstResponder(view)
    }

    func hideShortcutCheatSheet() {
        guard isShortcutCheatSheetVisible else { return }
        shortcutCheatSheet?.hide()
    }

    func showSearch(initialNeedle: String? = nil) {
        guard !isSearchVisible, let host else { return }
        hideModifierHints()
        hideShortcutCheatSheet()
        isSearchVisible = true

        let bar = SearchBarView()
        bar.onSearch = { [weak self] query in
            self?.performSearch(query)
        }
        bar.onNext = { [weak self] in
            self?.searchNext()
        }
        bar.onPrev = { [weak self] in
            self?.searchPrev()
        }
        bar.onDismiss = { [weak self] in
            guard let self else { return }
            self.isSearchVisible = false
            self.searchBar = nil
            self.closeSurfaceSearch()
            self.host?.overlayWindow?.makeFirstResponder(self.host?.activeSurfaceForOverlay)
        }

        searchBar = bar
        if let needle = initialNeedle {
            bar.setQuery(needle)
        }
        bar.show(in: host.overlayContainerView)
    }

    func hideSearch() {
        guard isSearchVisible else { return }
        searchBar?.hide()
    }

    func updateSearchTotal(_ total: Int) {
        searchTotal = total
        searchBar?.updateCount(selected: 0, total: total)
    }

    func updateSearchSelected(_ selected: Int) {
        searchBar?.updateCount(selected: selected, total: searchTotal)
    }

    func searchNextShortcut() {
        guard isSearchVisible else { return }
        searchNext()
    }

    func searchPrevShortcut() {
        guard isSearchVisible else { return }
        searchPrev()
    }

    func handleModifierFlagsChanged(_ flags: NSEvent.ModifierFlags) {
        let normalizedFlags = normalizedModifierFlags(flags)
        pendingModifierFlags = normalizedFlags

        guard settings.showModifierHints else {
            cancelPendingModifierHints()
            hideModifierHints()
            return
        }

        guard !isPaletteVisible, !isSearchVisible, !isShortcutCheatSheetVisible else {
            cancelPendingModifierHints()
            hideModifierHints()
            return
        }

        guard !normalizedFlags.isEmpty else {
            cancelPendingModifierHints()
            hideModifierHints()
            return
        }

        if modifierHintOverlay?.superview != nil {
            showModifierHints(for: normalizedFlags)
            return
        }

        cancelPendingModifierHints()
        let workItem = DispatchWorkItem { [weak self] in
            guard let self, self.pendingModifierFlags == normalizedFlags else { return }
            self.showModifierHints(for: normalizedFlags)
        }
        pendingModifierHintWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + Metrics.modifierHintDelay, execute: workItem)
    }

    func handleKeyEventBegan() {
        cancelPendingModifierHints()
        hideModifierHints()
    }

    func hideModifierHints() {
        cancelPendingModifierHints()
        modifierHintOverlay?.hide()
    }

    private func showModifierHints(for flags: NSEvent.ModifierFlags) {
        guard let host else { return }

        let tabHints = flags == [.command] ? host.terminalTabHintsForOverlay : []
        let sections = modifierHintSections(for: flags, tabHints: tabHints)
        guard !sections.isEmpty else {
            hideModifierHints()
            return
        }

        let title = "\(displayModifierString(for: flags)) shortcuts"
        let subtitle: String
        if flags == [.command], !tabHints.isEmpty {
            subtitle = "Release modifiers to dismiss · ⌘1–9 always follows terminal tabs, never tools"
        } else {
            subtitle = "Release modifiers to dismiss"
        }

        let view = modifierHintOverlay ?? ModifierShortcutHintsView()
        view.update(title: title, subtitle: subtitle, sections: sections)
        if modifierHintOverlay == nil {
            modifierHintOverlay = view
        }
        view.show(in: host.overlayContainerView)
    }

    private func modifierHintSections(
        for flags: NSEvent.ModifierFlags,
        tabHints: [ShortcutTabHint]
    ) -> [ModifierShortcutHintsView.Section] {
        var sections: [ModifierShortcutHintsView.Section] = []

        if flags == [.command], !tabHints.isEmpty {
            sections.append(
                ModifierShortcutHintsView.Section(
                    title: "Terminal Tabs",
                    items: tabHints.map {
                        ModifierShortcutHintsView.Item(
                            key: "\($0.shortcutDigit)",
                            label: $0.title,
                            detail: $0.isSelected ? "Current terminal tab" : "Jump to this tab",
                            isSelected: $0.isSelected
                        )
                    }
                )
            )
        }

        let matchingBindings = settings.keybindings.compactMap { binding -> (String, ModifierShortcutHintsView.Item)? in
            let shortcuts = binding.allShortcuts.filter { normalizedModifierFlags($0.modifierFlags) == flags }
            guard !shortcuts.isEmpty else { return nil }

            let keys = shortcuts
                .map { KeyShortcut.displayKey(for: $0.normalizedKey) }
                .reduce(into: [String]()) { orderedKeys, key in
                    if !orderedKeys.contains(key) {
                        orderedKeys.append(key)
                    }
                }
                .joined(separator: " · ")

            return (
                binding.category,
                ModifierShortcutHintsView.Item(
                    key: keys,
                    label: binding.label,
                    detail: binding.discoverabilityText,
                    isSelected: false
                )
            )
        }

        let categoryOrder = settings.keybindings.map(\.category).reduce(into: [String]()) { order, category in
            if !order.contains(category) {
                order.append(category)
            }
        }

        for category in categoryOrder {
            let items = matchingBindings.compactMap { bindingCategory, item in
                bindingCategory == category ? item : nil
            }
            if !items.isEmpty {
                sections.append(ModifierShortcutHintsView.Section(title: category, items: items))
            }
        }

        return sections
    }

    private func normalizedModifierFlags(_ flags: NSEvent.ModifierFlags) -> NSEvent.ModifierFlags {
        flags.intersection([.command, .shift, .option, .control])
    }

    private func displayModifierString(for flags: NSEvent.ModifierFlags) -> String {
        var parts: [String] = []
        if flags.contains(.control) { parts.append("⌃") }
        if flags.contains(.option) { parts.append("⌥") }
        if flags.contains(.shift) { parts.append("⇧") }
        if flags.contains(.command) { parts.append("⌘") }
        return parts.joined()
    }

    private func cancelPendingModifierHints() {
        pendingModifierHintWorkItem?.cancel()
        pendingModifierHintWorkItem = nil
    }

    private func performSearch(_ query: String) {
        performSurfaceAction("search_forward:\(query)")
    }

    private func searchNext() {
        performSurfaceAction("search_forward")
    }

    private func searchPrev() {
        performSurfaceAction("search_backward")
    }

    private func closeSurfaceSearch() {
        performSurfaceAction("close_surface_search")
    }

    private func performSurfaceAction(_ action: String) {
        guard let surface = host?.activeSurfaceForOverlay?.surface else { return }
        _ = action.withCString { ptr in
            ghostty_surface_binding_action(surface, ptr, UInt(action.utf8.count))
        }
    }
}
