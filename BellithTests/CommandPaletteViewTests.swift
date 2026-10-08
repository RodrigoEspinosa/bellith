import XCTest
@testable import Bellith

final class CommandPaletteViewTests: XCTestCase {
    func testFuzzyScorePrefersConsecutiveMatches() {
        XCTAssertNotNil(CommandPaletteView.fuzzyScore(query: "np", target: "New Pane"))
        XCTAssertNil(CommandPaletteView.fuzzyScore(query: "zz", target: "New Pane"))
    }

    func testFilteredCommandsReturnsPrefixForEmptyQuery() {
        let commands: [CommandPaletteView.CommandItem] = [
            (id: "newTab", label: "New Tab", description: "Open a new terminal tab", icon: "plus.square", shortcutId: nil),
            (id: "nextTerminal", label: "Next Terminal", description: "Move to the next terminal", icon: "arrow.right", shortcutId: nil),
            (id: "reloadConfig", label: "Reload Config", description: "Reload terminal configuration", icon: "arrow.clockwise", shortcutId: nil),
        ]

        let filtered = CommandPaletteView.filteredCommands(for: "", limit: 2, commands: commands)

        XCTAssertEqual(filtered.map(\.id), ["newTab", "nextTerminal"])
    }

    func testFilteredCommandsPrefersLabelMatchesOverIDMatches() {
        let commands: [CommandPaletteView.CommandItem] = [
            (id: "new-pane", label: "Preferences", description: "ID match only", icon: "slider.horizontal.3", shortcutId: nil),
            (id: "pane-manager", label: "New Pane", description: "Label match should rank first", icon: "plus.square", shortcutId: nil),
        ]

        let filtered = CommandPaletteView.filteredCommands(for: "new", limit: 3, commands: commands)

        XCTAssertEqual(filtered.first?.id, "pane-manager")
    }

    func testFilteredCommandsReturnsNoResultsForUnmatchedQuery() {
        let commands: [CommandPaletteView.CommandItem] = [
            (id: "newTab", label: "New Tab", description: "Open a new terminal tab", icon: "plus.square", shortcutId: nil),
            (id: "nextTerminal", label: "Next Terminal", description: "Move to the next terminal", icon: "arrow.right", shortcutId: nil),
            (id: "reloadConfig", label: "Reload Config", description: "Reload terminal configuration", icon: "arrow.clockwise", shortcutId: nil),
        ]

        let filtered = CommandPaletteView.filteredCommands(for: "zzzz-unmatched", limit: 3, commands: commands)

        XCTAssertTrue(filtered.isEmpty)
    }
}

@MainActor
final class UIChromeCleanupTests: XCTestCase {
    func testToggleExposesStateAndAccessibleAction() {
        var received: Bool?
        let toggle = PrefToggle(label: "Restore session", isOn: false) { received = $0 }
        XCTAssertEqual(toggle.accessibilityLabel(), "Restore session")
        XCTAssertEqual(toggle.accessibilityValue() as? Int, 0)
        XCTAssertTrue(toggle.accessibilityPerformPress())
        XCTAssertEqual(received, true)
        XCTAssertEqual(toggle.accessibilityValue() as? Int, 1)
    }

    func testOpacityAccessibleActionsRespectBounds() {
        var received = 0.0
        let track = OpacityTrackView(value: 1) { received = $0 }
        XCTAssertTrue(track.accessibilityPerformIncrement())
        XCTAssertEqual(received, 1)
        track.setValue(0.3)
        XCTAssertTrue(track.accessibilityPerformDecrement())
        XCTAssertEqual(received, 0.3)
    }

    func testResetDefaultsCanBeActivatedWithoutMouse() {
        var pressed = false
        let button = ResetDefaultsButton()
        button.onClick = { pressed = true }
        XCTAssertTrue(button.acceptsFirstResponder)
        XCTAssertTrue(button.accessibilityPerformPress())
        XCTAssertTrue(pressed)
    }

    func testWorkspaceCardsAndAddTileExposeAccessibleActions() {
        let rail = RebrandWorkspaceRail(frame: NSRect(x: 0, y: 0, width: 72, height: 400))
        let id = UUID()
        rail.workspaces = [.init(id: id, title: "Music", paneCount: 1, hotkeyDigit: 1)]
        rail.layout()
        let scroll = rail.subviews.compactMap { $0 as? NSScrollView }.first!
        let card = scroll.documentView!.subviews.compactMap { $0 as? RebrandWorkspaceCard }.first!
        var selected: UUID?
        rail.onSelect = { selected = $0 }
        XCTAssertEqual(card.accessibilityLabel(), "Music")
        XCTAssertTrue(card.accessibilityPerformPress())
        XCTAssertEqual(selected, id)
        var added = false
        rail.onAdd = { added = true }
        let add = rail.subviews.compactMap { $0 as? RebrandAddTile }.first!
        XCTAssertTrue(add.accessibilityPerformPress())
        XCTAssertTrue(added)
    }

    func testSearchClearingDisablesNavigationAndFitsNarrowPane() {
        let search = SearchBarView(frame: NSRect(x: 0, y: 0, width: 280, height: 36))
        search.setQuery("missing")
        search.updateCount(selected: 0, total: 0)
        let nav = search.subviews.compactMap { $0 as? NSButton }.filter { $0.image != nil }
        XCTAssertTrue(nav.allSatisfy { !$0.isEnabled })
        search.updateCount(selected: 1, total: 3)
        XCTAssertTrue(nav.allSatisfy(\.isEnabled))
        search.setQuery("")
        search.layout()
        XCTAssertTrue(nav.allSatisfy { !$0.isEnabled })
        let input = search.subviews.compactMap { $0 as? NSTextField }.first { $0.isEditable }!
        XCTAssertLessThanOrEqual(input.frame.maxX, search.subviews.compactMap { $0 as? NSButton }.map(\.frame.minX).min()!)
    }

    func testLongTitleDoesNotOverlapStudioButton() {
        let title = RebrandTitleBar(frame: NSRect(x: 0, y: 0, width: 360, height: 44))
        title.workspaceName = String(repeating: "workspace", count: 20)
        title.muxLabel = String(repeating: "multiplexer", count: 10)
        title.paneCount = 12
        title.layout()
        let button = title.subviews.compactMap { $0 as? NSButton }.first!
        let label = title.subviews.compactMap { $0 as? NSTextField }.first!
        XCTAssertLessThanOrEqual(label.frame.maxX, button.frame.minX - 12)
        let pill = title.subviews.compactMap { $0 as? RebrandPaneCountPill }.first!
        XCTAssertEqual(pill.frame.width, 0)
    }

    func testWorkspaceOverflowStaysAboveFooterAndSelectedCardIsVisible() {
        let rail = RebrandWorkspaceRail(frame: NSRect(x: 0, y: 0, width: 72, height: 400))
        let items = (0..<20).map { RebrandWorkspaceRail.Workspace(id: UUID(), title: "Workspace \($0)", paneCount: 1, hotkeyDigit: nil) }
        rail.workspaces = items
        rail.selectedID = items.last!.id
        rail.layout()
        let scroll = rail.subviews.compactMap { $0 as? NSScrollView }.first!
        let footer = rail.subviews.compactMap { $0 as? RebrandAddTile }.first!
        XCTAssertGreaterThan(scroll.frame.minY, footer.frame.maxY)
        let document = scroll.documentView!
        XCTAssertGreaterThan(document.frame.height, scroll.frame.height)
        let selected = document.subviews.compactMap { $0 as? RebrandWorkspaceCard }.first { $0.workspaceID == items.last!.id }!
        XCTAssertTrue(document.visibleRect.intersects(selected.frame))
    }
}
