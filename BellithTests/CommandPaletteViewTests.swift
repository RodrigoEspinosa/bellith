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
