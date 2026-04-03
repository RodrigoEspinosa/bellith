import AppKit

/// A binary-tree split pane container. Each node is either a leaf (hosting a content view)
/// or a branch with two children separated by a draggable divider.
final class SplitPaneView: NSView {
    enum Orientation { case horizontal, vertical }

    // Leaf state
    private(set) var contentView: NSView?

    // Branch state
    private(set) var orientation: Orientation?
    private(set) var first: SplitPaneView?
    private(set) var second: SplitPaneView?
    private var divider: SplitDividerView?
    private var ratio: CGFloat = 0.5

    /// Called when focus moves to a leaf's content view.
    var onFocusChanged: ((NSView) -> Void)?

    // MARK: - Init

    init(content: NSView) {
        super.init(frame: .zero)
        wantsLayer = true
        self.contentView = content
        addSubview(content)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    var isLeaf: Bool { contentView != nil }

    // MARK: - Splitting

    /// Split this leaf into two panes. Returns the new (second) leaf's content slot.
    @discardableResult
    func split(orientation: Orientation, newContent: NSView) -> SplitPaneView {
        guard isLeaf, let existing = contentView else {
            // Already a branch — find the focused leaf and split that
            let leaf = focusedLeaf ?? deepestLeaf
            return leaf.split(orientation: orientation, newContent: newContent)
        }

        // Convert from leaf to branch
        self.contentView = nil
        existing.removeFromSuperview()

        self.orientation = orientation
        self.ratio = 0.5

        let firstChild = SplitPaneView(content: existing)
        firstChild.onFocusChanged = onFocusChanged
        let secondChild = SplitPaneView(content: newContent)
        secondChild.onFocusChanged = onFocusChanged

        self.first = firstChild
        self.second = secondChild
        addSubview(firstChild)
        addSubview(secondChild)

        let div = SplitDividerView(orientation: orientation)
        div.onDrag = { [weak self] delta in self?.handleDividerDrag(delta) }
        self.divider = div
        addSubview(div)

        needsLayout = true
        return secondChild
    }

    /// Remove a child leaf and collapse this branch back to a single pane.
    func removeChild(_ child: SplitPaneView) {
        guard !isLeaf else { return }

        let remaining: SplitPaneView?
        if child === first {
            remaining = second
        } else if child === second {
            remaining = first
        } else {
            return
        }

        child.removeFromSuperview()
        divider?.removeFromSuperview()
        remaining?.removeFromSuperview()

        first = nil
        second = nil
        divider = nil
        orientation = nil

        if let remaining {
            if remaining.isLeaf, let content = remaining.contentView {
                remaining.contentView = nil
                content.removeFromSuperview()
                self.contentView = content
                addSubview(content)
            } else {
                // Absorb the remaining branch's children
                self.orientation = remaining.orientation
                self.ratio = remaining.ratio
                self.first = remaining.first
                self.second = remaining.second
                self.divider = remaining.divider

                remaining.first?.removeFromSuperview()
                remaining.second?.removeFromSuperview()
                remaining.divider?.removeFromSuperview()

                if let f = first { addSubview(f) }
                if let s = second { addSubview(s) }
                if let d = divider { addSubview(d) }
            }
        }

        needsLayout = true
    }

    // MARK: - Focus Tracking

    private weak var _focusedLeaf: SplitPaneView?

    var focusedLeaf: SplitPaneView? {
        get {
            if isLeaf { return self }
            return first?.focusedLeaf ?? second?.focusedLeaf
        }
    }

    var deepestLeaf: SplitPaneView {
        if isLeaf { return self }
        return first?.deepestLeaf ?? self
    }

    /// Collect all leaf content views.
    var allLeaves: [NSView] {
        if isLeaf, let c = contentView { return [c] }
        return (first?.allLeaves ?? []) + (second?.allLeaves ?? [])
    }

    /// Find the leaf containing a specific content view.
    func leaf(containing view: NSView) -> SplitPaneView? {
        if isLeaf && contentView === view { return self }
        return first?.leaf(containing: view) ?? second?.leaf(containing: view)
    }

    /// Find the parent branch of a given child.
    func parent(of child: SplitPaneView) -> SplitPaneView? {
        if first === child || second === child { return self }
        return first?.parent(of: child) ?? second?.parent(of: child)
    }

    // MARK: - Layout

    private let dividerThickness: CGFloat = 1
    private let dividerHitArea: CGFloat = 6

    override func layout() {
        super.layout()

        if isLeaf {
            contentView?.frame = bounds
            return
        }

        guard let orientation, let first, let second, let divider else { return }

        let divThick = dividerThickness

        switch orientation {
        case .vertical:
            let firstW = (bounds.width - divThick) * ratio
            first.frame = NSRect(x: 0, y: 0, width: firstW, height: bounds.height)
            divider.frame = NSRect(x: firstW, y: 0, width: divThick, height: bounds.height)
            second.frame = NSRect(x: firstW + divThick, y: 0,
                                  width: bounds.width - firstW - divThick, height: bounds.height)

        case .horizontal:
            let firstH = (bounds.height - divThick) * ratio
            // First pane at top (higher y in flipped coords? No — AppKit is bottom-up)
            // "horizontal split" = top/bottom, so first=bottom, second=top
            first.frame = NSRect(x: 0, y: 0, width: bounds.width, height: firstH)
            divider.frame = NSRect(x: 0, y: firstH, width: bounds.width, height: divThick)
            second.frame = NSRect(x: 0, y: firstH + divThick,
                                  width: bounds.width, height: bounds.height - firstH - divThick)
        }
    }

    // MARK: - Divider Dragging

    private func handleDividerDrag(_ delta: CGFloat) {
        guard let orientation else { return }

        let total: CGFloat
        switch orientation {
        case .vertical: total = bounds.width
        case .horizontal: total = bounds.height
        }

        guard total > 0 else { return }

        let newRatio = ratio + delta / total
        ratio = min(0.85, max(0.15, newRatio))
        needsLayout = true
    }
}

// MARK: - Divider View

private final class SplitDividerView: NSView {
    let orientation: SplitPaneView.Orientation
    var onDrag: ((CGFloat) -> Void)?
    private var lastDragLocation: CGFloat = 0

    init(orientation: SplitPaneView.Orientation) {
        self.orientation = orientation
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = NSColor(white: 1.0, alpha: 0.06).cgColor
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func resetCursorRects() {
        let cursor: NSCursor = orientation == .vertical ? .resizeLeftRight : .resizeUpDown
        // Expand the hit area beyond the visible divider
        let hitRect: NSRect
        switch orientation {
        case .vertical:
            hitRect = bounds.insetBy(dx: -3, dy: 0)
        case .horizontal:
            hitRect = bounds.insetBy(dx: 0, dy: -3)
        }
        addCursorRect(hitRect, cursor: cursor)
    }

    override func mouseDown(with event: NSEvent) {
        let loc = convert(event.locationInWindow, from: nil)
        lastDragLocation = orientation == .vertical ? loc.x : loc.y
    }

    override func mouseDragged(with event: NSEvent) {
        let loc = convert(event.locationInWindow, from: nil)
        let current = orientation == .vertical ? loc.x : loc.y
        let delta = current - lastDragLocation
        lastDragLocation = current
        onDrag?(delta)
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        // Expand hit test area for easier grabbing
        let expanded: NSRect
        switch orientation {
        case .vertical:
            expanded = frame.insetBy(dx: -3, dy: 0)
        case .horizontal:
            expanded = frame.insetBy(dx: 0, dy: -3)
        }
        if expanded.contains(point) { return self }
        return nil
    }
}
