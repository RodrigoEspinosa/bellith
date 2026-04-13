import Foundation

enum SSHLaunchBuilder {
    static func command(for profile: SSHProfile, availableProfiles: [SSHProfile] = SSHProfileStore.shared.profiles) -> String {
        let profile = profile.sanitized()

        switch profile.transport {
        case .ssh:
            return sshCommand(for: profile, availableProfiles: availableProfiles)
        case .mosh:
            return moshCommand(for: profile, availableProfiles: availableProfiles)
        }
    }

    private static func sshCommand(
        for profile: SSHProfile,
        availableProfiles: [SSHProfile],
        remoteCommandOverride: String? = nil
    ) -> String {
        var parts = sshTransportParts(for: profile, availableProfiles: availableProfiles)
        parts.append(shellQuoted(profile.destination))

        if let remoteCommand = remoteCommandOverride ?? remoteCommand(for: profile) {
            parts.append("--")
            parts.append("sh")
            parts.append("-lc")
            parts.append(shellQuoted(remoteCommand))
        }

        return parts.joined(separator: " ")
    }

    private static func moshCommand(for profile: SSHProfile, availableProfiles: [SSHProfile]) -> String {
        let fallbackSSHCommand = sshCommand(for: profile, availableProfiles: availableProfiles)
        let remoteCheckCommand = sshCommand(
            for: profile,
            availableProfiles: availableProfiles,
            remoteCommandOverride: "command -v mosh-server >/dev/null 2>&1"
        )
        let remoteLaunchCommand = moshLaunchCommand(for: profile, availableProfiles: availableProfiles)
        let localFallbackMessage = "Bellith: mosh is not installed locally. Falling back to SSH."
        let remoteFallbackMessage = "Bellith: mosh-server is unavailable on \(profile.destination). Falling back to SSH."

        return """
        if command -v mosh >/dev/null 2>&1; then
          if \(remoteCheckCommand); then
            \(remoteLaunchCommand)
          else
            printf '%s\\n' \(shellQuoted(remoteFallbackMessage))
            \(fallbackSSHCommand)
          fi
        else
          printf '%s\\n' \(shellQuoted(localFallbackMessage))
          \(fallbackSSHCommand)
        fi
        """
    }

    private static func moshLaunchCommand(for profile: SSHProfile, availableProfiles: [SSHProfile]) -> String {
        var parts = [
            "mosh",
            "--ssh=\(shellQuoted(sshTransportCommand(for: profile, availableProfiles: availableProfiles)))",
            shellQuoted(profile.destination),
        ]

        if let remoteCommand = remoteCommand(for: profile) {
            parts.append("sh")
            parts.append("-lc")
            parts.append(shellQuoted(remoteCommand))
        }

        return parts.joined(separator: " ")
    }

    private static func sshTransportCommand(for profile: SSHProfile, availableProfiles: [SSHProfile]) -> String {
        sshTransportParts(for: profile, availableProfiles: availableProfiles).joined(separator: " ")
    }

    private static func sshTransportParts(for profile: SSHProfile, availableProfiles: [SSHProfile]) -> [String] {
        var parts = ["ssh"]

        if profile.port != 22 {
            parts.append("-p")
            parts.append("\(profile.port)")
        }

        if !profile.identityPath.isEmpty {
            parts.append("-i")
            parts.append(shellQuoted(profile.identityPath))
        }

        let proxyJumpArgument = profile.resolvedProxyJumpArgument(using: availableProfiles)
        if !proxyJumpArgument.isEmpty {
            parts.append("-J")
            parts.append(shellQuoted(proxyJumpArgument))
        }

        return parts
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
