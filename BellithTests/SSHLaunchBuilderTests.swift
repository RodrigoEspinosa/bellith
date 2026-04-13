import XCTest
@testable import Bellith

final class SSHLaunchBuilderTests: XCTestCase {
    func testBuildsMinimalSSHCommand() {
        let profile = SSHProfile(name: "App", host: "app.example.com", user: "deploy")
        XCTAssertEqual(SSHLaunchBuilder.command(for: profile), "ssh 'deploy@app.example.com'")
    }

    func testBuildsMoshCommandWithFallbackAndBootstrap() {
        let profile = SSHProfile(
            name: "Prod",
            host: "prod.example.com",
            user: "ops",
            transport: .mosh,
            port: 2222,
            identityPath: "~/.ssh/prod",
            proxyJump: "bastion",
            defaultDirectory: "/srv/app",
            startupCommand: "bin/deploy",
            sessionBootstrap: .tmux,
            sessionName: "prod"
        )

        let command = SSHLaunchBuilder.command(for: profile)
        XCTAssertTrue(command.contains("if command -v mosh >/dev/null 2>&1; then"))
        XCTAssertTrue(command.contains("ssh -p 2222 -i '~/.ssh/prod' -J 'bastion' 'ops@prod.example.com' -- sh -lc 'command -v mosh-server >/dev/null 2>&1'"))
        XCTAssertTrue(command.contains("mosh --ssh='ssh -p 2222 -i '\\''~/.ssh/prod'\\'' -J '\\''bastion'\\''' 'ops@prod.example.com' sh -lc 'cd '\\''/srv/app'\\'' && tmux attach -t '\\''prod'\\'' || tmux new -s '\\''prod'\\'' && bin/deploy'"))
        XCTAssertTrue(command.contains("printf '%s\\n' 'Bellith: mosh is not installed locally. Falling back to SSH.'"))
        XCTAssertTrue(command.contains("printf '%s\\n' 'Bellith: mosh-server is unavailable on ops@prod.example.com. Falling back to SSH.'"))
        XCTAssertTrue(command.contains("ssh -p 2222 -i '~/.ssh/prod' -J 'bastion' 'ops@prod.example.com' -- sh -lc 'cd '\\''/srv/app'\\'' && tmux attach -t '\\''prod'\\'' || tmux new -s '\\''prod'\\'' && bin/deploy'"))
        XCTAssertFalse(command.contains("mosh --ssh='ssh -p 2222 -i '\\''~/.ssh/prod'\\'' -J '\\''bastion'\\''' 'ops@prod.example.com' -- sh -lc"))
    }

    func testBuildsMoshCommandWithoutRemoteBootstrapCommand() {
        let profile = SSHProfile(name: "App", host: "app.example.com", user: "deploy", transport: .mosh)

        let command = SSHLaunchBuilder.command(for: profile)
        XCTAssertTrue(command.contains("mosh --ssh='ssh' 'deploy@app.example.com'"))
        XCTAssertFalse(command.contains("mosh --ssh='ssh' 'deploy@app.example.com' sh -lc"))
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
            sessionBootstrap: .tmux,
            sessionName: "prod"
        )

        XCTAssertEqual(
            SSHLaunchBuilder.command(for: profile),
            "ssh -p 2222 -i '~/.ssh/prod' -J 'bastion' 'ops@prod.example.com' -- sh -lc 'cd '\\''/srv/app'\\'' && tmux attach -t '\\''prod'\\'' || tmux new -s '\\''prod'\\'' && bin/deploy'"
        )
    }

    func testBuildsSSHCommandWithZellijBootstrap() {
        let profile = SSHProfile(
            name: "Prod",
            host: "prod.example.com",
            user: "ops",
            defaultDirectory: "/srv/app",
            sessionBootstrap: .zellij,
            sessionName: "prod"
        )

        XCTAssertEqual(
            SSHLaunchBuilder.command(for: profile),
            "ssh 'ops@prod.example.com' -- sh -lc 'cd '\\''/srv/app'\\'' && zellij options --session-name '\\''prod'\\'' --attach-to-session true'"
        )
    }
}
