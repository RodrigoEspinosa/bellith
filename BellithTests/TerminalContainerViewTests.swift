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
}
