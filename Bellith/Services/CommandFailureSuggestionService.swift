import Foundation

struct CommandFailureSuggestion: Equatable {
    let title: String
    let explanation: String
    let fixCommand: String
    let matchedLine: String
}

enum CommandFailureSuggestionService {
    private static let installFormulaOverrides: [String: String] = [
        "code": "visual-studio-code",
        "fd": "fd",
        "gsed": "gnu-sed",
        "npm": "node",
        "python": "python",
        "python3": "python",
        "rg": "ripgrep",
    ]

    private static let errorKeywords = [
        "command not found",
        "permission denied",
        "no such file or directory",
        "not a git repository",
        "missing script",
        "no module named",
        "cannot find module",
        "is not a git command",
        "fatal:",
        "error:",
        "error ",
    ]

    static func suggestion(
        for transcript: String,
        exitCode: Int16,
        foregroundProcessName: String? = nil
    ) -> CommandFailureSuggestion? {
        guard exitCode > 0 else { return nil }

        let recentLines = normalizedLines(from: transcript)
        guard let matchedLine = likelyErrorLine(in: recentLines) else { return nil }

        if let missingCommand = commandNotFound(in: matchedLine) {
            return CommandFailureSuggestion(
                title: "Missing command",
                explanation: "\(quoted(missingCommand)) is not available on your PATH, so the shell could not launch it.",
                fixCommand: "brew install \(installFormula(for: missingCommand))",
                matchedLine: matchedLine
            )
        }

        if matchedLine.localizedCaseInsensitiveContains("permission denied") {
            let path = permissionDeniedPath(in: matchedLine)
            return CommandFailureSuggestion(
                title: "Permission denied",
                explanation: path.map {
                    "\(quoted($0)) is present, but the shell does not have permission to execute it."
                } ?? "The shell found the target, but it is not executable with the current permissions.",
                fixCommand: path.map { "chmod +x \(shellQuoted($0))" } ?? "ls -l",
                matchedLine: matchedLine
            )
        }

        if matchedLine.localizedCaseInsensitiveContains("no such file or directory") {
            let path = missingPath(in: matchedLine)
            return CommandFailureSuggestion(
                title: "Missing path",
                explanation: path.map {
                    "The command referenced \(quoted($0)), but that path does not exist from the current working directory."
                } ?? "The command referenced a file or directory that could not be found.",
                fixCommand: path.map { "ls -la \(shellQuoted($0))" } ?? "pwd && ls -la",
                matchedLine: matchedLine
            )
        }

        if matchedLine.localizedCaseInsensitiveContains("not a git repository") {
            return CommandFailureSuggestion(
                title: "Not inside a Git repository",
                explanation: "Git could not locate a repository from the current working directory.",
                fixCommand: "git rev-parse --show-toplevel",
                matchedLine: matchedLine
            )
        }

        if gitUnknownSubcommand(in: matchedLine) != nil {
            return CommandFailureSuggestion(
                title: "Unknown Git subcommand",
                explanation: "Git recognized the main command, but not the subcommand that was requested.",
                fixCommand: "git help -a",
                matchedLine: matchedLine
            )
        }

        if let script = missingScript(in: matchedLine) {
            return CommandFailureSuggestion(
                title: "Missing package script",
                explanation: "The project does not define the \(quoted(script)) script in package.json.",
                fixCommand: "npm run",
                matchedLine: matchedLine
            )
        }

        if let module = missingPythonModule(in: matchedLine) {
            return CommandFailureSuggestion(
                title: "Python module missing",
                explanation: "Python could not import the module \(quoted(module)).",
                fixCommand: "python3 -m pip install \(shellQuoted(module))",
                matchedLine: matchedLine
            )
        }

        if let module = missingNodeModule(in: matchedLine) {
            return CommandFailureSuggestion(
                title: "Node package missing",
                explanation: "Node could not resolve the package \(quoted(module)) from the current project.",
                fixCommand: "npm install \(shellQuoted(module))",
                matchedLine: matchedLine
            )
        }

        guard let helpCommand = fallbackHelpCommand(from: matchedLine, foregroundProcessName: foregroundProcessName) else {
            return nil
        }

        return CommandFailureSuggestion(
            title: "Command exited with status \(exitCode)",
            explanation: "Bellith spotted this recent error: \(quoted(matchedLine)). The suggested fix opens the command help so you can verify syntax and flags.",
            fixCommand: helpCommand,
            matchedLine: matchedLine
        )
    }

    private static func normalizedLines(from transcript: String, limit: Int = 64) -> [String] {
        transcript
            .replacingOccurrences(of: "\r\n", with: "\n")
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .suffix(limit)
            .map { $0 }
    }

    private static func likelyErrorLine(in lines: [String]) -> String? {
        for line in lines.reversed() where errorKeywords.contains(where: { line.localizedCaseInsensitiveContains($0) }) {
            return line
        }

        return lines.reversed().first(where: { !looksLikePrompt($0) })
    }

    private static func looksLikePrompt(_ line: String) -> Bool {
        guard let firstCharacter = line.first else { return false }
        return ["$", "%", "#", "❯"].contains(firstCharacter)
    }

    private static func commandNotFound(in line: String) -> String? {
        if let command = firstMatch(in: line, pattern: #"command not found:\s*([^\s]+)"#) {
            return sanitizedToken(command)
        }
        if let command = firstMatch(in: line, pattern: #"^([^:\s]+):\s*command not found"#) {
            return sanitizedToken(command)
        }
        return nil
    }

    private static func permissionDeniedPath(in line: String) -> String? {
        if let path = firstMatch(in: line, pattern: #"permission denied:\s*(.+)$"#) {
            return sanitizedPath(path)
        }
        if let path = firstMatch(in: line, pattern: #"^.*?:\s*(.+?):\s*permission denied$"#, options: [.caseInsensitive]) {
            return sanitizedPath(path)
        }
        return nil
    }

    private static func missingPath(in line: String) -> String? {
        if let quotedPath = firstMatch(in: line, pattern: #"'([^']+)'"#) {
            return sanitizedPath(quotedPath)
        }
        if let path = firstMatch(in: line, pattern: #":\s*(.+?):\s*No such file or directory$"#, options: [.caseInsensitive]) {
            return sanitizedPath(path)
        }
        if let path = firstMatch(in: line, pattern: #"No such file or directory:\s*(.+)$"#, options: [.caseInsensitive]) {
            return sanitizedPath(path)
        }
        return nil
    }

    private static func gitUnknownSubcommand(in line: String) -> String? {
        firstMatch(in: line, pattern: #"git:\s*'([^']+)'\s*is not a git command"#, options: [.caseInsensitive])
    }

    private static func missingScript(in line: String) -> String? {
        firstMatch(in: line, pattern: #"Missing script:\s*[\"']([^\"']+)[\"']"#, options: [.caseInsensitive])
    }

    private static func missingPythonModule(in line: String) -> String? {
        firstMatch(in: line, pattern: #"No module named ['\"]([^'\"]+)['\"]"#, options: [.caseInsensitive])
    }

    private static func missingNodeModule(in line: String) -> String? {
        firstMatch(in: line, pattern: #"Cannot find module ['\"]([^'\"]+)['\"]"#, options: [.caseInsensitive])
    }

    private static func fallbackHelpCommand(from line: String, foregroundProcessName: String?) -> String? {
        let command = inferredCommand(from: line) ?? sanitizedToken(foregroundProcessName)
        guard let command, !command.isEmpty else { return nil }
        return "\(command) --help"
    }

    private static func inferredCommand(from line: String) -> String? {
        if let missingCommand = commandNotFound(in: line) {
            return missingCommand
        }

        let separators = CharacterSet(charactersIn: ": ")
        let prefix = line.components(separatedBy: separators).first
        return sanitizedToken(prefix)
    }

    private static func installFormula(for command: String) -> String {
        installFormulaOverrides[command] ?? command
    }

    private static func quoted(_ text: String) -> String {
        "“\(text)”"
    }

    private static func shellQuoted(_ text: String) -> String {
        let escaped = text.replacingOccurrences(of: "'", with: "'\\''")
        return "'\(escaped)'"
    }

    private static func sanitizedToken(_ token: String?) -> String? {
        guard let token else { return nil }
        let trimmed = token.trimmingCharacters(in: CharacterSet(charactersIn: " \t\n\r'\"`()[]{}<>.,;"))
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func sanitizedPath(_ path: String?) -> String? {
        guard let path else { return nil }
        let trimmed = path.trimmingCharacters(in: CharacterSet(charactersIn: " \t\n\r'\""))
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func firstMatch(
        in text: String,
        pattern: String,
        options: NSRegularExpression.Options = []
    ) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else {
            return nil
        }

        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, options: [], range: range), match.numberOfRanges > 1,
              let captureRange = Range(match.range(at: 1), in: text) else {
            return nil
        }

        return String(text[captureRange])
    }
}
