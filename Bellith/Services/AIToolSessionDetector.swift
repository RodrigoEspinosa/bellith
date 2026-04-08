import Foundation

struct ForegroundProcessPresentation: Equatable {
    enum Style: Equatable {
        case standard
        case tool
    }

    let text: String
    let iconName: String
    let style: Style
}

enum AIToolSessionDetector {
    private enum KnownTool: String {
        case claude = "claude"
        case claudeCode = "claude-code"
        case copilot = "copilot"
        case cursorAgent = "cursor-agent"

        var displayName: String {
            switch self {
            case .claude, .claudeCode:
                return "Claude Code"
            case .copilot:
                return "Copilot CLI"
            case .cursorAgent:
                return "Cursor Agent"
            }
        }

        var iconName: String {
            switch self {
            case .claude, .claudeCode:
                return "sparkles.rectangle.stack"
            case .copilot:
                return "wand.and.stars"
            case .cursorAgent:
                return "cursorarrow.motionlines"
            }
        }
    }

    static func presentation(
        for process: TerminalProcessInfo?,
        arguments: (pid_t) -> [String],
        now: Date = .init()
    ) -> ForegroundProcessPresentation? {
        guard let process else { return nil }

        let normalizedName = process.name.lowercased()
        if let knownTool = knownTool(named: normalizedName) {
            let model = extractModel(from: arguments(process.pid))
            let uptime = ProcessMonitor.formatUptime(from: process.startTime)
            let details = [model, uptime == "\u{2014}" ? nil : uptime]
                .compactMap { $0 }
                .joined(separator: " · ")

            return ForegroundProcessPresentation(
                text: details.isEmpty ? knownTool.displayName : "\(knownTool.displayName) · \(details)",
                iconName: knownTool.iconName,
                style: .tool
            )
        }

        return ForegroundProcessPresentation(
            text: process.name,
            iconName: "gearshape.fill",
            style: .standard
        )
    }

    static func extractModel(from arguments: [String]) -> String? {
        guard arguments.count > 1 else { return nil }

        for (index, argument) in arguments.enumerated() {
            if argument == "--model" || argument == "-m" {
                let valueIndex = index + 1
                if valueIndex < arguments.count {
                    return normalizeModel(arguments[valueIndex])
                }
            }

            if argument.hasPrefix("--model=") {
                return normalizeModel(String(argument.dropFirst("--model=".count)))
            }

            if argument.hasPrefix("-m"), argument.count > 2 {
                return normalizeModel(String(argument.dropFirst(2)))
            }
        }

        return nil
    }

    private static func knownTool(named processName: String) -> KnownTool? {
        if processName == KnownTool.claude.rawValue || processName.contains(KnownTool.claude.rawValue) {
            return .claude
        }

        return KnownTool(rawValue: processName)
    }

    private static func normalizeModel(_ model: String) -> String? {
        let trimmed = model.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let aliases: [String: String] = [
            "sonnet": "Sonnet",
            "haiku": "Haiku",
            "opus": "Opus",
        ]

        let lowered = trimmed.lowercased()
        if let alias = aliases[lowered] {
            return alias
        }

        if let alias = aliases.first(where: { lowered.contains($0.key) })?.value {
            return alias
        }

        return trimmed
    }
}
