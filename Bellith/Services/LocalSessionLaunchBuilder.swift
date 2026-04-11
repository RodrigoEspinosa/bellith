import Foundation

enum LocalSessionLaunchBuilder {
    static func makeSessionName() -> String {
        "bellith-\(UUID().uuidString.lowercased())"
    }

    static func command(
        bootstrap: SSHSessionBootstrap,
        sessionName: String?,
        workingDirectory: String?
    ) -> String? {
        guard bootstrap != .none else { return nil }

        let trimmedSessionName = trimmed(sessionName)
        guard !trimmedSessionName.isEmpty,
              let bootstrapCommand = SessionBootstrapCommandBuilder.command(
                  for: bootstrap,
                  sessionName: trimmedSessionName
              ) else {
            return nil
        }

        var commands: [String] = []
        let trimmedWorkingDirectory = trimmed(workingDirectory)
        if !trimmedWorkingDirectory.isEmpty {
            commands.append("cd \(SessionBootstrapCommandBuilder.shellQuoted(trimmedWorkingDirectory))")
        }
        commands.append(bootstrapCommand)
        return commands.joined(separator: " && ")
    }

    private static func trimmed(_ value: String?) -> String {
        value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }
}
