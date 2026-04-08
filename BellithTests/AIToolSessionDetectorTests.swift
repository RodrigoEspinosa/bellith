import XCTest
@testable import Bellith

final class AIToolSessionDetectorTests: XCTestCase {
    func testExtractModelPrefersNamedFlag() {
        let model = AIToolSessionDetector.extractModel(
            from: ["claude", "--model", "sonnet"]
        )

        XCTAssertEqual(model, "Sonnet")
    }

    func testPresentationHighlightsClaudeCodeSessions() {
        let startedAt = Date().addingTimeInterval(-120)
        let process = TerminalProcessInfo(
            pid: 42,
            ppid: 1,
            name: "claude",
            cpuUsage: 0,
            memoryBytes: 0,
            startTime: startedAt
        )

        let presentation = AIToolSessionDetector.presentation(for: process) { _ in
            ["claude", "--model=sonnet"]
        }

        XCTAssertEqual(presentation?.style, .tool)
        XCTAssertEqual(presentation?.iconName, "sparkles.rectangle.stack")
        XCTAssertTrue(presentation?.text.contains("Claude Code") ?? false)
        XCTAssertTrue(presentation?.text.contains("Sonnet") ?? false)
    }

    func testPresentationFallsBackToStandardProcessDisplay() {
        let process = TerminalProcessInfo(
            pid: 7,
            ppid: 1,
            name: "vim",
            cpuUsage: 0,
            memoryBytes: 0,
            startTime: nil
        )

        let presentation = AIToolSessionDetector.presentation(for: process) { _ in [] }

        XCTAssertEqual(presentation, ForegroundProcessPresentation(text: "vim", iconName: "gearshape.fill", style: .standard))
    }
}
