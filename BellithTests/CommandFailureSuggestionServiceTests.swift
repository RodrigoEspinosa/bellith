import XCTest
@testable import Bellith

final class CommandFailureSuggestionServiceTests: XCTestCase {
    func testReturnsNilForSuccessfulExit() {
        let suggestion = CommandFailureSuggestionService.suggestion(
            for: "zsh% echo ok\nok",
            exitCode: 0,
            foregroundProcessName: "echo"
        )

        XCTAssertNil(suggestion)
    }

    func testSuggestsBrewInstallForMissingCommand() {
        let suggestion = CommandFailureSuggestionService.suggestion(
            for: "zsh: command not found: rg",
            exitCode: 127,
            foregroundProcessName: "rg"
        )

        XCTAssertEqual(suggestion?.title, "Missing command")
        XCTAssertEqual(suggestion?.fixCommand, "brew install ripgrep")
    }

    func testSuggestsChmodForPermissionDenied() {
        let suggestion = CommandFailureSuggestionService.suggestion(
            for: "zsh: permission denied: ./scripts/setup.sh",
            exitCode: 126,
            foregroundProcessName: "./scripts/setup.sh"
        )

        XCTAssertEqual(suggestion?.title, "Permission denied")
        XCTAssertEqual(suggestion?.fixCommand, "chmod +x './scripts/setup.sh'")
    }

    func testSuggestsGitTopLevelWhenRepoMissing() {
        let suggestion = CommandFailureSuggestionService.suggestion(
            for: "fatal: not a git repository (or any of the parent directories): .git",
            exitCode: 128,
            foregroundProcessName: "git"
        )

        XCTAssertEqual(suggestion?.title, "Not inside a Git repository")
        XCTAssertEqual(suggestion?.fixCommand, "git rev-parse --show-toplevel")
    }

    func testSuggestsPipInstallForMissingPythonModule() {
        let transcript = "Traceback (most recent call last):\nModuleNotFoundError: No module named 'rich'"
        let suggestion = CommandFailureSuggestionService.suggestion(
            for: transcript,
            exitCode: 1,
            foregroundProcessName: "python3"
        )

        XCTAssertEqual(suggestion?.title, "Python module missing")
        XCTAssertEqual(suggestion?.fixCommand, "python3 -m pip install 'rich'")
    }

    func testFallsBackToCommandHelpForUnknownFailure() {
        let suggestion = CommandFailureSuggestionService.suggestion(
            for: "git: unknown option --example",
            exitCode: 129,
            foregroundProcessName: "git"
        )

        XCTAssertEqual(suggestion?.title, "Command exited with status 129")
        XCTAssertEqual(suggestion?.fixCommand, "git --help")
    }
}
