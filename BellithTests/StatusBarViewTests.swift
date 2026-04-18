import XCTest
@testable import Bellith

final class StatusBarViewTests: XCTestCase {
    func testGitHubToolTipIncludesPullRequestsAndIssues() {
        let details = GitHubService.StatusDetails(
            repoName: "owner/repo",
            openPRs: 2,
            openIssues: 1,
            pullRequests: [
                .init(number: 12, title: "Improve status bar", author: "rec", labels: [], isDraft: false, headBranch: "feat/status-bar", createdAt: "1h ago", url: "https://example.com/pr/12", additions: 0, deletions: 0, checkState: .none),
                .init(number: 15, title: "Add loading state", author: "bot", labels: [], isDraft: false, headBranch: "feat/loading", createdAt: "2h ago", url: "https://example.com/pr/15", additions: 0, deletions: 0, checkState: .none),
            ],
            issues: [
                .init(number: 8, title: "Popover clips", author: "qa", labels: [], createdAt: "3h ago", url: "https://example.com/issues/8"),
            ]
        )

        let toolTip = StatusBarView.gitHubToolTip(details: details)

        XCTAssertEqual(
            toolTip,
            [
                "owner/repo",
                "",
                "Pull requests",
                "#12 Improve status bar — @rec",
                "#15 Add loading state — @bot",
                "",
                "Issues",
                "#8 Popover clips — @qa",
            ].joined(separator: "\n")
        )
    }
}
