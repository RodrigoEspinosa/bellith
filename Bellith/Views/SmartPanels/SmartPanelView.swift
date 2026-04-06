import AppKit

struct SmartPanelPlugin {
    typealias PanelFactory = () -> SmartPanelView

    let id: String
    let title: String
    let iconName: String
    let commandDescription: String
    let commandAliases: [String]
    let sidebarEnabledByDefault: Bool
    let makePanel: PanelFactory

    init(
        id: String,
        title: String,
        iconName: String,
        commandDescription: String,
        commandAliases: [String] = [],
        sidebarEnabledByDefault: Bool = true,
        makePanel: @escaping PanelFactory
    ) {
        self.id = id
        self.title = title
        self.iconName = iconName
        self.commandDescription = commandDescription
        self.commandAliases = commandAliases
        self.sidebarEnabledByDefault = sidebarEnabledByDefault
        self.makePanel = makePanel
    }

    fileprivate func matchesCommand(_ normalizedCommand: String) -> Bool {
        if SmartPanelRegistry.normalizeCommand(id) == normalizedCommand { return true }
        if SmartPanelRegistry.normalizeCommand(title) == normalizedCommand { return true }
        return commandAliases.contains { SmartPanelRegistry.normalizeCommand($0) == normalizedCommand }
    }
}

final class SmartPanelRegistry {
    static let shared = SmartPanelRegistry()

    private var orderedPluginIDs: [String] = []
    private var pluginsByID: [String: SmartPanelPlugin] = [:]

    private init() {
        register(ProcessTreePanel.plugin)
        register(NetworkPanel.plugin)
        register(EnvironmentPanel.plugin)
        register(FileActivityPanel.plugin)
        register(PerformancePanel.plugin)
    }

    func register(_ plugin: SmartPanelPlugin) {
        guard pluginsByID[plugin.id] == nil else { return }
        orderedPluginIDs.append(plugin.id)
        pluginsByID[plugin.id] = plugin
    }

    var allPlugins: [SmartPanelPlugin] {
        orderedPluginIDs.compactMap { pluginsByID[$0] }
    }

    func plugin(for id: String) -> SmartPanelPlugin? {
        pluginsByID[id]
    }

    func makePanel(id: String) -> SmartPanelView? {
        plugin(for: id)?.makePanel()
    }

    func plugin(matchingCommand text: String) -> SmartPanelPlugin? {
        let normalized = Self.normalizeCommand(text)
        return allPlugins.first { $0.matchesCommand(normalized) }
    }

    static func normalizeCommand(_ text: String) -> String {
        text
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .joined()
    }
}

/// Base class for smart (non-terminal) tab panels.
/// Provides a frosted header bar, scrollable content area, and a refresh timer.
class SmartPanelView: NSView {
    let pluginID: String
    let panelTitle: String
    let panelIconName: String

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

    init(plugin: SmartPanelPlugin) {
        self.pluginID = plugin.id
        self.panelTitle = plugin.title
        self.panelIconName = plugin.iconName
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

        headerIcon.image = NSImage(systemSymbolName: panelIconName, accessibilityDescription: nil)
        headerIcon.contentTintColor = Theme.accent
        headerIcon.imageScaling = .scaleProportionallyDown
        headerView.addSubview(headerIcon)

        headerLabel.stringValue = panelTitle
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

    static func create(pluginID: String) -> SmartPanelView? {
        SmartPanelRegistry.shared.makePanel(id: pluginID)
    }
}
