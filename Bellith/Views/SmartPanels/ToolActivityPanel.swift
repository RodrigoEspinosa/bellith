import AppKit

final class ToolActivityPanel: SmartPanelView {
    static let plugin = SmartPanelPlugin(
        id: "toolActivity",
        title: "Tool Activity",
        iconName: "bolt.horizontal.circle",
        commandDescription: "Inspect live CLI tool activity",
        commandAliases: ["tool activity", "agent activity", "cli activity"]
    ) {
        ToolActivityPanel()
    }

    private let emptyLabel = NSTextField(labelWithString: "")
    private let headerLabel = NSTextField(labelWithString: "LIVE ACTIVITY")
    private var rows: [ToolActivityRow] = []
    private let monitor = ToolActivityMonitor()
    private var events: [ToolActivityEvent] = []

    init() {
        super.init(plugin: Self.plugin)

        headerLabel.font = .systemFont(ofSize: 10, weight: .semibold)
        headerLabel.textColor = Theme.textMuted
        headerLabel.isEditable = false
        headerLabel.isBezeled = false
        headerLabel.drawsBackground = false
        contentView.addSubview(headerLabel)

        emptyLabel.font = .systemFont(ofSize: 12, weight: .regular)
        emptyLabel.textColor = Theme.textMuted
        emptyLabel.alignment = .center
        emptyLabel.isEditable = false
        emptyLabel.isBezeled = false
        emptyLabel.drawsBackground = false
        emptyLabel.stringValue = "Waiting for CLI activity"
        contentView.addSubview(emptyLabel)
    }

    override func refresh() {
        guard let shellPID else {
            showEmpty("No shell process")
            return
        }

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let snapshot = self?.monitor.snapshot(for: shellPID) ?? ToolActivitySnapshot(events: [])
            DispatchQueue.main.async {
                guard let self else { return }
                self.update(events: snapshot.events)
            }
        }
    }

    private func update(events: [ToolActivityEvent]) {
        self.events = events

        if events.isEmpty {
            showEmpty("Waiting for CLI activity")
            return
        }

        emptyLabel.isHidden = true
        headerLabel.isHidden = false

        while rows.count > events.count {
            rows.removeLast().removeFromSuperview()
        }

        while rows.count < events.count {
            let row = ToolActivityRow()
            contentView.addSubview(row)
            rows.append(row)
        }

        for (index, event) in events.enumerated() {
            rows[index].update(event: event, isAlternate: index.isMultiple(of: 2))
        }

        layoutContent()
    }

    private func showEmpty(_ message: String) {
        events.removeAll()
        rows.forEach { $0.removeFromSuperview() }
        rows.removeAll()
        headerLabel.isHidden = true
        emptyLabel.isHidden = false
        emptyLabel.stringValue = message
        layoutContent()
    }

    override func layoutContent() {
        let headerHeight: CGFloat = 24
        let rowHeight: CGFloat = 42
        let totalHeight = max(headerHeight + CGFloat(rows.count) * rowHeight, scrollView.bounds.height)
        contentView.frame = NSRect(x: 0, y: 0, width: scrollView.bounds.width, height: totalHeight)

        headerLabel.frame = NSRect(x: 14, y: totalHeight - headerHeight + 6, width: scrollView.bounds.width - 28, height: 12)
        emptyLabel.frame = NSRect(x: 0, y: (totalHeight - 20) / 2, width: scrollView.bounds.width, height: 20)

        for (index, row) in rows.enumerated() {
            let y = totalHeight - headerHeight - CGFloat(index + 1) * rowHeight
            row.frame = NSRect(x: 0, y: y, width: scrollView.bounds.width, height: rowHeight)
        }
    }
}

private final class ToolActivityRow: NSView {
    private let iconView = NSImageView()
    private let kindLabel = NSTextField(labelWithString: "")
    private let titleLabel = NSTextField(labelWithString: "")
    private let subtitleLabel = NSTextField(labelWithString: "")
    private let timeLabel = NSTextField(labelWithString: "")

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true

        iconView.imageScaling = .scaleProportionallyDown
        addSubview(iconView)

        for label in [kindLabel, titleLabel, subtitleLabel, timeLabel] {
            label.isEditable = false
            label.isBezeled = false
            label.drawsBackground = false
            label.maximumNumberOfLines = 1
            addSubview(label)
        }

        kindLabel.font = .systemFont(ofSize: 10, weight: .semibold)
        kindLabel.textColor = Theme.textMuted

        titleLabel.font = .monospacedSystemFont(ofSize: 12, weight: .medium)
        titleLabel.textColor = Theme.textPrimary

        subtitleLabel.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        subtitleLabel.textColor = Theme.textSecondary
        subtitleLabel.lineBreakMode = .byTruncatingMiddle

        timeLabel.font = .monospacedSystemFont(ofSize: 10, weight: .regular)
        timeLabel.textColor = Theme.textMuted
        timeLabel.alignment = .right
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func update(event: ToolActivityEvent, isAlternate: Bool) {
        layer?.backgroundColor = isAlternate
            ? NSColor(white: 1.0, alpha: 0.02).cgColor
            : NSColor.clear.cgColor

        iconView.image = NSImage(systemSymbolName: event.kind.iconName, accessibilityDescription: nil)
        iconView.contentTintColor = tintColor(for: event.kind)
        kindLabel.stringValue = event.kind.label.uppercased()
        titleLabel.stringValue = event.title
        subtitleLabel.stringValue = event.subtitle
        timeLabel.stringValue = RelativeDateTimeFormatter().localizedString(for: event.timestamp, relativeTo: .init())
        needsLayout = true
    }

    override func layout() {
        super.layout()
        let h = bounds.height
        iconView.frame = NSRect(x: 12, y: (h - 16) / 2, width: 16, height: 16)
        kindLabel.frame = NSRect(x: 38, y: h - 16, width: bounds.width - 120, height: 12)
        titleLabel.frame = NSRect(x: 38, y: 14, width: bounds.width - 120, height: 16)
        subtitleLabel.frame = NSRect(x: 38, y: 2, width: bounds.width - 120, height: 14)
        timeLabel.frame = NSRect(x: bounds.width - 92, y: h - 16, width: 78, height: 12)
    }

    private func tintColor(for kind: ToolActivityEvent.Kind) -> NSColor {
        switch kind {
        case .fileAdded:
            return Theme.success
        case .fileModified:
            return Theme.accent
        case .fileRemoved:
            return Theme.warning
        case .processStarted:
            return Theme.textPrimary
        case .networkOpened:
            return Theme.accent
        }
    }
}
