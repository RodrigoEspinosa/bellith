import AppKit

/// Smart panel that displays the process tree rooted at the shell PID.
final class ProcessTreePanel: SmartPanelView {
    private var rows: [ProcessRow] = []
    private var flatProcesses: [(info: TerminalProcessInfo, depth: Int)] = []

    init() {
        super.init(kind: .processTree)
    }

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
                    self.updateTree(tree)
                } else {
                    self.showEmpty("Process not found (PID \(pid))")
                }
            }
        }
    }

    private func updateTree(_ root: TerminalProcessInfo) {
        // Flatten tree with depth info
        flatProcesses.removeAll()
        func flatten(_ node: TerminalProcessInfo, depth: Int) {
            flatProcesses.append((node, depth))
            for child in node.children.sorted(by: { $0.pid < $1.pid }) {
                flatten(child, depth: depth + 1)
            }
        }
        flatten(root, depth: 0)

        // Update rows
        while rows.count > flatProcesses.count {
            rows.removeLast().removeFromSuperview()
        }
        while rows.count < flatProcesses.count {
            let row = ProcessRow()
            contentView.addSubview(row)
            rows.append(row)
        }

        for (i, entry) in flatProcesses.enumerated() {
            rows[i].update(info: entry.info, depth: entry.depth, isAlternate: i % 2 == 1)
        }

        layoutContent()
    }

    private func showEmpty(_ message: String) {
        flatProcesses.removeAll()
        rows.forEach { $0.removeFromSuperview() }
        rows.removeAll()

        let row = ProcessRow()
        row.showMessage(message)
        contentView.addSubview(row)
        rows.append(row)
        layoutContent()
    }

    override func layoutContent() {
        let rowHeight: CGFloat = 28
        let totalHeight = max(CGFloat(rows.count) * rowHeight, scrollView.bounds.height)
        contentView.frame = NSRect(x: 0, y: 0, width: scrollView.bounds.width, height: totalHeight)

        for (i, row) in rows.enumerated() {
            let y = totalHeight - CGFloat(i + 1) * rowHeight
            row.frame = NSRect(x: 0, y: y, width: scrollView.bounds.width, height: rowHeight)
        }
    }
}

// MARK: - Process Row

private final class ProcessRow: NSView {
    private let nameLabel = NSTextField(labelWithString: "")
    private let pidLabel = NSTextField(labelWithString: "")
    private let cpuLabel = NSTextField(labelWithString: "")
    private let memLabel = NSTextField(labelWithString: "")
    private let uptimeLabel = NSTextField(labelWithString: "")
    private let treeIndicator = NSTextField(labelWithString: "")
    private var depth: Int = 0

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true

        for label in [treeIndicator, nameLabel, pidLabel, cpuLabel, memLabel, uptimeLabel] {
            label.isEditable = false
            label.isBezeled = false
            label.drawsBackground = false
            label.lineBreakMode = .byTruncatingTail
            label.maximumNumberOfLines = 1
            addSubview(label)
        }

        treeIndicator.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        treeIndicator.textColor = Theme.textMuted

        nameLabel.font = .monospacedSystemFont(ofSize: 12, weight: .medium)
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

        uptimeLabel.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        uptimeLabel.textColor = Theme.textMuted
        uptimeLabel.alignment = .right
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func update(info: TerminalProcessInfo, depth: Int, isAlternate: Bool) {
        self.depth = depth
        layer?.backgroundColor = isAlternate
            ? NSColor(white: 1.0, alpha: 0.02).cgColor
            : NSColor.clear.cgColor

        // Tree connector
        if depth > 0 {
            let prefix = String(repeating: "  ", count: depth - 1) + "└ "
            treeIndicator.stringValue = prefix
        } else {
            treeIndicator.stringValue = ""
        }

        nameLabel.stringValue = info.name
        nameLabel.textColor = depth == 0 ? Theme.accent : Theme.textPrimary
        nameLabel.font = .monospacedSystemFont(ofSize: 12, weight: depth == 0 ? .semibold : .medium)

        pidLabel.stringValue = "\(info.pid)"
        cpuLabel.stringValue = String(format: "%.1f%%", info.cpuUsage)
        cpuLabel.textColor = info.cpuUsage > 50 ? Theme.warning : Theme.textSecondary
        memLabel.stringValue = ProcessMonitor.formatBytes(info.memoryBytes)
        uptimeLabel.stringValue = ProcessMonitor.formatUptime(from: info.startTime)

        needsLayout = true
    }

    func showMessage(_ message: String) {
        treeIndicator.stringValue = ""
        nameLabel.stringValue = message
        nameLabel.textColor = Theme.textMuted
        nameLabel.font = .systemFont(ofSize: 12, weight: .regular)
        pidLabel.stringValue = ""
        memLabel.stringValue = ""
        uptimeLabel.stringValue = ""
        layer?.backgroundColor = NSColor.clear.cgColor
    }

    override func layout() {
        super.layout()
        let h = bounds.height
        let indentWidth = CGFloat(depth) * 16
        let treeWidth = max(indentWidth + 16, 20)

        treeIndicator.frame = NSRect(x: 8, y: (h - 14) / 2, width: treeWidth, height: 14)

        let nameX = 8 + treeWidth
        let rightColsWidth: CGFloat = 240
        let nameWidth = max(bounds.width - nameX - rightColsWidth - 8, 60)

        nameLabel.frame = NSRect(x: nameX, y: (h - 16) / 2, width: nameWidth, height: 16)
        pidLabel.frame = NSRect(x: bounds.width - 240, y: (h - 14) / 2, width: 56, height: 14)
        cpuLabel.frame = NSRect(x: bounds.width - 180, y: (h - 14) / 2, width: 48, height: 14)
        memLabel.frame = NSRect(x: bounds.width - 128, y: (h - 14) / 2, width: 68, height: 14)
        uptimeLabel.frame = NSRect(x: bounds.width - 56, y: (h - 14) / 2, width: 52, height: 14)
    }
}
