import XCTest
@testable import Bellith

final class ToolActivityMonitorTests: XCTestCase {
    func testPathFilterSkipsKnownNoiseDirectories() {
        XCTAssertTrue(ToolActivityPathFilter.shouldSkipDirectory(named: ".git"))
        XCTAssertTrue(ToolActivityPathFilter.shouldSkipDirectory(named: "node_modules"))
        XCTAssertFalse(ToolActivityPathFilter.shouldSkipDirectory(named: "Sources"))
    }

    func testPathFilterIgnoresCacheLikePaths() {
        XCTAssertFalse(ToolActivityPathFilter.shouldIncludeFile(at: "/tmp/session.log"))
        XCTAssertFalse(ToolActivityPathFilter.shouldIncludeFile(at: "/Users/test/.cache/tool/output.json"))
        XCTAssertTrue(ToolActivityPathFilter.shouldIncludeFile(at: "/Users/test/Projects/bellith/README.md"))
    }
}
