import Foundation

/// Row math for locating the most recent command's output in a terminal
/// surface. Ghostty can select an output block from any row inside it, but
/// only knows rows by their semantic shell-integration marks, so Bellith
/// remembers where the last command was submitted and probes rows between
/// that line and the current cursor.
enum CommandOutputLocator {
    /// Where the cursor sat when a command was submitted with Return.
    struct Anchor: Equatable {
        /// Total rows in the screen (scrollback + active area) at submit time.
        let screenRows: Int
        /// Cursor bottom edge in viewport points, as reported by Ghostty.
        let cursorY: Double
    }

    /// Counts the rows in a screen by probing for the first missing row.
    /// `exists` must be monotonic: true for every row below the count and
    /// false for every row at or above it.
    static func screenRowCount(exists: (Int) -> Bool) -> Int {
        guard exists(0) else { return 0 }

        // Gallop to an upper bound, then binary search the boundary.
        var low = 0
        var high = 1
        while exists(high) {
            low = high
            high *= 2
        }

        while high - low > 1 {
            let mid = low + (high - low) / 2
            if exists(mid) { low = mid } else { high = mid }
        }
        return low + 1
    }

    /// How many rows above the current cursor line the submitted command line
    /// now sits, or nil when the anchor cannot be related to the current screen
    /// (for example after a clear or a switch between primary and alt screens).
    static func rowsAboveCursor(
        anchor: Anchor,
        currentScreenRows: Int,
        currentCursorY: Double,
        cellHeight: Double
    ) -> Int? {
        guard cellHeight > 0 else { return nil }
        let addedRows = currentScreenRows - anchor.screenRows
        let cursorShift = Int(((currentCursorY - anchor.cursorY) / cellHeight).rounded())
        let rows = addedRows + cursorShift
        return rows > 0 ? rows : nil
    }

    /// Row offsets above the cursor to probe for command output, nearest
    /// first. Output usually ends just above the prompt, so scanning upward
    /// finds it after skipping the prompt's own lines.
    ///
    /// - Parameters:
    ///   - rowsAboveSubmit: Distance from the cursor to the submitted command
    ///     line, when known. Rows at or beyond it belong to older commands.
    ///   - visibleRowsAboveCursor: Rows between the cursor and the top of the
    ///     viewport; Ghostty can only hit-test visible rows.
    static func candidateOffsets(rowsAboveSubmit: Int?, visibleRowsAboveCursor: Int) -> [Int] {
        var limit = max(0, visibleRowsAboveCursor)
        if let rowsAboveSubmit {
            limit = min(limit, rowsAboveSubmit - 1)
        }
        guard limit >= 1 else { return [] }
        return Array(1...limit)
    }
}
