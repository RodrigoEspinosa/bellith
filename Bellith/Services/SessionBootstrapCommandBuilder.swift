import Foundation

enum SessionBootstrapCommandBuilder {
    static func command(for bootstrap: SSHSessionBootstrap, sessionName: String) -> String? {
        switch bootstrap {
        case .none:
            return nil
        case .tmux:
            guard !sessionName.isEmpty else { return "tmux" }
            let session = shellQuoted(sessionName)
            return "tmux attach -t \(session) || tmux new -s \(session)"
        case .zellij:
            guard !sessionName.isEmpty else { return "zellij" }
            let session = shellQuoted(sessionName)
            return "zellij options --session-name \(session) --attach-to-session true"
        }
    }

    static func shellQuoted(_ value: String) -> String {
        let escaped = value.replacingOccurrences(of: "'", with: "'\\''")
        return "'\(escaped)'"
    }
}
