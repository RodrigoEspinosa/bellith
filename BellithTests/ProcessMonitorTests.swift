import XCTest
@testable import Bellith

final class ProcessMonitorTests: XCTestCase {
    func testInfoForCurrentProcess() {
        let pid = ProcessInfo.processInfo.processIdentifier
        let info = ProcessMonitor.info(for: pid)
        XCTAssertNotNil(info, "Should be able to get info for current process")
        XCTAssertEqual(info?.pid, pid)
        XCTAssertFalse(info?.name.isEmpty ?? true, "Process name should not be empty")
        XCTAssertGreaterThan(info?.memoryBytes ?? 0, 0, "Memory should be positive")
    }

    func testProcessTreeForCurrentProcess() {
        let pid = ProcessInfo.processInfo.processIdentifier
        let tree = ProcessMonitor.processTree(rootPID: pid)
        XCTAssertNotNil(tree, "Should be able to build process tree for current process")
        XCTAssertEqual(tree?.pid, pid)
    }

    func testAllDescendantsIncludesSelf() {
        let pid = ProcessInfo.processInfo.processIdentifier
        let descendants = ProcessMonitor.allDescendants(of: pid)
        XCTAssertTrue(descendants.contains(pid), "Descendants should include the root PID")
    }

    func testWorkingDirectoryForCurrentProcess() {
        let pid = ProcessInfo.processInfo.processIdentifier
        let cwd = ProcessMonitor.workingDirectory(for: pid)
        XCTAssertNotNil(cwd, "Should be able to read CWD for current process")
        XCTAssertFalse(cwd?.isEmpty ?? true, "CWD should not be empty")
    }

    // MARK: - Formatting

    func testFormatBytesKB() {
        XCTAssertEqual(ProcessMonitor.formatBytes(512 * 1024), "512 KB")
    }

    func testFormatBytesMB() {
        let result = ProcessMonitor.formatBytes(150 * 1024 * 1024)
        XCTAssertTrue(result.contains("MB"), "Expected MB but got: \(result)")
    }

    func testFormatBytesGB() {
        let result = ProcessMonitor.formatBytes(2 * 1024 * 1024 * 1024)
        XCTAssertTrue(result.contains("GB"), "Expected GB but got: \(result)")
    }

    func testFormatUptimeSeconds() {
        let start = Date().addingTimeInterval(-30)
        let result = ProcessMonitor.formatUptime(from: start)
        XCTAssertTrue(result.hasSuffix("s"), "Expected seconds format but got: \(result)")
    }

    func testFormatUptimeMinutes() {
        let start = Date().addingTimeInterval(-300)
        let result = ProcessMonitor.formatUptime(from: start)
        XCTAssertTrue(result.hasSuffix("m"), "Expected minutes format but got: \(result)")
    }

    func testFormatUptimeHours() {
        let start = Date().addingTimeInterval(-7200)
        let result = ProcessMonitor.formatUptime(from: start)
        XCTAssertTrue(result.hasSuffix("h"), "Expected hours format but got: \(result)")
    }

    func testFormatUptimeNilDate() {
        let result = ProcessMonitor.formatUptime(from: nil)
        XCTAssertEqual(result, "\u{2014}")
    }
}
