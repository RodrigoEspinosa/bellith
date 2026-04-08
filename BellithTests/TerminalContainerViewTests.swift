import XCTest
@testable import Bellith

final class TerminalContainerViewTests: XCTestCase {
    func testShouldPollRuntimeStatusRequiresVisibleKeyWindow() {
        XCTAssertTrue(TerminalContainerView.shouldPollRuntimeStatus(windowIsVisible: true, isKeyWindow: true))
        XCTAssertFalse(TerminalContainerView.shouldPollRuntimeStatus(windowIsVisible: true, isKeyWindow: false))
        XCTAssertFalse(TerminalContainerView.shouldPollRuntimeStatus(windowIsVisible: false, isKeyWindow: true))
        XCTAssertFalse(TerminalContainerView.shouldPollRuntimeStatus(windowIsVisible: false, isKeyWindow: false))
    }
}
