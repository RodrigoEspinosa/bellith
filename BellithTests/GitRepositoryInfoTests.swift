import XCTest
@testable import Bellith

final class GitRepositoryInfoTests: XCTestCase {
    func testGitRepositoryInfoDetectsLinkedWorktree() throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory.appendingPathComponent("BellithGitRepo-\(UUID().uuidString)", isDirectory: true)
        let worktree = root.appendingPathComponent("feature-worktree", isDirectory: true)

        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        defer {
            try? fileManager.removeItem(at: root)
        }

        try runGit(["init"], in: root)
        try runGit(["config", "user.name", "Bellith Tests"], in: root)
        try runGit(["config", "user.email", "tests@example.com"], in: root)

        let readme = root.appendingPathComponent("README.md")
        try "initial".write(to: readme, atomically: true, encoding: .utf8)
        try runGit(["add", "README.md"], in: root)
        try runGit(["commit", "-m", "initial"], in: root)
        try runGit(["worktree", "add", "-b", "feature", worktree.path], in: root)

        let worktreeInfo = TerminalContainerView.gitRepositoryInfo(in: worktree.path)
        XCTAssertEqual(worktreeInfo?.branch, "feature")
        XCTAssertEqual(worktreeInfo?.worktreeName, "feature-worktree")
        XCTAssertTrue(worktreeInfo?.isWorktree ?? false)

        let rootInfo = TerminalContainerView.gitRepositoryInfo(in: root.path)
        XCTAssertNotNil(rootInfo?.branch)
        XCTAssertNil(rootInfo?.worktreeName)
        XCTAssertFalse(rootInfo?.isWorktree ?? true)
    }

    private func runGit(_ arguments: [String], in directory: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["-c", "commit.gpgsign=false"] + arguments
        process.currentDirectoryURL = directory

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let stdout = String(data: outputPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            let stderr = String(data: errorPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            throw NSError(
                domain: "GitRepositoryInfoTests",
                code: Int(process.terminationStatus),
                userInfo: [NSLocalizedDescriptionKey: "git \(arguments.joined(separator: " ")) failed: \(stdout) \(stderr)"]
            )
        }
    }
}
