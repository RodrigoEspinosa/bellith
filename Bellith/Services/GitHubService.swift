import Foundation

/// Lightweight wrapper around the `gh` CLI for querying GitHub issues and pull requests.
/// All methods run synchronously on the calling thread — callers should dispatch to a
/// background queue.
enum GitHubService {

    // MARK: - Models

    struct Issue: Equatable {
        let number: Int
        let title: String
        let author: String
        let labels: [String]
        let createdAt: String
        let url: String
    }

    struct PullRequest: Equatable {
        let number: Int
        let title: String
        let author: String
        let labels: [String]
        let isDraft: Bool
        let headBranch: String
        let createdAt: String
        let url: String
    }

    struct RepoInfo: Equatable {
        let owner: String
        let name: String
        let fullName: String
    }

    struct StatusSummary: Equatable {
        let repoName: String
        let openPRs: Int
        let openIssues: Int
    }

    struct StatusDetails: Equatable {
        let repoName: String
        let openPRs: Int
        let openIssues: Int
        let pullRequests: [PullRequest]
        let issues: [Issue]

        var summary: StatusSummary? {
            guard openPRs > 0 || openIssues > 0 else { return nil }
            return StatusSummary(repoName: repoName, openPRs: openPRs, openIssues: openIssues)
        }
    }

    enum GitHubError: Error {
        case ghNotInstalled
        case notARepository
        case commandFailed(String)
    }

    // MARK: - gh availability

    private static var cachedGHPath: String?
    private static var pathChecked = false

    /// Returns the path to `gh` if installed, or nil.
    static func ghPath() -> String? {
        if pathChecked { return cachedGHPath }
        pathChecked = true

        // Check common locations
        let candidates = [
            "/opt/homebrew/bin/gh",
            "/usr/local/bin/gh",
            "/usr/bin/gh",
        ]
        for path in candidates {
            if FileManager.default.isExecutableFile(atPath: path) {
                cachedGHPath = path
                return path
            }
        }

        // Fallback: which gh
        let result = run(executable: "/usr/bin/which", arguments: ["gh"])
        if let path = result?.trimmingCharacters(in: .whitespacesAndNewlines), !path.isEmpty {
            cachedGHPath = path
            return path
        }

        return nil
    }

    static var isAvailable: Bool { ghPath() != nil }

    // MARK: - Queries

    /// Detect the current repo from a working directory.
    static func repoInfo(in directory: String) -> Result<RepoInfo, GitHubError> {
        guard let gh = ghPath() else { return .failure(.ghNotInstalled) }

        guard let output = run(executable: gh, arguments: [
            "repo", "view", "--json", "owner,name,nameWithOwner",
        ], directory: directory) else {
            return .failure(.notARepository)
        }

        guard let data = output.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let owner = json["owner"] as? [String: Any],
              let login = owner["login"] as? String,
              let name = json["name"] as? String,
              let fullName = json["nameWithOwner"] as? String else {
            return .failure(.commandFailed("Failed to parse repo info"))
        }

        return .success(RepoInfo(owner: login, name: name, fullName: fullName))
    }

    /// Quick summary of open PRs and issues for the status bar. Runs two fast `gh` commands.
    static func statusSummary(in directory: String) -> StatusSummary? {
        statusDetails(in: directory)?.summary
    }

    /// Detailed PR and issue metadata for hover affordances in the status bar.
    static func statusDetails(
        in directory: String,
        countLimit: Int = 100,
        previewLimit: Int = 8
    ) -> StatusDetails? {
        guard ghPath() != nil else { return nil }
        guard case .success(let repo) = repoInfo(in: directory) else { return nil }

        let prs: [PullRequest]
        if case .success(let result) = listPullRequests(in: directory, limit: countLimit) {
            prs = result
        } else {
            prs = []
        }

        let issues: [Issue]
        if case .success(let result) = listIssues(in: directory, limit: countLimit) {
            issues = result
        } else {
            issues = []
        }

        guard !prs.isEmpty || !issues.isEmpty else { return nil }

        return StatusDetails(
            repoName: repo.fullName,
            openPRs: prs.count,
            openIssues: issues.count,
            pullRequests: Array(prs.prefix(previewLimit)),
            issues: Array(issues.prefix(previewLimit))
        )
    }

    /// List open issues for the repo at the given directory.
    static func listIssues(in directory: String, limit: Int = 25) -> Result<[Issue], GitHubError> {
        guard let gh = ghPath() else { return .failure(.ghNotInstalled) }

        guard let output = run(executable: gh, arguments: [
            "issue", "list",
            "--state", "open",
            "--limit", "\(limit)",
            "--json", "number,title,author,labels,createdAt,url",
        ], directory: directory) else {
            return .failure(.commandFailed("Failed to list issues"))
        }

        return .success(parseIssues(output))
    }

    /// List open pull requests for the repo at the given directory.
    static func listPullRequests(in directory: String, limit: Int = 25) -> Result<[PullRequest], GitHubError> {
        guard let gh = ghPath() else { return .failure(.ghNotInstalled) }

        guard let output = run(executable: gh, arguments: [
            "pr", "list",
            "--state", "open",
            "--limit", "\(limit)",
            "--json", "number,title,author,labels,isDraft,headRefName,createdAt,url",
        ], directory: directory) else {
            return .failure(.commandFailed("Failed to list pull requests"))
        }

        return .success(parsePullRequests(output))
    }

    /// Open an issue or PR in the default browser.
    static func openInBrowser(number: Int, isPR: Bool, directory: String) {
        guard let gh = ghPath() else { return }
        let kind = isPR ? "pr" : "issue"
        DispatchQueue.global(qos: .userInitiated).async {
            _ = run(executable: gh, arguments: [kind, "view", "\(number)", "--web"], directory: directory)
        }
    }

    /// Checkout a pull request branch.
    static func checkoutPR(number: Int, directory: String) -> Result<String, GitHubError> {
        guard let gh = ghPath() else { return .failure(.ghNotInstalled) }

        guard let output = run(executable: gh, arguments: [
            "pr", "checkout", "\(number)",
        ], directory: directory) else {
            return .failure(.commandFailed("Failed to checkout PR #\(number)"))
        }

        return .success(output)
    }

    /// Create a git worktree for an issue or PR branch.
    static func createWorktree(number: Int, isPR: Bool, directory: String) -> Result<String, GitHubError> {
        // Determine branch name
        let branchName: String
        if isPR {
            // Get the PR's head branch name
            guard let gh = ghPath() else { return .failure(.ghNotInstalled) }
            guard let output = run(executable: gh, arguments: [
                "pr", "view", "\(number)", "--json", "headRefName",
            ], directory: directory),
                  let data = output.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let headRef = json["headRefName"] as? String else {
                return .failure(.commandFailed("Failed to get PR branch"))
            }
            branchName = headRef
        } else {
            branchName = "issue-\(number)"
        }

        // Find repo root
        guard let repoRoot = run(
            executable: "/usr/bin/git",
            arguments: ["-C", directory, "rev-parse", "--show-toplevel"]
        )?.trimmingCharacters(in: .whitespacesAndNewlines) else {
            return .failure(.notARepository)
        }

        let worktreePath = (repoRoot as NSString)
            .deletingLastPathComponent
            .appending("/\((repoRoot as NSString).lastPathComponent)-\(branchName)")

        // For PRs, fetch the branch first then create worktree
        if isPR {
            guard let gh = ghPath() else { return .failure(.ghNotInstalled) }
            // Use gh to fetch the PR ref
            _ = run(executable: gh, arguments: [
                "pr", "checkout", "\(number)", "--detach",
            ], directory: directory)

            // Create worktree from the fetched branch
            guard run(executable: "/usr/bin/git", arguments: [
                "-C", directory, "worktree", "add", worktreePath, branchName,
            ], directory: directory) != nil else {
                return .failure(.commandFailed("Failed to create worktree at \(worktreePath)"))
            }
        } else {
            // For issues, create a new branch in a worktree
            guard run(executable: "/usr/bin/git", arguments: [
                "-C", directory, "worktree", "add", "-b", branchName, worktreePath,
            ], directory: directory) != nil else {
                return .failure(.commandFailed("Failed to create worktree at \(worktreePath)"))
            }
        }

        return .success(worktreePath)
    }

    // MARK: - JSON parsing

    private static func parseIssues(_ json: String) -> [Issue] {
        guard let data = json.data(using: .utf8),
              let array = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return []
        }

        return array.compactMap { item in
            guard let number = item["number"] as? Int,
                  let title = item["title"] as? String else { return nil }

            let author = (item["author"] as? [String: Any])?["login"] as? String ?? ""
            let labels = (item["labels"] as? [[String: Any]])?.compactMap { $0["name"] as? String } ?? []
            let createdAt = formatDate(item["createdAt"] as? String)
            let url = item["url"] as? String ?? ""

            return Issue(number: number, title: title, author: author, labels: labels, createdAt: createdAt, url: url)
        }
    }

    private static func parsePullRequests(_ json: String) -> [PullRequest] {
        guard let data = json.data(using: .utf8),
              let array = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return []
        }

        return array.compactMap { item in
            guard let number = item["number"] as? Int,
                  let title = item["title"] as? String else { return nil }

            let author = (item["author"] as? [String: Any])?["login"] as? String ?? ""
            let labels = (item["labels"] as? [[String: Any]])?.compactMap { $0["name"] as? String } ?? []
            let isDraft = item["isDraft"] as? Bool ?? false
            let headBranch = item["headRefName"] as? String ?? ""
            let createdAt = formatDate(item["createdAt"] as? String)
            let url = item["url"] as? String ?? ""

            return PullRequest(
                number: number, title: title, author: author, labels: labels,
                isDraft: isDraft, headBranch: headBranch, createdAt: createdAt, url: url
            )
        }
    }

    private static func formatDate(_ isoString: String?) -> String {
        guard let isoString else { return "" }
        let formatter = ISO8601DateFormatter()
        guard let date = formatter.date(from: isoString) else { return isoString }

        let interval = Date().timeIntervalSince(date)
        if interval < 3600 { return "\(Int(interval / 60))m ago" }
        if interval < 86400 { return "\(Int(interval / 3600))h ago" }
        if interval < 604_800 { return "\(Int(interval / 86400))d ago" }

        let display = DateFormatter()
        display.dateFormat = "MMM d"
        return display.string(from: date)
    }

    // MARK: - Process execution

    @discardableResult
    private static func run(executable: String, arguments: [String], directory: String? = nil) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        if let directory {
            process.currentDirectoryURL = URL(fileURLWithPath: directory)
        }
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { return nil }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            return String(data: data, encoding: .utf8)
        } catch {
            return nil
        }
    }
}
