import AppKit

/// Thin vertical strip along the right edge of a terminal surface that shows
/// a zoomed-out representation of the scrollback. Users can click to jump or
/// drag to scrub the viewport to any position.
final class ScrollbackMinimapView: NSView {
    enum MarkKind {
        case prompt
        case error
        case searchHit
    }

    struct Mark {
        let row: Int
        let kind: MarkKind
    }

    static let defaultWidth: CGFloat = 14

    var onScrollToRow: ((Int) -> Void)?

    private var total: Int = 0
    private var offset: Int = 0
    private var len: Int = 0
    private var marks: [Mark] = []
    private var searchHitRow: Int?
    private var hovering = false
    private var themeObserver: NSObjectProtocol?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        setAccessibilityRole(.slider)
        setAccessibilityLabel("Scrollback Minimap")
        themeObserver = NotificationCenter.default.addObserver(
            forName: ThemeManager.didChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            self?.needsDisplay = true
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    deinit {
        if let themeObserver {
            NotificationCenter.default.removeObserver(themeObserver)
        }
    }

    override var isFlipped: Bool { false }

    override func updateTrackingAreas() {
        trackingAreas.forEach { removeTrackingArea($0) }
        addTrackingArea(NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
            owner: self,
            userInfo: nil
        ))
    }

    override func mouseEntered(with event: NSEvent) {
        hovering = true
        needsDisplay = true
    }

    override func mouseExited(with event: NSEvent) {
        hovering = false
        needsDisplay = true
    }

    // MARK: - State

    func updateScrollbar(total: Int, offset: Int, len: Int) {
        let clampedTotal = max(0, total)
        let clampedLen = max(0, min(len, clampedTotal))
        let clampedOffset = max(0, min(offset, max(0, clampedTotal - clampedLen)))
        guard total != self.total || offset != self.offset || len != self.len else { return }
        self.total = clampedTotal
        self.offset = clampedOffset
        self.len = clampedLen
        needsDisplay = true
    }

    func appendMark(row: Int, kind: MarkKind) {
        marks.append(Mark(row: row, kind: kind))
        if marks.count > 2000 {
            marks.removeFirst(marks.count - 2000)
        }
        needsDisplay = true
    }

    func clearMarks() {
        guard !marks.isEmpty || searchHitRow != nil else { return }
        marks.removeAll()
        searchHitRow = nil
        needsDisplay = true
    }

    func setSearchHit(row: Int?) {
        guard searchHitRow != row else { return }
        searchHitRow = row
        needsDisplay = true
    }

    var hasScrollback: Bool { total > len && total > 0 }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        let r = bounds

        // Translucent track
        let trackAlpha: CGFloat = hovering ? 0.22 : 0.12
        ctx.setFillColor(Theme.border.withAlphaComponent(trackAlpha).cgColor)
        let trackInset: CGFloat = 3
        let trackRect = r.insetBy(dx: trackInset, dy: 2)
        ctx.addPath(CGPath(roundedRect: trackRect, cornerWidth: 2, cornerHeight: 2, transform: nil))
        ctx.fillPath()

        guard total > 0, len > 0 else { return }

        let travelHeight = r.height
        let rowPerPixel = CGFloat(total) / travelHeight

        // Marks first, so the thumb paints over them.
        for mark in marks {
            drawMark(mark, in: ctx, travelHeight: travelHeight)
        }
        if let row = searchHitRow {
            drawSearchHit(row: row, in: ctx, travelHeight: travelHeight)
        }

        // Viewport thumb
        let thumbHeight = max(24, CGFloat(len) / max(1, rowPerPixel))
        let usableHeight = travelHeight - thumbHeight
        let progress = total > len ? CGFloat(offset) / CGFloat(total - len) : 0
        let thumbY = usableHeight - (progress * usableHeight)
        let thumbRect = NSRect(
            x: trackInset,
            y: max(0, thumbY),
            width: r.width - 2 * trackInset,
            height: thumbHeight
        )
        let thumbColor = hovering
            ? Theme.accent.withAlphaComponent(0.9)
            : Theme.accent.withAlphaComponent(0.55)
        ctx.setFillColor(thumbColor.cgColor)
        ctx.addPath(CGPath(roundedRect: thumbRect, cornerWidth: 3, cornerHeight: 3, transform: nil))
        ctx.fillPath()
    }

    private func drawMark(_ mark: Mark, in ctx: CGContext, travelHeight: CGFloat) {
        guard total > 0 else { return }
        let progress = CGFloat(mark.row) / CGFloat(total)
        // flipped: row 0 (oldest) is at top of strip
        let y = travelHeight - progress * travelHeight
        let (color, height): (NSColor, CGFloat) = {
            switch mark.kind {
            case .prompt: return (Theme.textMuted.withAlphaComponent(0.55), 1.2)
            case .error: return (Theme.destructive.withAlphaComponent(0.85), 2.0)
            case .searchHit: return (Theme.accent.withAlphaComponent(0.85), 1.5)
            }
        }()
        ctx.setFillColor(color.cgColor)
        ctx.fill(NSRect(x: 0, y: y - height / 2, width: bounds.width, height: height))
    }

    private func drawSearchHit(row: Int, in ctx: CGContext, travelHeight: CGFloat) {
        guard total > 0 else { return }
        let progress = CGFloat(row) / CGFloat(total)
        let y = travelHeight - progress * travelHeight
        let height: CGFloat = 3
        ctx.setFillColor(Theme.accent.cgColor)
        ctx.fill(NSRect(x: 0, y: y - height / 2, width: bounds.width, height: height))
    }

    // MARK: - Mouse

    override func mouseDown(with event: NSEvent) {
        guard total > len else { return }
        let point = convert(event.locationInWindow, from: nil)
        emitScroll(toPoint: point)
    }

    override func mouseDragged(with event: NSEvent) {
        guard total > len else { return }
        let point = convert(event.locationInWindow, from: nil)
        emitScroll(toPoint: point)
    }

    private func emitScroll(toPoint point: NSPoint) {
        let travelHeight = bounds.height
        guard travelHeight > 0 else { return }
        // Flip so top of strip = oldest row = row 0
        let clampedY = max(0, min(travelHeight, point.y))
        let fromTop = travelHeight - clampedY
        let progress = fromTop / travelHeight
        let maxOffset = max(0, total - len)
        var target = Int((progress * CGFloat(maxOffset)).rounded())
        target = max(0, min(target, maxOffset))
        onScrollToRow?(target)
    }

    // MARK: - Cursor

    override func resetCursorRects() {
        discardCursorRects()
        addCursorRect(bounds, cursor: .pointingHand)
    }
}
