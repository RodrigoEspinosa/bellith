import XCTest
@testable import Bellith

final class TerminalContainerViewTests: XCTestCase {
    func testShouldPollRuntimeStatusRequiresVisibleKeyWindow() {
        XCTAssertTrue(TerminalContainerView.shouldPollRuntimeStatus(windowIsVisible: true, isKeyWindow: true))
        XCTAssertFalse(TerminalContainerView.shouldPollRuntimeStatus(windowIsVisible: true, isKeyWindow: false))
        XCTAssertFalse(TerminalContainerView.shouldPollRuntimeStatus(windowIsVisible: false, isKeyWindow: true))
        XCTAssertFalse(TerminalContainerView.shouldPollRuntimeStatus(windowIsVisible: false, isKeyWindow: false))
    }

    func testShortcutSelectableTerminalTabIndicesSkipTools() {
        let indices = TerminalContainerView.shortcutSelectableTerminalTabIndices(
            for: [.smart("processes"), .terminal, .smart("network"), .terminal]
        )

        XCTAssertEqual(indices, [1, 3])
    }

    func testShortcutSelectableTerminalTabIndexClampsWithinTerminalTabs() {
        let tabKinds: [TerminalTabKind] = [.terminal, .smart("processes"), .terminal, .smart("network")]

        XCTAssertEqual(
            TerminalContainerView.shortcutSelectableTerminalTabIndex(for: 1, tabKinds: tabKinds),
            0
        )
        XCTAssertEqual(
            TerminalContainerView.shortcutSelectableTerminalTabIndex(for: 2, tabKinds: tabKinds),
            2
        )
        XCTAssertEqual(
            TerminalContainerView.shortcutSelectableTerminalTabIndex(for: 9, tabKinds: tabKinds),
            2
        )
    }

    func testNextTerminalTabIndexSkipsToolTabs() {
        let tabKinds: [TerminalTabKind] = [.terminal, .smart("processes"), .terminal, .smart("network")]

        XCTAssertEqual(
            TerminalContainerView.nextTerminalTabIndex(after: 0, in: tabKinds),
            2
        )
        XCTAssertEqual(
            TerminalContainerView.nextTerminalTabIndex(after: 2, in: tabKinds),
            0
        )
        XCTAssertEqual(
            TerminalContainerView.nextTerminalTabIndex(after: 1, in: tabKinds),
            2
        )
        XCTAssertNil(
            TerminalContainerView.nextTerminalTabIndex(after: 0, in: [.smart("processes")])
        )
    }

    func testPreviousTerminalTabIndexSkipsToolTabs() {
        let tabKinds: [TerminalTabKind] = [.terminal, .smart("processes"), .terminal, .smart("network")]

        XCTAssertEqual(
            TerminalContainerView.previousTerminalTabIndex(before: 2, in: tabKinds),
            0
        )
        XCTAssertEqual(
            TerminalContainerView.previousTerminalTabIndex(before: 0, in: tabKinds),
            2
        )
        XCTAssertEqual(
            TerminalContainerView.previousTerminalTabIndex(before: 1, in: tabKinds),
            0
        )
        XCTAssertNil(
            TerminalContainerView.previousTerminalTabIndex(before: 0, in: [.smart("processes")])
        )
    }

    func testClampedDropInsertionIndexKeepsPinnedTabsInPinnedRegion() {
        XCTAssertEqual(
            TerminalContainerView.clampedDropInsertionIndex(
                requestedIndex: 4,
                movingPinned: true,
                pinnedCount: 2,
                tabCount: 5
            ),
            2
        )
        XCTAssertEqual(
            TerminalContainerView.clampedDropInsertionIndex(
                requestedIndex: 0,
                movingPinned: false,
                pinnedCount: 2,
                tabCount: 5
            ),
            2
        )
    }

    func testReorderDestinationIndexTreatsInsertionIndexAsEdgeDropTarget() {
        XCTAssertEqual(
            TabBarView.reorderDestinationIndex(sourceIndex: 1, insertionIndex: 4, tabCount: 4),
            3
        )
        XCTAssertEqual(
            TabBarView.reorderDestinationIndex(sourceIndex: 3, insertionIndex: 0, tabCount: 4),
            0
        )
    }
}
