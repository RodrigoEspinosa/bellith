import AppKit

/// The kind of smart panel — used for tab identification and icon selection.
enum SmartPanelKind: String, CaseIterable {
    case processTree
    case network
    case environment
    case fileActivity
    case performance

    var displayName: String {
        switch self {
        case .processTree:  return "Processes"
        case .network:      return "Network"
        case .environment:  return "Environment"
        case .fileActivity: return "Files"
        case .performance:  return "Performance"
        }
    }

    var iconName: String {
        switch self {
        case .processTree:  return "list.bullet.indent"
        case .network:      return "network"
        case .environment:  return "text.alignleft"
        case .fileActivity: return "doc.text.magnifyingglass"
        case .performance:  return "chart.xyaxis.line"
        }
    }
}

/// Base class for smart (non-terminal) tab panels.
/// Provides a frosted header bar, scrollable content area, and a refresh timer.
class SmartPanelView: NSView {
    let kind: SmartPanelKind

    /// The shell PID to scope inspection to. Set by the container when creating the tab.
    var shellPID: pid_t? {
        didSet { if shellPID != oldValue { refresh() } }
    }

    private let headerView = NSView()
    private let headerLabel = NSTextField(labelWithString: "")
    private let headerIcon = NSImageView()

    /// When false, hides the built-in header bar (useful when embedded in the sidebar
    /// where the tool row already serves as the label).
    var showsHeader: Bool = true {
        didSet {
            headerView.isHidden = !showsHeader
            needsLayout = true
        }
    }
    let scrollView = NSScrollView()
    let contentView = NSView()
    private var refreshTimer: DispatchSourceTimer?
    private var isActive = false

    init(kind: SmartPanelKind) {
        self.kind = kind
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = Theme.base.cgColor

        setupHeader()
        setupScrollView()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    deinit {
        stopRefreshing()
    }

    // MARK: - Setup

    private func setupHeader() {
        headerView.wantsLayer = true
        headerView.layer?.backgroundColor = Theme.surface.cgColor
        addSubview(headerView)

        let border = CALayer()
        border.backgroundColor = Theme.border.cgColor
        border.frame = CGRect(x: 0, y: 0, width: 10000, height: 0.5)
        headerView.layer?.addSublayer(border)

        headerIcon.image = NSImage(systemSymbolName: kind.iconName, accessibilityDescription: nil)
        headerIcon.contentTintColor = Theme.accent
        headerIcon.imageScaling = .scaleProportionallyDown
        headerView.addSubview(headerIcon)

        headerLabel.stringValue = kind.displayName
        headerLabel.font = .systemFont(ofSize: 12, weight: .semibold)
        headerLabel.textColor = Theme.textPrimary
        headerView.addSubview(headerLabel)
    }

    private func setupScrollView() {
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder

        contentView.wantsLayer = true
        scrollView.documentView = contentView

        addSubview(scrollView)
    }

    // MARK: - Layout

    private let headerHeight: CGFloat = 36

    override func layout() {
        super.layout()
        if showsHeader {
            headerView.frame = NSRect(x: 0, y: bounds.height - headerHeight, width: bounds.width, height: headerHeight)
            headerIcon.frame = NSRect(x: 12, y: (headerHeight - 14) / 2, width: 14, height: 14)
            headerLabel.frame = NSRect(x: 32, y: (headerHeight - 16) / 2, width: bounds.width - 44, height: 16)
            scrollView.frame = NSRect(x: 0, y: 0, width: bounds.width, height: bounds.height - headerHeight)
        } else {
            scrollView.frame = bounds
        }
        layoutContent()
    }

    /// Override in subclasses to layout the content within the scroll view.
    func layoutContent() {}

    // MARK: - Refresh

    /// Override in subclasses to update data.
    func refresh() {}

    /// Start the periodic refresh timer (call when the tab becomes visible).
    func startRefreshing(interval: TimeInterval = 2.0) {
        guard !isActive else { return }
        isActive = true
        refresh()

        let timer = DispatchSource.makeTimerSource(queue: .global(qos: .userInitiated))
        timer.schedule(deadline: .now() + interval, repeating: interval)
        timer.setEventHandler { [weak self] in
            DispatchQueue.main.async { self?.refresh() }
        }
        timer.resume()
        refreshTimer = timer
    }

    /// Stop the periodic refresh timer.
    func stopRefreshing() {
        isActive = false
        refreshTimer?.cancel()
        refreshTimer = nil
    }

    // MARK: - Factory

    static func create(kind: SmartPanelKind) -> SmartPanelView {
        switch kind {
        case .processTree:
            return ProcessTreePanel()
        case .network:
            return NetworkPanel()
        case .environment:
            return EnvironmentPanel()
        case .fileActivity:
            return FileActivityPanel()
        case .performance:
            return PerformancePanel()
        }
    }
}
