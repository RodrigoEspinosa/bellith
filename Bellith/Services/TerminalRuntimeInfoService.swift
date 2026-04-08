import Foundation

struct TerminalRuntimeStatus {
    let foregroundProcess: String?
    let detectedContext: TerminalContext?
}

enum TerminalRuntimeInfoService {
    static func runtimeStatus(for shellPID: pid_t?) -> TerminalRuntimeStatus {
        guard let shellPID,
              let tree = ProcessMonitor.processTree(rootPID: shellPID) else {
            return TerminalRuntimeStatus(foregroundProcess: nil, detectedContext: nil)
        }

        let shellName = ProcessMonitor.processName(for: shellPID)
        let foregroundProcess = SSHSessionDetector.foregroundProcess(in: tree, shellPID: shellPID)
        let foregroundName = foregroundProcess?.name.lowercased() == shellName.lowercased()
            ? nil
            : foregroundProcess?.name
        let detectedContext = SSHSessionDetector.detectedContext(
            in: tree,
            shellPID: shellPID,
            arguments: ProcessMonitor.arguments(for:)
        )

        return TerminalRuntimeStatus(foregroundProcess: foregroundName, detectedContext: detectedContext)
    }

    static func gitRepositoryInfo(in directory: String) -> GitRepositoryInfo? {
        let pipe = Pipe()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = [
            "-C", directory,
            "rev-parse",
            "--abbrev-ref", "HEAD",
            "--git-dir",
            "--git-common-dir",
            "--show-toplevel",
        ]
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { return nil }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard let output, !output.isEmpty else { return nil }

            let lines = output.components(separatedBy: .newlines)
            guard lines.count >= 4 else { return nil }

            let branch = normalizedGitOutput(lines[0])
            let gitDir = resolvedGitURL(for: lines[1], relativeTo: directory)
            let commonDir = resolvedGitURL(for: lines[2], relativeTo: directory)
            let topLevel = resolvedGitURL(for: lines[3], relativeTo: directory)
            let isWorktree = gitDir.resolvingSymlinksInPath().path != commonDir.resolvingSymlinksInPath().path
            let worktreeName = isWorktree ? topLevel.lastPathComponent : nil
            return GitRepositoryInfo(branch: branch, worktreeName: worktreeName, isWorktree: isWorktree)
        } catch {
            return nil
        }
    }

    private static func resolvedGitURL(for path: String, relativeTo directory: String) -> URL {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("/") {
            return URL(fileURLWithPath: trimmed).standardizedFileURL
        }
        return URL(fileURLWithPath: directory, isDirectory: true)
            .appendingPathComponent(trimmed)
            .standardizedFileURL
    }

    private static func normalizedGitOutput(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
