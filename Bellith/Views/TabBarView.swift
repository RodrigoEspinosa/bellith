import AppKit

/// Minimal Zen-style tab bar. Sits in the titlebar area, right of the traffic lights.
/// Pill-shaped tabs, close button appears on hover only.
/// Smart tabs show distinct icons and accent colors.
final class TabBarView: NSView, NSDraggingSource {
    struct Tab {
        let id: UUID
        var title: String
        var kind: TerminalContainerView.TabKind = .terminal
        var isPinned: Bool = false
    }

    private(set) var tabs: [Tab] = []
    private(set) var selectedIndex: Int = 0
    private var tabViews: [TabPillView] = []

    var onSelectTab: ((Int) -> Void)?
    var onCloseTab: ((Int) -> Void)?
    var onNewTab: (() -> Void)?
    var onReorderTab: ((Int, Int) -> Void)?
    var onTogglePin: ((Int) -> Void)?
    var onReceiveDraggedTab: ((TabDragPayload, Int) -> Void)?
    var onTearOffTab: ((UUID, NSPoint) -> Void)?

    var windowIdentifier: UUID?

    private var effectiveWindowIdentifier: UUID? {
        windowIdentifier ?? (window as? TerminalWindow)?.tabDragIdentifier
    }

    private var dragSourceIndex: Int?
    private var dragIndicatorLayer: CALayer?
    private var dragInsertionIndex: Int?
    private var isDropAccepted = false
    private let smartPanelRegistry: SmartPanelRegistry

    private let newTabButton = NSButton()
    private let singleTabLabel = NSTextField(labelWithString: "")
    private var themeObserver: NSObjectProtocol?
    private var singleTabMouseDownLocation: NSPoint?

    override var mouseDownCanMoveWindow: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    init(frame frameRect: NSRect = .zero, smartPanelRegistry: SmartPanelRegistry = .shared) {
        self.smartPanelRegistry = smartPanelRegistry
        super.init(frame: frameRect)
        registerForDraggedTypes([TabDragPayload.pasteboardType])
        setupNewTabButton()
        setupSingleTabLabel()
        themeObserver = NotificationCenter.default.addObserver(
            forName: ThemeManager.didChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            self?.refreshTheme()
        }
    }

    deinit {
        if let themeObserver {
            NotificationCenter.default.removeObserver(themeObserver)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    private func setupNewTabButton() {
        newTabButton.isBordered = false
        newTabButton.title = ""
        newTabButton.image = NSImage(systemSymbolName: "plus", accessibilityDescription: "New Tab")
        newTabButton.contentTintColor = Theme.textSecondary
        newTabButton.target = self
        newTabButton.action = #selector(handleNewTab)
        newTabButton.setFrameSize(NSSize(width: 24, height: 24))
        addSubview(newTabButton)
        newTabButton.wantsLayer = true
        newTabButton.layer?.cornerRadius = 6
    }

    private func setupSingleTabLabel() {
        singleTabLabel.font = BellithFont.ui(12.5, weight: .medium)
        singleTabLabel.textColor = Theme.textSecondary
        singleTabLabel.isEditable = false
        singleTabLabel.isSelectable = false
        singleTabLabel.isBezeled = false
        singleTabLabel.drawsBackground = false
        singleTabLabel.lineBreakMode = .byTruncatingTail
        singleTabLabel.maximumNumberOfLines = 1
        singleTabLabel.isHidden = true
        addSubview(singleTabLabel)
    }

    func update(tabs: [Tab], selectedIndex: Int) {
        self.tabs = tabs
        self.selectedIndex = selectedIndex

        if tabs.count == 1, let firstTab = tabs.first {
            singleTabLabel.stringValue = firstTab.title
        }

        rebuildTabViews()
    }

    func refreshTheme() {
        newTabButton.contentTintColor = Theme.textSecondary
        singleTabLabel.textColor = Theme.textSecondary
        dragIndicatorLayer?.backgroundColor = Theme.accent.withAlphaComponent(0.5).cgColor
        rebuildTabViews()
    }

    private func rebuildTabViews() {
        tabViews.forEach { $0.removeFromSuperview() }
        tabViews.removeAll()

        for (i, tab) in tabs.enumerated() {
            let pill = TabPillView(
                title: tab.title,
                isSelected: i == selectedIndex,
                isPinned: tab.isPinned,
                kind: tab.kind,
                smartPanelRegistry: smartPanelRegistry
            )
            pill.onSelect = { [weak self] in self?.onSelectTab?(i) }
            pill.onClose = { [weak self] in self?.onCloseTab?(i) }
            pill.onTogglePin = { [weak self] in self?.onTogglePin?(i) }
            pill.onBeginDrag = { [weak self, weak pill] event in
                guard let self else { return }
                self.beginDragSession(fromIndex: i, event: event, dragView: pill)
            }
            addSubview(pill)
            tabViews.append(pill)
        }

        needsLayout = true
    }

    override func layout() {
        super.layout()

        var x: CGFloat = 0
        let height = bounds.height
        let tabHeight: CGFloat = 30
        let y = (height - tabHeight) / 2

        for pill in tabViews {
            let width: CGFloat = min(180, max(92, pill.idealWidth))
            pill.frame = NSRect(x: x, y: y, width: width, height: tabHeight)
            x += width + 6
        }

        newTabButton.frame = NSRect(x: x + 4, y: (height - 24) / 2, width: 24, height: 24)

        // Single tab: show just the label and new tab button, hide pills.
        if tabs.count <= 1 {
            singleTabLabel.isHidden = false
            singleTabLabel.frame = NSRect(
                x: 0,
                y: (height - 16) / 2,
                width: min(240, singleTabLabel.attributedStringValue.size().width + 8),
                height: 16
            )
            newTabButton.frame = NSRect(x: singleTabLabel.frame.maxX + 8, y: (height - 24) / 2, width: 24, height: 24)
            tabViews.forEach { $0.isHidden = true }
        } else {
            singleTabLabel.isHidden = true
            tabViews.forEach { $0.isHidden = false }
        }

        updateDragIndicatorFrame()
    }

    override func mouseDown(with event: NSEvent) {
        guard tabs.count == 1 else {
            super.mouseDown(with: event)
            return
        }

        let location = convert(event.locationInWindow, from: nil)
        guard singleTabLabel.frame.insetBy(dx: -4, dy: -4).contains(location) else {
            super.mouseDown(with: event)
            return
        }

        singleTabMouseDownLocation = event.locationInWindow
    }

    override func mouseDragged(with event: NSEvent) {
        guard tabs.count == 1, let start = singleTabMouseDownLocation else {
            super.mouseDragged(with: event)
            return
        }

        let location = event.locationInWindow
        guard hypot(location.x - start.x, location.y - start.y) > 4 else { return }
        singleTabMouseDownLocation = nil
        beginDragSession(fromIndex: 0, event: event, dragView: singleTabLabel)
    }

    override func mouseUp(with event: NSEvent) {
        let shouldSelect = singleTabMouseDownLocation != nil
        singleTabMouseDownLocation = nil
        if shouldSelect {
            onSelectTab?(0)
            return
        }
        super.mouseUp(with: event)
    }

    private func beginDragSession(fromIndex: Int, event: NSEvent, dragView: NSView?) {
        guard dragSourceIndex == nil,
              fromIndex >= 0, fromIndex < tabs.count,
              let windowIdentifier = effectiveWindowIdentifier,
              let dragView,
              let draggingImage = dragImage(for: dragView) else { return }

        let payload = TabDragPayload(sourceWindowID: windowIdentifier, tabID: tabs[fromIndex].id)
        let pasteboardItem = NSPasteboardItem()
        payload.set(on: pasteboardItem)

        let draggingItem = NSDraggingItem(pasteboardWriter: pasteboardItem)
        draggingItem.setDraggingFrame(dragView.bounds, contents: draggingImage)

        dragSourceIndex = fromIndex
        dragInsertionIndex = nil
        isDropAccepted = false
        ensureDragIndicator()
        dragIndicatorLayer?.isHidden = true

        let session = dragView.beginDraggingSession(with: [draggingItem], event: event, source: self)
        session.animatesToStartingPositionsOnCancelOrFail = false
        session.draggingFormation = .none
    }

    private func dragImage(for view: NSView) -> NSImage? {
        guard view.bounds.width > 0, view.bounds.height > 0 else { return nil }

        if let representation = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
            view.cacheDisplay(in: view.bounds, to: representation)
            let image = NSImage(size: view.bounds.size)
            image.addRepresentation(representation)
            return image
        }

        let pdfData = view.dataWithPDF(inside: view.bounds)
        return NSImage(data: pdfData)
    }

    private func ensureDragIndicator() {
        guard dragIndicatorLayer == nil else { return }
        let indicator = CALayer()
        indicator.backgroundColor = Theme.accent.withAlphaComponent(0.5).cgColor
        indicator.cornerRadius = 1
        wantsLayer = true
        layer?.addSublayer(indicator)
        dragIndicatorLayer = indicator
    }

    private func clearDragState() {
        dragSourceIndex = nil
        dragInsertionIndex = nil
        isDropAccepted = false
        dragIndicatorLayer?.removeFromSuperlayer()
        dragIndicatorLayer = nil
    }

    private func insertionIndex(for location: NSPoint) -> Int {
        guard !tabs.isEmpty else { return 0 }

        if tabs.count <= 1 {
            return location.x <= singleTabLabel.frame.midX ? 0 : 1
        }

        for (index, pill) in tabViews.enumerated() {
            if location.x < pill.frame.midX {
                return index
            }
        }

        return tabs.count
    }

    private func updateDragIndicatorFrame() {
        guard let indicator = dragIndicatorLayer,
              let dragInsertionIndex else {
            dragIndicatorLayer?.isHidden = true
            return
        }

        let tabHeight: CGFloat = 30
        let y = (bounds.height - tabHeight) / 2 + 4
        let height = tabHeight - 8

        let x: CGFloat
        if tabs.isEmpty {
            x = 0
        } else if tabs.count <= 1 {
            x = dragInsertionIndex == 0 ? singleTabLabel.frame.minX - 2 : singleTabLabel.frame.maxX + 2
        } else if dragInsertionIndex <= 0 {
            x = tabViews.first?.frame.minX ?? 0
        } else if dragInsertionIndex >= tabViews.count {
            x = (tabViews.last?.frame.maxX ?? 0) + 6
        } else {
            x = tabViews[dragInsertionIndex].frame.minX - 3
        }

        indicator.frame = NSRect(x: x, y: y, width: 2, height: height)
        indicator.isHidden = false
    }

    static func reorderDestinationIndex(sourceIndex: Int, insertionIndex: Int, tabCount: Int) -> Int {
        guard tabCount > 0 else { return 0 }
        let clampedInsertion = max(0, min(insertionIndex, tabCount))
        let adjustedIndex = clampedInsertion > sourceIndex ? clampedInsertion - 1 : clampedInsertion
        return max(0, min(adjustedIndex, tabCount - 1))
    }

    // MARK: - NSDraggingSource

    func draggingSession(
        _ session: NSDraggingSession,
        sourceOperationMaskFor context: NSDraggingContext
    ) -> NSDragOperation {
        .move
    }

    func ignoreModifierKeys(for session: NSDraggingSession) -> Bool {
        true
    }

    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        let payload = dragSourceIndex.flatMap { tabs.indices.contains($0) ? tabs[$0].id : nil }
        let shouldTearOff = operation == [] && !isDropAccepted
        clearDragState()

        guard shouldTearOff, let tabID = payload else { return }
        onTearOffTab?(tabID, screenPoint)
    }

    // MARK: - NSDraggingDestination

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        draggingUpdated(sender)
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard TabDragPayload.read(from: sender.draggingPasteboard) != nil else {
            dragInsertionIndex = nil
            updateDragIndicatorFrame()
            return []
        }

        ensureDragIndicator()
        dragInsertionIndex = insertionIndex(for: convert(sender.draggingLocation, from: nil))
        updateDragIndicatorFrame()
        return .move
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        dragInsertionIndex = nil
        updateDragIndicatorFrame()
    }

    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool {
        TabDragPayload.read(from: sender.draggingPasteboard) != nil
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard let payload = TabDragPayload.read(from: sender.draggingPasteboard) else { return false }
        let insertionIndex = dragInsertionIndex ?? insertionIndex(for: convert(sender.draggingLocation, from: nil))
        let sourceIndex = tabs.firstIndex(where: { $0.id == payload.tabID })

        if payload.sourceWindowID == effectiveWindowIdentifier, let sourceIndex {
            let destinationIndex = Self.reorderDestinationIndex(
                sourceIndex: sourceIndex,
                insertionIndex: insertionIndex,
                tabCount: tabs.count
            )
            if destinationIndex != sourceIndex {
                onReorderTab?(sourceIndex, destinationIndex)
            }
        } else {
            onReceiveDraggedTab?(payload, insertionIndex)
        }

        isDropAccepted = true
        return true
    }

    override func concludeDragOperation(_ sender: NSDraggingInfo?) {
        dragInsertionIndex = nil
        updateDragIndicatorFrame()
    }

    @objc private func handleNewTab() {
        onNewTab?()
    }
}

// MARK: - Tab Pill View

fileprivate final class TabPillView: NSView {
    var onSelect: (() -> Void)?
    var onClose: (() -> Void)?
    var onTogglePin: (() -> Void)?
    var onBeginDrag: ((NSEvent) -> Void)?
    private var isDragging = false
    private var mouseDownLocation: NSPoint?

    override var mouseDownCanMoveWindow: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard bounds.contains(point) else { return nil }
        if !isPinned, closeButton.frame.contains(point) {
            return closeButton
        }
        return self
    }

    private let iconView = NSImageView()
    private let pinView = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let closeButton = NSButton()
    private let isSelected: Bool
    private let isPinned: Bool
    private let kind: TerminalContainerView.TabKind
    private let smartPanelRegistry: SmartPanelRegistry
    private var trackingArea: NSTrackingArea?
    private var isHovered = false

    var idealWidth: CGFloat {
        let iconWidth: CGFloat = (isSmartTab || isPinned) ? 22 : 0
        // Pinned tabs render compactly — no trailing close button gap.
        let trailing: CGFloat = isPinned ? 20 : 40
        return titleLabel.attributedStringValue.size().width + trailing + iconWidth
    }

    private var isSmartTab: Bool {
        if case .smart = kind { return true }
        return false
    }

    init(
        title: String,
        isSelected: Bool,
        isPinned: Bool,
        kind: TerminalContainerView.TabKind,
        smartPanelRegistry: SmartPanelRegistry
    ) {
        self.isSelected = isSelected
        self.isPinned = isPinned
        self.kind = kind
        self.smartPanelRegistry = smartPanelRegistry
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 7
        layer?.borderWidth = 0.5

        // Accessibility
        setAccessibilityRole(.button)
        let pinnedSuffix = isPinned ? ", pinned" : ""
        setAccessibilityLabel("Tab: \(title)\(pinnedSuffix)")
        setAccessibilityValue(isSelected ? "selected" : "")

        // Leading icon: smart-tab icon takes priority over pin glyph.
        if case .smart(let pluginID) = kind,
           let plugin = smartPanelRegistry.plugin(for: pluginID) {
            iconView.image = NSImage(systemSymbolName: plugin.iconName, accessibilityDescription: nil)
            iconView.contentTintColor = isSelected ? Theme.textPrimary : Theme.textTertiary
            iconView.imageScaling = .scaleProportionallyDown
            addSubview(iconView)
        } else if isPinned {
            pinView.image = NSImage(systemSymbolName: "pin.fill", accessibilityDescription: "Pinned")
            pinView.contentTintColor = isSelected ? Theme.accent : Theme.textTertiary
            pinView.imageScaling = .scaleProportionallyDown
            addSubview(pinView)
        }

        titleLabel.stringValue = title
        titleLabel.font = BellithFont.ui(12, weight: isSelected ? .medium : .regular)
        titleLabel.textColor = isSelected ? Theme.textPrimary : Theme.textSecondary
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.maximumNumberOfLines = 1
        addSubview(titleLabel)

        if !isPinned {
            closeButton.isBordered = false
            closeButton.title = ""
            closeButton.image = NSImage(systemSymbolName: "xmark", accessibilityDescription: "Close")
            closeButton.contentTintColor = Theme.textTertiary
            closeButton.setFrameSize(NSSize(width: 18, height: 18))
            closeButton.target = self
            closeButton.action = #selector(handleClose)
            closeButton.alphaValue = 0
            addSubview(closeButton)
        }

        updateAppearance()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        var labelX: CGFloat = 12

        if isSmartTab {
            iconView.frame = NSRect(x: 10, y: (bounds.height - 12) / 2, width: 12, height: 12)
            labelX = 28
        } else if isPinned {
            pinView.frame = NSRect(x: 10, y: (bounds.height - 11) / 2, width: 11, height: 11)
            labelX = 26
        }

        let trailingInset: CGFloat = isPinned ? 10 : 28
        titleLabel.frame = NSRect(x: labelX, y: (bounds.height - 16) / 2, width: max(0, bounds.width - labelX - trailingInset), height: 16)
        if !isPinned {
            closeButton.frame = NSRect(x: bounds.width - 24, y: (bounds.height - 18) / 2, width: 18, height: 18)
        }
    }

    override func updateTrackingAreas() {
        if let area = trackingArea { removeTrackingArea(area) }
        let area = NSTrackingArea(
            rect: bounds,
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
        guard !isPinned else { return }
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = Theme.animFast
            closeButton.animator().alphaValue = 1
        }
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
        updateAppearance()
        guard !isPinned else { return }
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = Theme.animFast
            closeButton.animator().alphaValue = 0
        }
    }

    override func rightMouseDown(with event: NSEvent) {
        let menu = NSMenu()
        let pinTitle = isPinned ? "Unpin Tab" : "Pin Tab"
        let pinItem = NSMenuItem(title: pinTitle, action: #selector(handleTogglePin), keyEquivalent: "")
        pinItem.target = self
        menu.addItem(pinItem)
        if !isPinned {
            menu.addItem(.separator())
            let closeItem = NSMenuItem(title: "Close Tab", action: #selector(handleClose), keyEquivalent: "")
            closeItem.target = self
            menu.addItem(closeItem)
        }
        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }

    @objc private func handleTogglePin() {
        onTogglePin?()
    }

    override func mouseDown(with event: NSEvent) {
        mouseDownLocation = event.locationInWindow
        isDragging = false
    }

    override func otherMouseDown(with event: NSEvent) {
        // Middle-click to close tab
        if event.buttonNumber == 2 {
            onClose?()
        }
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start = mouseDownLocation else { return }
        let location = event.locationInWindow
        if !isDragging && hypot(location.x - start.x, location.y - start.y) > 4 {
            isDragging = true
            onBeginDrag?(event)
        }
    }

    override func mouseUp(with event: NSEvent) {
        let shouldSelect = !isDragging
        isDragging = false
        mouseDownLocation = nil
        if shouldSelect {
            onSelect?()
        }
    }

    @objc private func handleClose() {
        onClose?()
    }

    private func updateAppearance() {
        let bgColor: CGColor
        let borderColor: CGColor
        if isSelected {
            bgColor = Theme.chromeElevated.withAlphaComponent(0.58).cgColor
            borderColor = Theme.chromeHairline.cgColor
        } else if isHovered {
            bgColor = Theme.hoverOverlay.cgColor
            borderColor = Theme.chromeHairline.cgColor
        } else {
            bgColor = NSColor.clear.cgColor
            borderColor = NSColor.clear.cgColor
        }

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = Theme.animFast
            ctx.allowsImplicitAnimation = true
            self.layer?.backgroundColor = bgColor
            self.layer?.borderColor = borderColor
        }
    }
}
