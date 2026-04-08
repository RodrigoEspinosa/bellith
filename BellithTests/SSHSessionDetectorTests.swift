import XCTest
@testable import Bellith

final class SSHSessionDetectorTests: XCTestCase {
    func testDestinationArgumentSkipsSSHOptions() {
        let arguments = [
            "/usr/bin/ssh",
            "-p", "2222",
            "-i", "~/.ssh/prod",
            "-J", "bastion",
            "deploy@app.example.com",
            "tail", "-f", "/var/log/app.log"
        ]

        XCTAssertEqual(SSHSessionDetector.destinationArgument(in: arguments), "deploy@app.example.com")
    }

    func testContextParsesExplicitUserOption() {
        let context = SSHSessionDetector.context(
            forDestination: "prod.example.com",
            arguments: ["ssh", "-l", "deploy", "prod.example.com"]
        )

        XCTAssertEqual(
            context,
            TerminalContext(source: .sshCommand, host: "prod.example.com", user: "deploy")
        )
    }

    func testDetectedContextUsesForegroundSSHProcess() {
        let tree = TerminalProcessInfo(
            pid: 100,
            ppid: 1,
            name: "zsh",
            cpuUsage: 0,
            memoryBytes: 0,
            startTime: nil,
            children: [
                TerminalProcessInfo(
                    pid: 101,
                    ppid: 100,
                    name: "ssh",
                    cpuUsage: 0,
                    memoryBytes: 0,
                    startTime: nil
                )
            ]
        )

        let context = SSHSessionDetector.detectedContext(in: tree, shellPID: 100) { pid in
            if pid == 101 {
                return ["ssh", "-p2222", "ops@app.example.com"]
            }
            return []
        }

        XCTAssertEqual(
            context,
            TerminalContext(source: .sshCommand, host: "app.example.com", user: "ops")
        )
    }

    func testDetectedContextIgnoresLocalForegroundProcess() {
        let tree = TerminalProcessInfo(
            pid: 200,
            ppid: 1,
            name: "zsh",
            cpuUsage: 0,
            memoryBytes: 0,
            startTime: nil,
            children: [
                TerminalProcessInfo(
                    pid: 201,
                    ppid: 200,
                    name: "vim",
                    cpuUsage: 0,
                    memoryBytes: 0,
                    startTime: nil
                )
            ]
        )

        let context = SSHSessionDetector.detectedContext(in: tree, shellPID: 200) { _ in
            XCTFail("Argument lookup should not run for non-SSH foreground processes")
            return []
        }

        XCTAssertNil(context)
    }
}
