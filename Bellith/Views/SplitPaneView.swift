import AppKit

/// A binary-tree split pane container. Each node is either a leaf (hosting a content view)
/// or a branch with two children separated by a draggable divider.
final class SplitPaneView: NSView {
    enum Orientation { case horizontal, vertical }

    private enum Metrics {
        static let defaultSplitRatio: CGFloat = 0.5
        static let minSplitRatio: CGFloat = 0.15
        static let maxSplitRatio: CGFloat = 0.85
    }

    // Leaf state
    private(set) var contentView: NSView?

    // Branch state
    private(set) var orientation: Orientation?
    private(set) var first: SplitPaneView?
    private(set) var second: SplitPaneView?
    private var divider: SplitDividerView?
    private var ratio: CGFloat = 0.5

    var currentRatio: CGFloat { ratio }

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
        self.ratio = Metrics.defaultSplitRatio

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

    var focusedLeaf: SplitPaneView? {
        get {
            if isLeaf { return self }
            return first?.focusedLeaf ?? second?.focusedLeaf
        }
    }

    var deepestLeaf: SplitPaneView {
        if isLeaf { return self }
        return first?.deepestLeaf ?? second?.deepestLeaf ?? self
    }

    /// Collect all leaf content views.
    var allLeaves: [NSView] {
        if isLeaf, let c = contentView { return [c] }
        return (first?.allLeaves ?? []) + (second?.allLeaves ?? [])
    }

    /// Find the leaf containing a specific content view.
    func leaf(containing view: NSView) -> SplitPaneView? {
        if isLeaf, let contentView,
           contentView === view || view.isDescendant(of: contentView) {
            return self
        }
        return first?.leaf(containing: view) ?? second?.leaf(containing: view)
    }

    /// Find the parent branch of a given child.
    func parent(of child: SplitPaneView) -> SplitPaneView? {
        if first === child || second === child { return self }
        return first?.parent(of: child) ?? second?.parent(of: child)
    }

    // MARK: - Directional Navigation

    enum Direction { case up, down, left, right }

    /// Find the spatially adjacent leaf in the given direction from the leaf containing `view`.
    func adjacentLeaf(from view: NSView, direction: Direction) -> NSView? {
        guard let leaf = leaf(containing: view) else { return nil }
        return adjacentLeafNode(from: leaf, direction: direction)?.contentView
    }

    private func adjacentLeafNode(from leaf: SplitPaneView, direction: Direction) -> SplitPaneView? {
        // Walk up from `leaf` to find a branch whose orientation matches the direction axis
        // and where the leaf is on the side that has a neighbor in that direction.
        var current = leaf
        while let par = parent(of: current) {
            let axisMatches: Bool
            let canNavigate: Bool

            switch direction {
            case .left, .right:
                axisMatches = par.orientation == .vertical
                canNavigate = (direction == .right && current === par.first)
                           || (direction == .left && current === par.second)
            case .up, .down:
                axisMatches = par.orientation == .horizontal
                // AppKit coords: first = bottom, second = top
                canNavigate = (direction == .up && current === par.first)
                           || (direction == .down && current === par.second)
            }

            if axisMatches && canNavigate {
                // Walk into the other child's nearest edge
                let other = (current === par.first) ? par.second : par.first
                return nearestLeaf(in: other, edge: direction)
            }
            current = par
        }
        return nil
    }

    /// Find the nearest leaf on the specified edge of a subtree.
    private func nearestLeaf(in node: SplitPaneView?, edge: Direction) -> SplitPaneView? {
        guard let node else { return nil }
        if node.isLeaf { return node }

        switch edge {
        case .left:
            // Want the leftmost leaf: if vertical split, go first; otherwise either child
            if node.orientation == .vertical { return nearestLeaf(in: node.first, edge: edge) }
            return nearestLeaf(in: node.first, edge: edge) ?? nearestLeaf(in: node.second, edge: edge)
        case .right:
            if node.orientation == .vertical { return nearestLeaf(in: node.second, edge: edge) }
            return nearestLeaf(in: node.first, edge: edge) ?? nearestLeaf(in: node.second, edge: edge)
        case .down:
            // AppKit: first = bottom, second = top. "Down" = go to first (bottom)
            if node.orientation == .horizontal { return nearestLeaf(in: node.first, edge: edge) }
            return nearestLeaf(in: node.first, edge: edge) ?? nearestLeaf(in: node.second, edge: edge)
        case .up:
            if node.orientation == .horizontal { return nearestLeaf(in: node.second, edge: edge) }
            return nearestLeaf(in: node.first, edge: edge) ?? nearestLeaf(in: node.second, edge: edge)
        }
    }

    // MARK: - Resize

    /// Adjust the ratio of the nearest ancestor branch relevant to the given direction.
    /// Returns true if a resize was performed.
    @discardableResult
    func resizeFromLeaf(containing view: NSView, direction: Direction, delta: CGFloat, animated: Bool = false) -> Bool {
        guard let leaf = leaf(containing: view) else { return false }

        var current = leaf
        while let par = parent(of: current) {
            let axisMatches: Bool
            switch direction {
            case .left, .right: axisMatches = par.orientation == .vertical
            case .up, .down: axisMatches = par.orientation == .horizontal
            }

            if axisMatches {
                // Determine sign: growing toward second = positive ratio delta
                let sign: CGFloat
                switch direction {
                case .right, .up:
                    sign = (current === par.first) ? 1 : -1
                case .left, .down:
                    sign = (current === par.first) ? -1 : 1
                }
                par.adjustRatio(by: sign * delta, animated: animated)
                return true
            }
            current = par
        }
        return false
    }

    func adjustRatio(by delta: CGFloat, animated: Bool = false) {
        ratio = min(Metrics.maxSplitRatio, max(Metrics.minSplitRatio, ratio + delta))
        if animated {
            animateLayout(duration: Theme.animFast)
        } else {
            needsLayout = true
        }
    }

    /// Reset all split ratios to 0.5 recursively.
    func equalizeAll() {
        guard !isLeaf else { return }
        applyEqualRatios()
        animateLayout()
    }

    private func applyEqualRatios() {
        ratio = 0.5
        first?.applyEqualRatios()
        second?.applyEqualRatios()
    }

    /// Animate the split layout to reflect current ratios with smooth frame transitions.
    func animateLayout(duration: TimeInterval = Theme.animMedium) {
        guard !isLeaf else { return }
        guard let orientation, let first, let second, let divider else { return }

        let divThick = dividerThickness

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = duration
            ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.16, 1, 0.3, 1)

            switch orientation {
            case .vertical:
                let firstW = (bounds.width - divThick) * ratio
                first.animator().frame = NSRect(x: 0, y: 0, width: firstW, height: bounds.height)
                divider.animator().frame = NSRect(x: firstW, y: 0, width: divThick, height: bounds.height)
                second.animator().frame = NSRect(x: firstW + divThick, y: 0,
                                                  width: bounds.width - firstW - divThick, height: bounds.height)
            case .horizontal:
                let firstH = (bounds.height - divThick) * ratio
                first.animator().frame = NSRect(x: 0, y: 0, width: bounds.width, height: firstH)
                divider.animator().frame = NSRect(x: 0, y: firstH, width: bounds.width, height: divThick)
                second.animator().frame = NSRect(x: 0, y: firstH + divThick,
                                                  width: bounds.width, height: bounds.height - firstH - divThick)
            }
        }

        // Recursively animate nested splits
        first.animateLayout(duration: duration)
        second.animateLayout(duration: duration)
    }

    // MARK: - Serialization

    /// Serialize the split tree to a `SplitNodeState` for session persistence.
    func serialize(cwdLookup: (NSView) -> String?) -> SplitNodeState {
        if isLeaf {
            let cwd = contentView.flatMap { cwdLookup($0) }
            let scrollbackText = (contentView as? TerminalSurfaceView)?.readScreenText()
            return .leaf(cwd: cwd, scrollbackText: scrollbackText)
        }
        let ori = orientation == .horizontal ? "horizontal" : "vertical"
        return .branch(
            orientation: ori,
            ratio: Double(ratio),
            first: first?.serialize(cwdLookup: cwdLookup) ?? .leaf(cwd: nil, scrollbackText: nil),
            second: second?.serialize(cwdLookup: cwdLookup) ?? .leaf(cwd: nil, scrollbackText: nil)
        )
    }

    /// Create a branch node directly (for session restore).
    static func makeBranch(
        orientation: Orientation,
        ratio: CGFloat,
        first: SplitPaneView,
        second: SplitPaneView,
        onFocusChanged: ((NSView) -> Void)? = nil
    ) -> SplitPaneView {
        // Create a placeholder leaf and convert to branch
        let node = SplitPaneView(content: NSView())
        node.contentView?.removeFromSuperview()
        node.contentView = nil
        node.onFocusChanged = onFocusChanged
        node.orientation = orientation
        node.ratio = ratio
        node.first = first
        node.second = second
        first.onFocusChanged = onFocusChanged
        second.onFocusChanged = onFocusChanged
        node.addSubview(first)
        node.addSubview(second)

        let div = SplitDividerView(orientation: orientation)
        div.onDrag = { [weak node] delta in node?.handleDividerDrag(delta) }
        node.divider = div
        node.addSubview(div)

        return node
    }

    func refreshTheme() {
        divider?.refreshTheme()
        first?.refreshTheme()
        second?.refreshTheme()
    }

    // MARK: - Layout

    private let dividerThickness: CGFloat = 8
    private let dividerHitArea: CGFloat = 14

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
        ratio = min(Metrics.maxSplitRatio, max(Metrics.minSplitRatio, newRatio))
        needsLayout = true
    }
}

// MARK: - Divider View

fileprivate final class SplitDividerView: NSView {
    let orientation: SplitPaneView.Orientation
    var onDrag: ((CGFloat) -> Void)?
    private var lastDragLocation: CGFloat = 0
    private var isHovered = false
    private var isDragging = false
    private var trackingArea: NSTrackingArea?
    private var themeObserver: NSObjectProtocol?

    init(orientation: SplitPaneView.Orientation) {
        self.orientation = orientation
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 4
        layer?.cornerCurve = .continuous

        // Accessibility
        setAccessibilityRole(.splitter)
        setAccessibilityLabel(orientation == .vertical ? "Vertical split divider" : "Horizontal split divider")
        setAccessibilityHelp("Drag to resize panes. Double-click to equalize.")

        themeObserver = NotificationCenter.default.addObserver(
            forName: ThemeManager.didChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            self?.refreshTheme()
        }
        refreshTheme()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    deinit {
        if let themeObserver {
            NotificationCenter.default.removeObserver(themeObserver)
        }
    }

    private func updateAppearance(animated: Bool = true) {
        let color: NSColor
        let borderColor: CGColor
        let borderWidth: CGFloat
        let shadowColor: CGColor
        let shadowOpacity: Float
        let shadowRadius: CGFloat

        if BellithSettings.shared.useRebrandShell {
            if isDragging {
                color = RebrandTokens.Color.hoverOverlay
                borderColor = RebrandTokens.Color.lineStrong.cgColor
                borderWidth = 1
                shadowColor = RebrandTokens.Color.lineStrong.withAlphaComponent(0.22).cgColor
                shadowOpacity = 1
                shadowRadius = 8
            } else if isHovered {
                color = RebrandTokens.Color.hoverOverlay.withAlphaComponent(0.70)
                borderColor = RebrandTokens.Color.line.withAlphaComponent(0.75).cgColor
                borderWidth = 1
                shadowColor = NSColor.clear.cgColor
                shadowOpacity = 0
                shadowRadius = 0
            } else {
                color = RebrandTokens.Color.windowBg
                borderColor = RebrandTokens.Color.lineSoft.withAlphaComponent(0.45).cgColor
                borderWidth = 0
                shadowColor = NSColor.clear.cgColor
                shadowOpacity = 0
                shadowRadius = 0
            }
        } else if isDragging {
            color = Theme.accentSubtle.withAlphaComponent(Theme.colors.isLight ? 0.92 : 0.78)
            borderColor = Theme.dividerActive.cgColor
            borderWidth = 1
            shadowColor = Theme.accent.withAlphaComponent(0.28).cgColor
            shadowOpacity = 1
            shadowRadius = 12
        } else if isHovered {
            color = Theme.chromeElevated.withAlphaComponent(Theme.colors.isLight ? 0.92 : 0.78)
            borderColor = Theme.dividerHover.cgColor
            borderWidth = 1
            shadowColor = Theme.dividerHover.withAlphaComponent(0.22).cgColor
            shadowOpacity = 1
            shadowRadius = 8
        } else {
            color = Theme.chromePanel.withAlphaComponent(Theme.colors.isLight ? 0.9 : 0.72)
            borderColor = Theme.chromeHairline.withAlphaComponent(Theme.colors.isLight ? 0.42 : 0.32).cgColor
            borderWidth = 1
            shadowColor = NSColor.clear.cgColor
            shadowOpacity = 0
            shadowRadius = 0
        }

        if animated {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = Theme.animFast
                ctx.allowsImplicitAnimation = true
                self.layer?.backgroundColor = color.cgColor
                self.layer?.borderColor = borderColor
                self.layer?.borderWidth = borderWidth
                self.layer?.shadowColor = shadowColor
                self.layer?.shadowOpacity = shadowOpacity
                self.layer?.shadowRadius = shadowRadius
                self.layer?.shadowOffset = .zero
            }
        } else {
            layer?.backgroundColor = color.cgColor
            layer?.borderColor = borderColor
            layer?.borderWidth = borderWidth
            layer?.shadowColor = shadowColor
            layer?.shadowOpacity = shadowOpacity
            layer?.shadowRadius = shadowRadius
            layer?.shadowOffset = .zero
        }
    }

    override func updateTrackingAreas() {
        if let area = trackingArea { removeTrackingArea(area) }
        // Track on the expanded hit area
        let inset = dividerHitInset
        let expandedRect: NSRect
        switch orientation {
        case .vertical:
            expandedRect = bounds.insetBy(dx: -inset, dy: 0)
        case .horizontal:
            expandedRect = bounds.insetBy(dx: 0, dy: -inset)
        }
        let area = NSTrackingArea(
            rect: expandedRect,
            options: [.mouseEnteredAndExited, .activeAlways],
            owner: self,
            userInfo: nil
        )
        trackingArea = area
        addTrackingArea(area)
    }

    override func mouseEntered(with event: NSEvent) {
        isHovered = true
        updateAppearance()
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
        if !isDragging { updateAppearance() }
    }

    override func resetCursorRects() {
        let cursor: NSCursor = orientation == .vertical ? .resizeLeftRight : .resizeUpDown
        let inset = dividerHitInset
        let hitRect: NSRect
        switch orientation {
        case .vertical:
            hitRect = bounds.insetBy(dx: -inset, dy: 0)
        case .horizontal:
            hitRect = bounds.insetBy(dx: 0, dy: -inset)
        }
        addCursorRect(hitRect, cursor: cursor)
    }

    override var mouseDownCanMoveWindow: Bool { false }

    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 {
            // Double-click to equalize with smooth animation
            if let splitPane = superview as? SplitPaneView {
                splitPane.adjustRatio(by: 0.5 - splitPane.currentRatio, animated: true)
            }
            return
        }
        let loc = convert(event.locationInWindow, from: nil)
        lastDragLocation = orientation == .vertical ? loc.x : loc.y
        isDragging = true
        updateAppearance()
    }

    override func mouseDragged(with event: NSEvent) {
        let loc = convert(event.locationInWindow, from: nil)
        let current = orientation == .vertical ? loc.x : loc.y
        let delta = current - lastDragLocation
        lastDragLocation = current
        onDrag?(delta)
    }

    override func mouseUp(with event: NSEvent) {
        isDragging = false
        updateAppearance()
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        let inset = dividerHitInset
        let expanded: NSRect
        switch orientation {
        case .vertical:
            expanded = bounds.insetBy(dx: -inset, dy: 0)
        case .horizontal:
            expanded = bounds.insetBy(dx: 0, dy: -inset)
        }
        if expanded.contains(point) { return self }
        return nil
    }

    func refreshTheme() {
        updateAppearance(animated: false)
    }

    private var dividerHitInset: CGFloat {
        orientation == .vertical ? 5 : 4
    }
}
