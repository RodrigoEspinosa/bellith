import AppKit

/// Smart panel that shows network connections for terminal processes.
/// Similar to LittleSnitch but scoped to the shell's process tree.
final class NetworkPanel: SmartPanelView {
    private var rows: [ConnectionRow] = []
    private var connections: [ConnectionInfo] = []
    private let headerRow = ConnectionHeaderRow()
    private let emptyLabel = NSTextField(labelWithString: "")
    private var resolvedHosts: [String: String] = [:]

    init() {
        super.init(kind: .network)

        contentView.addSubview(headerRow)

        emptyLabel.font = .systemFont(ofSize: 12, weight: .regular)
        emptyLabel.textColor = Theme.textMuted
        emptyLabel.alignment = .center
        emptyLabel.isEditable = false
        emptyLabel.isBezeled = false
        emptyLabel.drawsBackground = false
        contentView.addSubview(emptyLabel)
    }

    override func refresh() {
        guard let pid = shellPID else {
            showEmpty("No shell process")
            return
        }

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let pids = ProcessMonitor.allDescendants(of: pid)
            let conns = NetworkMonitor.connections(for: pids)
                .filter { $0.state != "CLOSED" && $0.state != "TIME_WAIT" }
                .sorted { a, b in
                    if a.state == "ESTABLISHED" && b.state != "ESTABLISHED" { return true }
                    if a.state != "ESTABLISHED" && b.state == "ESTABLISHED" { return false }
                    return a.pid < b.pid
                }

            DispatchQueue.main.async {
                guard let self else { return }
                self.updateConnections(conns)
            }
        }
    }

    private func updateConnections(_ conns: [ConnectionInfo]) {
        connections = conns

        if conns.isEmpty {
            showEmpty("No active connections")
            return
        }

        emptyLabel.isHidden = true
        headerRow.isHidden = false

        // Update rows
        while rows.count > conns.count {
            rows.removeLast().removeFromSuperview()
        }
        while rows.count < conns.count {
            let row = ConnectionRow()
            contentView.addSubview(row)
            rows.append(row)
        }

        for (i, conn) in conns.enumerated() {
            let hostname = resolvedHosts[conn.remoteAddress]
            rows[i].update(conn: conn, resolvedHost: hostname, isAlternate: i % 2 == 1)

            // Resolve hostname if not cached
            if resolvedHosts[conn.remoteAddress] == nil && !conn.remoteAddress.isEmpty && conn.remoteAddress != "0.0.0.0" && conn.remoteAddress != "::" {
                let addr = conn.remoteAddress
                NetworkMonitor.resolveHostname(addr) { [weak self] name in
                    DispatchQueue.main.async {
                        guard let self else { return }
                        self.resolvedHosts[addr] = name ?? addr
                        // Re-render if still showing same data
                        if let idx = self.connections.firstIndex(where: { $0.remoteAddress == addr }) {
                            if idx < self.rows.count {
                                self.rows[idx].update(conn: self.connections[idx], resolvedHost: self.resolvedHosts[addr], isAlternate: idx % 2 == 1)
                            }
                        }
                    }
                }
            }
        }

        layoutContent()
    }

    private func showEmpty(_ message: String) {
        connections.removeAll()
        rows.forEach { $0.removeFromSuperview() }
        rows.removeAll()
        headerRow.isHidden = true
        emptyLabel.isHidden = false
        emptyLabel.stringValue = message
        layoutContent()
    }

    override func layoutContent() {
        let headerHeight: CGFloat = 24
        let rowHeight: CGFloat = 26
        let totalHeight = max(headerHeight + CGFloat(rows.count) * rowHeight, scrollView.bounds.height)
        contentView.frame = NSRect(x: 0, y: 0, width: scrollView.bounds.width, height: totalHeight)

        headerRow.frame = NSRect(x: 0, y: totalHeight - headerHeight, width: scrollView.bounds.width, height: headerHeight)

        for (i, row) in rows.enumerated() {
            let y = totalHeight - headerHeight - CGFloat(i + 1) * rowHeight
            row.frame = NSRect(x: 0, y: y, width: scrollView.bounds.width, height: rowHeight)
        }

        emptyLabel.frame = NSRect(x: 0, y: (totalHeight - 20) / 2, width: scrollView.bounds.width, height: 20)
    }
}

// MARK: - Connection Header Row

private final class ConnectionHeaderRow: NSView {
    private let processLabel = NSTextField(labelWithString: "PROCESS")
    private let protoLabel = NSTextField(labelWithString: "PROTO")
    private let remoteLabel = NSTextField(labelWithString: "REMOTE")
    private let portLabel = NSTextField(labelWithString: "PORT")
    private let stateLabel = NSTextField(labelWithString: "STATE")

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = NSColor(white: 1.0, alpha: 0.03).cgColor

        for label in [processLabel, protoLabel, remoteLabel, portLabel, stateLabel] {
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
        let cols = columnLayout(width: bounds.width)
        processLabel.frame = NSRect(x: cols.process.x, y: (h - 12) / 2, width: cols.process.w, height: 12)
        protoLabel.frame = NSRect(x: cols.proto.x, y: (h - 12) / 2, width: cols.proto.w, height: 12)
        remoteLabel.frame = NSRect(x: cols.remote.x, y: (h - 12) / 2, width: cols.remote.w, height: 12)
        portLabel.frame = NSRect(x: cols.port.x, y: (h - 12) / 2, width: cols.port.w, height: 12)
        stateLabel.frame = NSRect(x: cols.state.x, y: (h - 12) / 2, width: cols.state.w, height: 12)
    }
}

// MARK: - Connection Row

private final class ConnectionRow: NSView {
    private let processLabel = NSTextField(labelWithString: "")
    private let protoLabel = NSTextField(labelWithString: "")
    private let remoteLabel = NSTextField(labelWithString: "")
    private let portLabel = NSTextField(labelWithString: "")
    private let stateLabel = NSTextField(labelWithString: "")
    private let stateIndicator = NSView()

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true

        stateIndicator.wantsLayer = true
        stateIndicator.layer?.cornerRadius = 3
        addSubview(stateIndicator)

        for label in [processLabel, protoLabel, remoteLabel, portLabel, stateLabel] {
            label.isEditable = false
            label.isBezeled = false
            label.drawsBackground = false
            label.lineBreakMode = .byTruncatingTail
            label.maximumNumberOfLines = 1
            addSubview(label)
        }

        processLabel.font = .monospacedSystemFont(ofSize: 11, weight: .medium)
        processLabel.textColor = Theme.textPrimary

        protoLabel.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        protoLabel.textColor = Theme.textSecondary

        remoteLabel.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        remoteLabel.textColor = Theme.textPrimary

        portLabel.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        portLabel.textColor = Theme.textSecondary

        stateLabel.font = .monospacedSystemFont(ofSize: 10, weight: .semibold)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func update(conn: ConnectionInfo, resolvedHost: String?, isAlternate: Bool) {
        layer?.backgroundColor = isAlternate
            ? NSColor(white: 1.0, alpha: 0.02).cgColor
            : NSColor.clear.cgColor

        processLabel.stringValue = conn.processName
        protoLabel.stringValue = conn.protocolName
        remoteLabel.stringValue = resolvedHost ?? conn.remoteAddress
        portLabel.stringValue = conn.remotePort > 0 ? "\(conn.remotePort)" : "—"

        stateLabel.stringValue = conn.state
        let stateColor = Self.colorForState(conn.state)
        stateLabel.textColor = stateColor
        stateIndicator.layer?.backgroundColor = stateColor.withAlphaComponent(0.3).cgColor

        needsLayout = true
    }

    private static func colorForState(_ state: String) -> NSColor {
        switch state {
        case "ESTABLISHED": return NSColor.systemGreen
        case "LISTEN":      return NSColor.systemBlue
        case "SYN_SENT":    return NSColor.systemYellow
        case "CLOSE_WAIT":  return NSColor.systemOrange
        case "TIME_WAIT":   return NSColor(white: 0.4, alpha: 1)
        default:            return Theme.textMuted
        }
    }

    override func layout() {
        super.layout()
        let h = bounds.height
        let cols = columnLayout(width: bounds.width)

        processLabel.frame = NSRect(x: cols.process.x, y: (h - 14) / 2, width: cols.process.w, height: 14)
        protoLabel.frame = NSRect(x: cols.proto.x, y: (h - 14) / 2, width: cols.proto.w, height: 14)
        remoteLabel.frame = NSRect(x: cols.remote.x, y: (h - 14) / 2, width: cols.remote.w, height: 14)
        portLabel.frame = NSRect(x: cols.port.x, y: (h - 14) / 2, width: cols.port.w, height: 14)

        stateIndicator.frame = NSRect(x: cols.state.x - 2, y: (h - 6) / 2, width: 6, height: 6)
        stateLabel.frame = NSRect(x: cols.state.x + 8, y: (h - 14) / 2, width: cols.state.w - 8, height: 14)
    }
}

// MARK: - Column Layout

private struct ColRect {
    let x: CGFloat
    let w: CGFloat
}

private struct ColumnLayout {
    let process: ColRect
    let proto: ColRect
    let remote: ColRect
    let port: ColRect
    let state: ColRect
}

private func columnLayout(width: CGFloat) -> ColumnLayout {
    let pad: CGFloat = 12
    let processW: CGFloat = max(100, width * 0.18)
    let protoW: CGFloat = 44
    let portW: CGFloat = 52
    let stateW: CGFloat = 96
    let remoteW = max(100, width - pad - processW - 8 - protoW - 8 - portW - 8 - stateW - pad)

    var x = pad
    let process = ColRect(x: x, w: processW); x += processW + 8
    let proto = ColRect(x: x, w: protoW); x += protoW + 8
    let remote = ColRect(x: x, w: remoteW); x += remoteW + 8
    let port = ColRect(x: x, w: portW); x += portW + 8
    let state = ColRect(x: x, w: stateW)

    return ColumnLayout(process: process, proto: proto, remote: remote, port: port, state: state)
}
