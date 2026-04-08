import XCTest
@testable import Bellith

final class SSHLaunchBuilderTests: XCTestCase {
    func testBuildsMinimalSSHCommand() {
        let profile = SSHProfile(name: "App", host: "app.example.com", user: "deploy")
        XCTAssertEqual(SSHLaunchBuilder.command(for: profile), "ssh 'deploy@app.example.com'")
    }

    func testBuildsSSHCommandWithRemoteBootstrap() {
        let profile = SSHProfile(
            name: "Prod",
            host: "prod.example.com",
            user: "ops",
            port: 2222,
            identityPath: "~/.ssh/prod",
            proxyJump: "bastion",
            defaultDirectory: "/srv/app",
            startupCommand: "bin/deploy",
            tmuxSession: "prod"
        )

        XCTAssertEqual(
            SSHLaunchBuilder.command(for: profile),
            "ssh -p 2222 -i '~/.ssh/prod' -J 'bastion' 'ops@prod.example.com' -- sh -lc 'cd '\\''/srv/app'\\'' && tmux attach -t '\\''prod'\\'' || tmux new -s '\\''prod'\\'' && bin/deploy'"
        )
    }
}
