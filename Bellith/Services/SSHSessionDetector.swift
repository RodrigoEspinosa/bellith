import Foundation

enum SSHSessionDetector {
    private static let remoteClientNames: Set<String> = ["ssh"]
    private static let optionsRequiringValue: Set<Character> = [
        "B", "b", "c", "D", "E", "e", "F", "I", "i", "J", "L", "l", "m", "O",
        "o", "p", "Q", "R", "S", "W", "w"
    ]

    static func foregroundProcess(in processTree: TerminalProcessInfo, shellPID: pid_t) -> TerminalProcessInfo? {
        var candidate: (depth: Int, node: TerminalProcessInfo)?

        func visit(_ node: TerminalProcessInfo, depth: Int) {
            if node.children.isEmpty, node.pid != shellPID {
                if let best = candidate {
                    if depth >= best.depth {
                        candidate = (depth, node)
                    }
                } else {
                    candidate = (depth, node)
                }
            }

            for child in node.children {
                visit(child, depth: depth + 1)
            }
        }

        visit(processTree, depth: 0)
        return candidate?.node
    }

    static func detectedContext(
        in processTree: TerminalProcessInfo,
        shellPID: pid_t,
        arguments: (pid_t) -> [String]
    ) -> TerminalContext? {
        guard let foreground = foregroundProcess(in: processTree, shellPID: shellPID) else { return nil }
        guard remoteClientNames.contains(foreground.name.lowercased()) else { return nil }
        let processArguments = arguments(foreground.pid)
        guard let destination = destinationArgument(in: processArguments) else { return nil }
        return context(forDestination: destination, arguments: processArguments)
    }

    static func destinationArgument(in arguments: [String]) -> String? {
        guard arguments.count > 1 else { return nil }

        var index = 1
        var endOfOptions = false

        while index < arguments.count {
            let argument = arguments[index]

            if endOfOptions {
                return normalizedDestination(argument)
            }

            if argument == "--" {
                endOfOptions = true
                index += 1
                continue
            }

            if argument.hasPrefix("-"), argument != "-" {
                let consumesValue = consumesValue(for: argument)
                let hasInlineValue = inlineOptionValue(in: argument) != nil
                index += consumesValue && !hasInlineValue ? 2 : 1
                continue
            }

            return normalizedDestination(argument)
        }

        return nil
    }

    static func context(forDestination destination: String, arguments: [String] = []) -> TerminalContext? {
        let trimmed = destination.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let configuredUser = explicitUser(in: arguments)

        if let components = URLComponents(string: trimmed),
           components.scheme?.lowercased() == "ssh",
           let host = normalizedHost(components.host) {
            return TerminalContext(
                source: .sshCommand,
                host: host,
                user: normalizedUser(components.user) ?? configuredUser
            )
        }

        let parts = trimmed.split(separator: "@", maxSplits: 1, omittingEmptySubsequences: false)
        if parts.count == 2 {
            let user = normalizedUser(String(parts[0]))
            let host = normalizedHost(String(parts[1]))
            guard host != nil else { return nil }
            return TerminalContext(source: .sshCommand, host: host, user: user)
        }

        guard let host = normalizedHost(trimmed) else { return nil }
        return TerminalContext(source: .sshCommand, host: host, user: configuredUser)
    }

    private static func normalizedDestination(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func normalizedUser(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func normalizedHost(_ value: String?) -> String? {
        guard let value else { return nil }

        var host = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if host.hasPrefix("["),
           let closingBracketIndex = host.firstIndex(of: "]") {
            host = String(host[host.index(after: host.startIndex)..<closingBracketIndex])
        } else if let colonIndex = host.firstIndex(of: ":"), !host.contains("::") {
            host = String(host[..<colonIndex])
        }

        return host.isEmpty ? nil : host
    }

    private static func consumesValue(for argument: String) -> Bool {
        guard argument.first == "-", argument.count >= 2 else { return false }
        guard let option = argument.dropFirst().first else { return false }
        return optionsRequiringValue.contains(option)
    }

    private static func inlineOptionValue(in argument: String) -> String? {
        guard argument.first == "-", argument.count >= 3 else { return nil }
        let option = argument.dropFirst()
        guard let first = option.first, optionsRequiringValue.contains(first) else { return nil }
        let remainder = option.dropFirst()
        return remainder.isEmpty ? nil : String(remainder)
    }

    private static func explicitUser(in arguments: [String]) -> String? {
        guard arguments.count > 1 else { return nil }

        var index = 1
        while index < arguments.count {
            let argument = arguments[index]
            if argument == "--" { break }

            if argument == "-l" {
                let valueIndex = index + 1
                return valueIndex < arguments.count ? normalizedUser(arguments[valueIndex]) : nil
            }

            if argument.hasPrefix("-l"), argument.count > 2 {
                return normalizedUser(String(argument.dropFirst(2)))
            }

            if argument == "-o" {
                let valueIndex = index + 1
                if valueIndex < arguments.count,
                   let user = userOptionValue(in: arguments[valueIndex]) {
                    return user
                }
                index += 2
                continue
            }

            if argument.hasPrefix("-o"), argument.count > 2,
               let user = userOptionValue(in: String(argument.dropFirst(2))) {
                return user
            }

            index += 1
        }

        return nil
    }

    private static func userOptionValue(in option: String) -> String? {
        let parts = option.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
        guard parts.count == 2,
              parts[0].trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "user" else {
            return nil
        }

        return normalizedUser(String(parts[1]))
    }
}
