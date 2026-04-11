import Foundation

enum SSHLaunchBuilder {
    static func command(for profile: SSHProfile) -> String {
        let profile = profile.sanitized()
        var parts = ["ssh"]

        if profile.port != 22 {
            parts.append("-p")
            parts.append("\(profile.port)")
        }

        if !profile.identityPath.isEmpty {
            parts.append("-i")
            parts.append(shellQuoted(profile.identityPath))
        }

        if !profile.proxyJump.isEmpty {
            parts.append("-J")
            parts.append(shellQuoted(profile.proxyJump))
        }

        parts.append(shellQuoted(profile.destination))

        if let remoteCommand = remoteCommand(for: profile) {
            parts.append("--")
            parts.append("sh")
            parts.append("-lc")
            parts.append(shellQuoted(remoteCommand))
        }

        return parts.joined(separator: " ")
    }

    private static func remoteCommand(for profile: SSHProfile) -> String? {
        var commands: [String] = []

        if !profile.defaultDirectory.isEmpty {
            commands.append("cd \(shellQuoted(profile.defaultDirectory))")
        }

        if let multiplexerCommand = sessionBootstrapCommand(for: profile) {
            commands.append(multiplexerCommand)
        }

        if !profile.startupCommand.isEmpty {
            commands.append(profile.startupCommand)
        }

        guard !commands.isEmpty else { return nil }
        return commands.joined(separator: " && ")
    }

    private static func sessionBootstrapCommand(for profile: SSHProfile) -> String? {
        SessionBootstrapCommandBuilder.command(
            for: profile.sessionBootstrap,
            sessionName: profile.sessionName
        )
    }

    private static func shellQuoted(_ value: String) -> String { SessionBootstrapCommandBuilder.shellQuoted(value) }
}
