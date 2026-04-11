import XCTest
@testable import Bellith

final class LocalSessionLaunchBuilderTests: XCTestCase {
    func testBuildsTmuxCommandWithWorkingDirectory() {
        XCTAssertEqual(
            LocalSessionLaunchBuilder.command(
                bootstrap: .tmux,
                sessionName: "bellith-work",
                workingDirectory: "/Users/rec/Projects/bellith"
            ),
            "cd '/Users/rec/Projects/bellith' && tmux attach -t 'bellith-work' || tmux new -s 'bellith-work'"
        )
    }

    func testBuildsZellijCommandWithoutWorkingDirectory() {
        XCTAssertEqual(
            LocalSessionLaunchBuilder.command(
                bootstrap: .zellij,
                sessionName: "bellith-work",
                workingDirectory: nil
            ),
            "zellij options --session-name 'bellith-work' --attach-to-session true"
        )
    }

    func testReturnsNilWithoutStableSessionName() {
        XCTAssertNil(
            LocalSessionLaunchBuilder.command(
                bootstrap: .tmux,
                sessionName: "   ",
                workingDirectory: "/tmp"
            )
        )
    }

    func testReturnsNilWhenBootstrapDisabled() {
        XCTAssertNil(
            LocalSessionLaunchBuilder.command(
                bootstrap: .none,
                sessionName: "bellith-work",
                workingDirectory: "/tmp"
            )
        )
    }
}
