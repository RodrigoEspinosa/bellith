import XCTest
@testable import Bellith

final class TerminalSessionCoordinatorTests: XCTestCase {
    func testRestorationIndicatorExplainsWhenScrollbackIsNotReplayed() {
        let indicator = TerminalSessionCoordinator.restorationIndicator(
            hasScrollback: true,
            cwd: "/Users/rec/project",
            isSSH: false
        )

        XCTAssertEqual(indicator.title, "Session Restored")
        XCTAssertEqual(indicator.detail, "Working directory restored. Previous output was not replayed.")
    }

    func testRestorationIndicatorHandlesSSHReconnects() {
        let indicator = TerminalSessionCoordinator.restorationIndicator(
            hasScrollback: false,
            cwd: nil,
            isSSH: true
        )

        XCTAssertEqual(indicator.title, "Session Restored")
        XCTAssertEqual(indicator.detail, "Remote session is reconnecting.")
    }
}
