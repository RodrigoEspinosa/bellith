import XCTest
@testable import Bellith

final class CommandOutputLocatorTests: XCTestCase {
    func testScreenRowCountFindsBoundary() {
        for count in [0, 1, 2, 3, 24, 25, 1000, 10_001] {
            var probes = 0
            let result = CommandOutputLocator.screenRowCount { row in
                probes += 1
                return row < count
            }
            XCTAssertEqual(result, count)
            XCTAssertLessThan(probes, 64)
        }
    }

    func testRowsAboveCursorWhenOutputScrolledScreen() {
        // Submitted on the last viewport row; 40 rows of output pushed the
        // screen up and the new prompt is back on the last row.
        let anchor = CommandOutputLocator.Anchor(screenRows: 100, cursorY: 480)
        let rows = CommandOutputLocator.rowsAboveCursor(
            anchor: anchor,
            currentScreenRows: 140,
            currentCursorY: 480,
            cellHeight: 20
        )
        XCTAssertEqual(rows, 40)
    }

    func testRowsAboveCursorWhenOutputFitsInViewport() {
        // Screen did not grow; the cursor moved down 5 rows.
        let anchor = CommandOutputLocator.Anchor(screenRows: 24, cursorY: 100)
        let rows = CommandOutputLocator.rowsAboveCursor(
            anchor: anchor,
            currentScreenRows: 24,
            currentCursorY: 200,
            cellHeight: 20
        )
        XCTAssertEqual(rows, 5)
    }

    func testRowsAboveCursorRejectsAnchorBelowCursor() {
        // A clear moved the cursor above where the command was submitted.
        let anchor = CommandOutputLocator.Anchor(screenRows: 24, cursorY: 400)
        let rows = CommandOutputLocator.rowsAboveCursor(
            anchor: anchor,
            currentScreenRows: 24,
            currentCursorY: 20,
            cellHeight: 20
        )
        XCTAssertNil(rows)
    }

    func testCandidateOffsetsStopBeforeSubmittedLine() {
        XCTAssertEqual(
            CommandOutputLocator.candidateOffsets(rowsAboveSubmit: 4, visibleRowsAboveCursor: 30),
            [1, 2, 3]
        )
    }

    func testCandidateOffsetsAreEmptyWhenCommandHadNoRoomForOutput() {
        XCTAssertEqual(
            CommandOutputLocator.candidateOffsets(rowsAboveSubmit: 1, visibleRowsAboveCursor: 30),
            []
        )
    }

    func testCandidateOffsetsLimitedToViewportWithoutAnchor() {
        XCTAssertEqual(
            CommandOutputLocator.candidateOffsets(rowsAboveSubmit: nil, visibleRowsAboveCursor: 3),
            [1, 2, 3]
        )
    }
}
