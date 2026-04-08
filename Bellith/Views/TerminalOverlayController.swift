import AppKit
import GhosttyKit

protocol TerminalOverlayControllerHost: AnyObject {
    var overlayContainerView: NSView { get }
    var overlayWindow: NSWindow? { get }
    var activeSurfaceForOverlay: TerminalSurfaceView? { get }
    func performCommandPaletteCommand(_ text: String)
}

final class TerminalOverlayController {
    weak var host: TerminalOverlayControllerHost?
    private let commandRegistry: CommandRegistry
    private let settings: BellithSettings

    private(set) var isPaletteVisible = false
    private var isSearchVisible = false
    private var searchTotal = 0
    private var commandPalette: CommandPaletteView?
    private var searchBar: SearchBarView?

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
        commandPalette ?? searchBar
    }

    func refreshTheme() {
        commandPalette?.refreshTheme()
        searchBar?.refreshTheme()
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

    func showSearch(initialNeedle: String? = nil) {
        guard !isSearchVisible, let host else { return }
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
