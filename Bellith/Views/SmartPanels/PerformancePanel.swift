import AppKit
import QuartzCore

/// Smart panel that displays resource usage for the shell process tree.
/// Shows aggregate stats, CPU/memory sparklines, and per-process breakdown.
final class PerformancePanel: SmartPanelView {
    static let plugin = SmartPanelPlugin(
        id: "performance",
        title: "Performance",
        iconName: "chart.xyaxis.line",
        commandDescription: "View resource usage",
        commandAliases: ["perf", "performance"]
    ) {
        PerformancePanel()
    }

    // MARK: - History

    static let maxSamples = 60
    private var cpuHistory: [Double] = []
    private var memoryHistory: [UInt64] = []

    // MARK: - Summary Cards

    private let cpuCard = StatCardView(icon: "cpu", label: "CPU")
    private let memoryCard = StatCardView(icon: "memorychip", label: "Memory")
    private let processCountCard = StatCardView(icon: "list.number", label: "Processes")
    private let uptimeCard = StatCardView(icon: "clock", label: "Uptime")

    // MARK: - Sparklines

    private let cpuSparkline = SparklineView(strokeColor: Theme.accent)
    private let memorySparkline = SparklineView(strokeColor: Theme.success)

    private let cpuSparklineLabel = NSTextField(labelWithString: "CPU")
    private let memorySparklineLabel = NSTextField(labelWithString: "MEMORY")

    // MARK: - Process Breakdown

    private let breakdownHeaderRow = BreakdownHeaderRow()
    private var breakdownRows: [BreakdownRow] = []
    private var flatProcesses: [(info: TerminalProcessInfo, depth: Int)] = []

    // MARK: - Empty State

    private let emptyLabel = NSTextField(labelWithString: "")

    init() {
        super.init(plugin: Self.plugin)

        for card in [cpuCard, memoryCard, processCountCard, uptimeCard] {
            contentView.addSubview(card)
        }

        for label in [cpuSparklineLabel, memorySparklineLabel] {
            label.font = .systemFont(ofSize: 10, weight: .semibold)
            label.textColor = Theme.textMuted
            label.isEditable = false
            label.isBezeled = false
            label.drawsBackground = false
            contentView.addSubview(label)
        }

        contentView.addSubview(cpuSparkline)
        contentView.addSubview(memorySparkline)
        contentView.addSubview(breakdownHeaderRow)

        emptyLabel.font = .systemFont(ofSize: 12, weight: .regular)
        emptyLabel.textColor = Theme.textMuted
        emptyLabel.alignment = .center
        emptyLabel.isEditable = false
        emptyLabel.isBezeled = false
        emptyLabel.drawsBackground = false
        contentView.addSubview(emptyLabel)
    }

    // MARK: - Refresh

    override func refresh() {
        guard let pid = shellPID else {
            showEmpty("No shell process")
            return
        }

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let tree = ProcessMonitor.processTree(rootPID: pid)
            DispatchQueue.main.async {
                guard let self else { return }
                if let tree {
                    self.updateData(tree)
                } else {
                    self.showEmpty("Process not found (PID \(pid))")
                }
            }
        }
    }

    private func updateData(_ root: TerminalProcessInfo) {
        emptyLabel.isHidden = true
        breakdownHeaderRow.isHidden = false

        // Flatten tree
        flatProcesses.removeAll()
        func flatten(_ node: TerminalProcessInfo) {
            flatProcesses.append((node, 0))
            for child in node.children {
                flatten(child)
            }
        }
        flatten(root)

        // Aggregate stats
        let totalCPU = flatProcesses.reduce(0.0) { $0 + $1.info.cpuUsage }
        let totalMemory = flatProcesses.reduce(UInt64(0)) { $0 + $1.info.memoryBytes }
        let processCount = flatProcesses.count

        // Update history
        cpuHistory.append(totalCPU)
        if cpuHistory.count > Self.maxSamples { cpuHistory.removeFirst() }
        memoryHistory.append(totalMemory)
        if memoryHistory.count > Self.maxSamples { memoryHistory.removeFirst() }

        // Summary cards
        cpuCard.setValue(String(format: "%.1f%%", totalCPU))
        memoryCard.setValue(ProcessMonitor.formatBytes(totalMemory))
        processCountCard.setValue("\(processCount)")
        uptimeCard.setValue(ProcessMonitor.formatUptime(from: root.startTime))

        // Sparklines
        cpuSparkline.strokeColor = Theme.accent
        cpuSparkline.update(values: cpuHistory, latestText: String(format: "%.1f%%", totalCPU))

        memorySparkline.strokeColor = Theme.success
        let memDoubles = memoryHistory.map { Double($0) }
        memorySparkline.update(values: memDoubles, latestText: ProcessMonitor.formatBytes(totalMemory))

        // Sort processes by CPU descending for breakdown
        let sorted = flatProcesses.sorted { $0.info.cpuUsage > $1.info.cpuUsage }
        let maxCPU = sorted.first?.info.cpuUsage ?? 1.0

        // Update breakdown rows
        while breakdownRows.count > sorted.count {
            breakdownRows.removeLast().removeFromSuperview()
        }
        while breakdownRows.count < sorted.count {
            let row = BreakdownRow()
            contentView.addSubview(row)
            breakdownRows.append(row)
        }

        for (i, entry) in sorted.enumerated() {
            breakdownRows[i].update(
                info: entry.info,
                maxCPU: max(maxCPU, 1.0),
                isAlternate: i % 2 == 1
            )
        }

        layoutContent()
    }

    private func showEmpty(_ message: String) {
        flatProcesses.removeAll()
        cpuHistory.removeAll()
        memoryHistory.removeAll()
        breakdownRows.forEach { $0.removeFromSuperview() }
        breakdownRows.removeAll()
        breakdownHeaderRow.isHidden = true
        emptyLabel.isHidden = false
        emptyLabel.stringValue = message

        cpuCard.setValue("--")
        memoryCard.setValue("--")
        processCountCard.setValue("--")
        uptimeCard.setValue("--")
        cpuSparkline.update(values: [], latestText: "--")
        memorySparkline.update(values: [], latestText: "--")

        layoutContent()
    }

    // MARK: - Layout

    override func layoutContent() {
        let w = scrollView.bounds.width
        let pad: CGFloat = Theme.spacingMD
        let cardSpacing: CGFloat = Theme.spacingSM
        let cardHeight: CGFloat = 56

        // Summary cards: 4 across
        let availableWidth = w - pad * 2 - cardSpacing * 3
        let cardWidth = floor(availableWidth / 4)
        var y: CGFloat = 0 // will be computed from top
        let cards = [cpuCard, memoryCard, processCountCard, uptimeCard]

        // We lay out from top-down in flipped coordinate sense,
        // but NSView origin is bottom-left, so we compute total height first.
        let sparklineHeight: CGFloat = 40
        let sparklineLabelHeight: CGFloat = 14
        let breakdownHeaderHeight: CGFloat = 24
        let breakdownRowHeight: CGFloat = 26
        let sectionSpacing: CGFloat = Theme.spacingMD

        let totalHeight: CGFloat = max(
            pad + cardHeight + sectionSpacing
            + sparklineLabelHeight + 4 + sparklineHeight + sectionSpacing
            + sparklineLabelHeight + 4 + sparklineHeight + sectionSpacing
            + breakdownHeaderHeight + CGFloat(breakdownRows.count) * breakdownRowHeight + pad,
            scrollView.bounds.height
        )
        contentView.frame = NSRect(x: 0, y: 0, width: w, height: totalHeight)

        // Top of content (NSView y = totalHeight - pad)
        y = totalHeight - pad - cardHeight
        for (i, card) in cards.enumerated() {
            let x = pad + CGFloat(i) * (cardWidth + cardSpacing)
            card.frame = NSRect(x: x, y: y, width: cardWidth, height: cardHeight)
        }

        // CPU sparkline section
        y -= sectionSpacing + sparklineLabelHeight
        cpuSparklineLabel.frame = NSRect(x: pad, y: y, width: 60, height: sparklineLabelHeight)
        y -= 4 + sparklineHeight
        cpuSparkline.frame = NSRect(x: pad, y: y, width: w - pad * 2, height: sparklineHeight)

        // Memory sparkline section
        y -= sectionSpacing + sparklineLabelHeight
        memorySparklineLabel.frame = NSRect(x: pad, y: y, width: 60, height: sparklineLabelHeight)
        y -= 4 + sparklineHeight
        memorySparkline.frame = NSRect(x: pad, y: y, width: w - pad * 2, height: sparklineHeight)

        // Breakdown header
        y -= sectionSpacing + breakdownHeaderHeight
        breakdownHeaderRow.frame = NSRect(x: 0, y: y, width: w, height: breakdownHeaderHeight)

        // Breakdown rows
        for (i, row) in breakdownRows.enumerated() {
            let rowY = y - CGFloat(i + 1) * breakdownRowHeight
            row.frame = NSRect(x: 0, y: rowY, width: w, height: breakdownRowHeight)
        }

        // Empty label centered
        emptyLabel.frame = NSRect(x: 0, y: (totalHeight - 20) / 2, width: w, height: 20)
    }
}

// MARK: - Stat Card View

private final class StatCardView: NSView {
    private let iconView = NSImageView()
    private let labelField = NSTextField(labelWithString: "")
    private let valueField = NSTextField(labelWithString: "--")

    init(icon: String, label: String) {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = Theme.surface.cgColor
        layer?.cornerRadius = Theme.radiusElement
        layer?.borderWidth = 0.5
        layer?.borderColor = Theme.borderSubtle.cgColor

        iconView.image = NSImage(systemSymbolName: icon, accessibilityDescription: nil)
        iconView.contentTintColor = Theme.textMuted
        iconView.imageScaling = .scaleProportionallyDown
        addSubview(iconView)

        labelField.stringValue = label
        labelField.font = .systemFont(ofSize: 10, weight: .medium)
        labelField.textColor = Theme.textMuted
        labelField.isEditable = false
        labelField.isBezeled = false
        labelField.drawsBackground = false
        addSubview(labelField)

        valueField.font = .monospacedSystemFont(ofSize: 16, weight: .semibold)
        valueField.textColor = Theme.textPrimary
        valueField.isEditable = false
        valueField.isBezeled = false
        valueField.drawsBackground = false
        valueField.lineBreakMode = .byTruncatingTail
        addSubview(valueField)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func setValue(_ text: String) {
        valueField.stringValue = text
    }

    override func layout() {
        super.layout()
        let h = bounds.height
        let w = bounds.width
        let innerPad: CGFloat = 8

        iconView.frame = NSRect(x: innerPad, y: h - 18, width: 12, height: 12)
        labelField.frame = NSRect(x: innerPad + 16, y: h - 19, width: w - innerPad * 2 - 16, height: 12)
        valueField.frame = NSRect(x: innerPad, y: 4, width: w - innerPad * 2, height: 22)
    }
}

// MARK: - Sparkline View

private final class SparklineView: NSView {
    var strokeColor: NSColor {
        didSet { setNeedsDisplay(bounds) }
    }

    private var values: [Double] = []
    private let latestLabel = NSTextField(labelWithString: "")
    private let shapeLayer = CAShapeLayer()
    private let fillLayer = CAShapeLayer()

    init(strokeColor: NSColor) {
        self.strokeColor = strokeColor
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = Theme.surface.cgColor
        layer?.cornerRadius = Theme.radiusElement
        layer?.borderWidth = 0.5
        layer?.borderColor = Theme.borderSubtle.cgColor
        layer?.masksToBounds = true

        fillLayer.fillColor = strokeColor.withAlphaComponent(0.08).cgColor
        fillLayer.strokeColor = nil
        layer?.addSublayer(fillLayer)

        shapeLayer.fillColor = nil
        shapeLayer.strokeColor = strokeColor.cgColor
        shapeLayer.lineWidth = 1.5
        shapeLayer.lineJoin = .round
        layer?.addSublayer(shapeLayer)

        latestLabel.font = .monospacedSystemFont(ofSize: 10, weight: .medium)
        latestLabel.textColor = Theme.textSecondary
        latestLabel.isEditable = false
        latestLabel.isBezeled = false
        latestLabel.drawsBackground = false
        latestLabel.alignment = .right
        addSubview(latestLabel)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func update(values: [Double], latestText: String) {
        self.values = values
        latestLabel.stringValue = latestText

        // Update colors in case theme changed
        shapeLayer.strokeColor = strokeColor.cgColor
        fillLayer.fillColor = strokeColor.withAlphaComponent(0.08).cgColor

        rebuildPath()
    }

    override func layout() {
        super.layout()
        latestLabel.frame = NSRect(x: bounds.width - 80, y: bounds.height - 16, width: 74, height: 14)
        rebuildPath()
    }

    private func rebuildPath() {
        guard values.count >= 2 else {
            shapeLayer.path = nil
            fillLayer.path = nil
            return
        }

        let w = bounds.width
        let h = bounds.height
        let insetY: CGFloat = 4
        let drawHeight = h - insetY * 2

        let maxVal = max(values.max() ?? 1.0, 1.0)
        let count = values.count
        let stepX = w / CGFloat(PerformancePanel.maxSamples - 1)

        // Start x so that the latest sample is at the right edge
        let startX = w - CGFloat(count - 1) * stepX

        let linePath = NSBezierPath()
        let fillPath = NSBezierPath()

        for (i, val) in values.enumerated() {
            let x = startX + CGFloat(i) * stepX
            let normalized = CGFloat(val / maxVal)
            let y = insetY + normalized * drawHeight

            if i == 0 {
                linePath.move(to: NSPoint(x: x, y: y))
                fillPath.move(to: NSPoint(x: x, y: insetY))
                fillPath.line(to: NSPoint(x: x, y: y))
            } else {
                linePath.line(to: NSPoint(x: x, y: y))
                fillPath.line(to: NSPoint(x: x, y: y))
            }
        }

        // Close fill path along bottom
        let lastX = startX + CGFloat(count - 1) * stepX
        fillPath.line(to: NSPoint(x: lastX, y: insetY))
        fillPath.close()

        shapeLayer.path = linePath.cgPath
        fillLayer.path = fillPath.cgPath
    }
}

private extension NSBezierPath {
    var cgPath: CGPath {
        let path = CGMutablePath()
        var points = [NSPoint](repeating: .zero, count: 3)
        for i in 0..<elementCount {
            let kind = element(at: i, associatedPoints: &points)
            switch kind {
            case .moveTo:    path.move(to: points[0])
            case .lineTo:    path.addLine(to: points[0])
            case .curveTo:   path.addCurve(to: points[2], control1: points[0], control2: points[1])
            case .closePath: path.closeSubpath()
            @unknown default: break
            }
        }
        return path
    }
}

// MARK: - Breakdown Header Row

private final class BreakdownHeaderRow: NSView {
    private let nameLabel = NSTextField(labelWithString: "PROCESS")
    private let pidLabel = NSTextField(labelWithString: "PID")
    private let cpuLabel = NSTextField(labelWithString: "CPU")
    private let memLabel = NSTextField(labelWithString: "MEMORY")

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = NSColor(white: 1.0, alpha: 0.03).cgColor

        for label in [nameLabel, pidLabel, cpuLabel, memLabel] {
            label.font = .systemFont(ofSize: 10, weight: .semibold)
            label.textColor = Theme.textMuted
            label.isEditable = false
            label.isBezeled = false
            label.drawsBackground = false
            addSubview(label)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        let h = bounds.height
        let cols = breakdownColumns(width: bounds.width)
        nameLabel.frame = NSRect(x: cols.nameX, y: (h - 12) / 2, width: cols.nameW, height: 12)
        pidLabel.frame = NSRect(x: cols.pidX, y: (h - 12) / 2, width: cols.pidW, height: 12)
        cpuLabel.frame = NSRect(x: cols.cpuX, y: (h - 12) / 2, width: cols.cpuW, height: 12)
        memLabel.frame = NSRect(x: cols.memX, y: (h - 12) / 2, width: cols.memW, height: 12)
    }
}

// MARK: - Breakdown Row

private final class BreakdownRow: NSView {
    private let nameLabel = NSTextField(labelWithString: "")
    private let pidLabel = NSTextField(labelWithString: "")
    private let cpuBarBackground = NSView()
    private let cpuBarFill = NSView()
    private let cpuLabel = NSTextField(labelWithString: "")
    private let memLabel = NSTextField(labelWithString: "")

    private var cpuFraction: CGFloat = 0

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true

        cpuBarBackground.wantsLayer = true
        cpuBarBackground.layer?.backgroundColor = NSColor(white: 1.0, alpha: 0.04).cgColor
        cpuBarBackground.layer?.cornerRadius = 2
        addSubview(cpuBarBackground)

        cpuBarFill.wantsLayer = true
        cpuBarFill.layer?.backgroundColor = Theme.accent.cgColor
        cpuBarFill.layer?.cornerRadius = 2
        addSubview(cpuBarFill)

        for label in [nameLabel, pidLabel, cpuLabel, memLabel] {
            label.isEditable = false
            label.isBezeled = false
            label.drawsBackground = false
            label.lineBreakMode = .byTruncatingTail
            label.maximumNumberOfLines = 1
            addSubview(label)
        }

        nameLabel.font = .monospacedSystemFont(ofSize: 11, weight: .medium)
        nameLabel.textColor = Theme.textPrimary

        pidLabel.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        pidLabel.textColor = Theme.textMuted
        pidLabel.alignment = .right

        cpuLabel.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        cpuLabel.textColor = Theme.textSecondary
        cpuLabel.alignment = .right

        memLabel.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        memLabel.textColor = Theme.textSecondary
        memLabel.alignment = .right
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func update(info: TerminalProcessInfo, maxCPU: Double, isAlternate: Bool) {
        layer?.backgroundColor = isAlternate
            ? NSColor(white: 1.0, alpha: 0.02).cgColor
            : NSColor.clear.cgColor

        nameLabel.stringValue = info.name
        pidLabel.stringValue = "\(info.pid)"
        cpuLabel.stringValue = String(format: "%.1f%%", info.cpuUsage)
        memLabel.stringValue = ProcessMonitor.formatBytes(info.memoryBytes)

        cpuFraction = CGFloat(info.cpuUsage / maxCPU)
        cpuBarFill.layer?.backgroundColor = Theme.accent.cgColor

        needsLayout = true
    }

    override func layout() {
        super.layout()
        let h = bounds.height
        let cols = breakdownColumns(width: bounds.width)

        nameLabel.frame = NSRect(x: cols.nameX, y: (h - 14) / 2, width: cols.nameW, height: 14)
        pidLabel.frame = NSRect(x: cols.pidX, y: (h - 14) / 2, width: cols.pidW, height: 14)

        // CPU bar within the CPU column area
        let barHeight: CGFloat = 4
        let barMaxWidth = cols.cpuW - 50
        let barY = (h - barHeight) / 2
        cpuBarBackground.frame = NSRect(x: cols.cpuX, y: barY, width: barMaxWidth, height: barHeight)
        cpuBarFill.frame = NSRect(x: cols.cpuX, y: barY, width: barMaxWidth * cpuFraction, height: barHeight)

        cpuLabel.frame = NSRect(x: cols.cpuX + barMaxWidth + 4, y: (h - 14) / 2, width: 44, height: 14)
        memLabel.frame = NSRect(x: cols.memX, y: (h - 14) / 2, width: cols.memW, height: 14)
    }
}

// MARK: - Breakdown Column Layout

private struct BreakdownColumns {
    let nameX: CGFloat; let nameW: CGFloat
    let pidX: CGFloat;  let pidW: CGFloat
    let cpuX: CGFloat;  let cpuW: CGFloat
    let memX: CGFloat;  let memW: CGFloat
}

private func breakdownColumns(width: CGFloat) -> BreakdownColumns {
    let pad: CGFloat = 12
    let pidW: CGFloat = 52
    let cpuW: CGFloat = 130
    let memW: CGFloat = 72
    let nameW = max(80, width - pad - pidW - cpuW - memW - pad - 24)

    var x = pad
    let name = (x: x, w: nameW); x += nameW + 8
    let pid  = (x: x, w: pidW);  x += pidW + 8
    let cpu  = (x: x, w: cpuW);  x += cpuW + 8
    let mem  = (x: x, w: memW)

    return BreakdownColumns(
        nameX: name.x, nameW: name.w,
        pidX: pid.x, pidW: pid.w,
        cpuX: cpu.x, cpuW: cpu.w,
        memX: mem.x, memW: mem.w
    )
}
