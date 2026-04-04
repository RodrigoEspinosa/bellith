import AppKit
import Darwin

/// Smart panel that displays environment variables for the shell process.
final class EnvironmentPanel: SmartPanelView {
    private var rows: [EnvVarRow] = []
    private var envVars: [(key: String, value: String)] = []
    private var filteredVars: [(key: String, value: String)] = []
    private let headerRow = EnvVarHeaderRow()
    private let searchField = NSTextField()
    private let emptyLabel = NSTextField(labelWithString: "")
    private var searchQuery: String = ""

    init() {
        super.init(kind: .environment)

        setupSearchField()

        contentView.addSubview(headerRow)

        emptyLabel.font = .systemFont(ofSize: 12, weight: .regular)
        emptyLabel.textColor = Theme.textMuted
        emptyLabel.alignment = .center
        emptyLabel.isEditable = false
        emptyLabel.isBezeled = false
        emptyLabel.drawsBackground = false
        contentView.addSubview(emptyLabel)
    }

    override func startRefreshing(interval: TimeInterval = 5.0) {
        super.startRefreshing(interval: interval)
    }

    private func setupSearchField() {
        searchField.placeholderString = "Filter variables\u{2026}"
        searchField.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        searchField.textColor = Theme.textPrimary
        searchField.backgroundColor = Theme.surface
        searchField.isBordered = true
        searchField.bezelStyle = .roundedBezel
        searchField.focusRingType = .none
        searchField.target = self
        searchField.action = #selector(searchChanged)
        searchField.delegate = self
        addSubview(searchField)
    }

    @objc private func searchChanged() {
        searchQuery = searchField.stringValue
        applyFilter()
    }

    private func applyFilter() {
        if searchQuery.isEmpty {
            filteredVars = envVars
        } else {
            let query = searchQuery.lowercased()
            filteredVars = envVars.filter { entry in
                entry.key.lowercased().contains(query) || entry.value.lowercased().contains(query)
            }
        }

        if filteredVars.isEmpty && !envVars.isEmpty {
            showEmpty("No matching variables")
        } else if filteredVars.isEmpty {
            // Already showing empty from refresh
        } else {
            updateRows(filteredVars)
        }
    }

    // MARK: - Refresh

    override func refresh() {
        guard let pid = shellPID else {
            showEmpty("No shell process")
            return
        }

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let vars = EnvironmentPanel.environmentVariables(for: pid)
            DispatchQueue.main.async {
                guard let self else { return }
                if vars.isEmpty {
                    self.envVars = []
                    self.showEmpty("No environment variables")
                } else {
                    self.envVars = vars
                    self.applyFilter()
                }
            }
        }
    }

    private func updateRows(_ vars: [(key: String, value: String)]) {
        emptyLabel.isHidden = true
        headerRow.isHidden = false

        while rows.count > vars.count {
            rows.removeLast().removeFromSuperview()
        }
        while rows.count < vars.count {
            let row = EnvVarRow()
            contentView.addSubview(row)
            rows.append(row)
        }

        for (i, entry) in vars.enumerated() {
            rows[i].update(key: entry.key, value: entry.value, isAlternate: i % 2 == 1)
        }

        layoutContent()
    }

    private func showEmpty(_ message: String) {
        filteredVars.removeAll()
        rows.forEach { $0.removeFromSuperview() }
        rows.removeAll()
        headerRow.isHidden = true
        emptyLabel.isHidden = false
        emptyLabel.stringValue = message
        layoutContent()
    }

    // MARK: - Layout

    private let searchFieldHeight: CGFloat = 28
    private let searchFieldPadding: CGFloat = 8

    override func layout() {
        super.layout()

        // Position search field between the panel header and the scroll view
        let headerHeight: CGFloat = 36
        let searchY = bounds.height - headerHeight - searchFieldPadding - searchFieldHeight
        searchField.frame = NSRect(
            x: searchFieldPadding,
            y: searchY,
            width: bounds.width - searchFieldPadding * 2,
            height: searchFieldHeight
        )

        let scrollTop = searchY - searchFieldPadding
        scrollView.frame = NSRect(x: 0, y: 0, width: bounds.width, height: scrollTop)
        layoutContent()
    }

    override func layoutContent() {
        let headerHeight: CGFloat = 24
        let rowHeight: CGFloat = 26
        let rowCount = filteredVars.isEmpty && !emptyLabel.isHidden ? 0 : rows.count
        let totalHeight = max(headerHeight + CGFloat(rowCount) * rowHeight, scrollView.bounds.height)
        contentView.frame = NSRect(x: 0, y: 0, width: scrollView.bounds.width, height: totalHeight)

        headerRow.frame = NSRect(x: 0, y: totalHeight - headerHeight, width: scrollView.bounds.width, height: headerHeight)

        for (i, row) in rows.enumerated() {
            let y = totalHeight - headerHeight - CGFloat(i + 1) * rowHeight
            row.frame = NSRect(x: 0, y: y, width: scrollView.bounds.width, height: rowHeight)
        }

        emptyLabel.frame = NSRect(x: 0, y: (totalHeight - 20) / 2, width: scrollView.bounds.width, height: 20)
    }

    // MARK: - Environment Variable Extraction

    /// Read environment variables from a process using sysctl KERN_PROCARGS2.
    ///
    /// The KERN_PROCARGS2 buffer layout is:
    ///   [argc: Int32] [exec_path\0] [padding\0...] [argv[0]\0 argv[1]\0 ...] [env[0]\0 env[1]\0 ...]
    ///
    /// We skip past argc, the exec path, any null padding, then skip `argc` argv strings
    /// to reach the environment variables (KEY=VALUE null-terminated strings).
    static func environmentVariables(for pid: pid_t) -> [(key: String, value: String)] {
        var mib: [Int32] = [CTL_KERN, KERN_PROCARGS2, pid]
        var size: Int = 0
        guard sysctl(&mib, 3, nil, &size, nil, 0) == 0, size > 0 else { return [] }

        var buffer = [UInt8](repeating: 0, count: size)
        guard sysctl(&mib, 3, &buffer, &size, nil, 0) == 0 else { return [] }
        guard size > MemoryLayout<Int32>.size else { return [] }

        // Read argc
        var argc: Int32 = 0
        memcpy(&argc, &buffer, MemoryLayout<Int32>.size)

        var pos = MemoryLayout<Int32>.size

        // Skip the exec path (null-terminated)
        while pos < size && buffer[pos] != 0 { pos += 1 }
        // Skip past the null terminator
        guard pos < size else { return [] }
        pos += 1

        // Skip any padding null bytes between exec path and argv[0]
        while pos < size && buffer[pos] == 0 { pos += 1 }

        // Skip argc argv strings (each null-terminated)
        var argSkipped: Int32 = 0
        while argSkipped < argc && pos < size {
            // Advance past this null-terminated string
            while pos < size && buffer[pos] != 0 { pos += 1 }
            guard pos < size else { return [] }
            pos += 1 // skip null terminator
            argSkipped += 1
        }

        // Now we are at the environment variables — null-terminated KEY=VALUE strings
        var result: [(key: String, value: String)] = []

        while pos < size {
            // Skip any stray null bytes between env entries
            if buffer[pos] == 0 {
                pos += 1
                continue
            }

            // Find the end of this null-terminated string
            let start = pos
            while pos < size && buffer[pos] != 0 { pos += 1 }

            guard let str = String(bytes: buffer[start..<pos], encoding: .utf8), !str.isEmpty else {
                pos += 1
                continue
            }

            // Split on first '='
            if let eqIdx = str.firstIndex(of: "=") {
                let key = String(str[str.startIndex..<eqIdx])
                let value = String(str[str.index(after: eqIdx)...])
                if !key.isEmpty {
                    result.append((key: key, value: value))
                }
            }

            // Skip past the null terminator
            if pos < size { pos += 1 }
        }

        return result.sorted { $0.key.localizedCaseInsensitiveCompare($1.key) == .orderedAscending }
    }
}

// MARK: - NSTextFieldDelegate

extension EnvironmentPanel: NSTextFieldDelegate {
    func controlTextDidChange(_ obj: Notification) {
        searchChanged()
    }
}

// MARK: - Environment Variable Header Row

private final class EnvVarHeaderRow: NSView {
    private let keyLabel = NSTextField(labelWithString: "KEY")
    private let valueLabel = NSTextField(labelWithString: "VALUE")

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = NSColor(white: 1.0, alpha: 0.03).cgColor

        for label in [keyLabel, valueLabel] {
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
        let cols = envColumnLayout(width: bounds.width)
        keyLabel.frame = NSRect(x: cols.key.x, y: (h - 12) / 2, width: cols.key.w, height: 12)
        valueLabel.frame = NSRect(x: cols.value.x, y: (h - 12) / 2, width: cols.value.w, height: 12)
    }
}

// MARK: - Environment Variable Row

private final class EnvVarRow: NSView {
    private let keyLabel = NSTextField(labelWithString: "")
    private let valueLabel = NSTextField(labelWithString: "")

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true

        for label in [keyLabel, valueLabel] {
            label.isEditable = false
            label.isBezeled = false
            label.drawsBackground = false
            label.lineBreakMode = .byTruncatingTail
            label.maximumNumberOfLines = 1
            addSubview(label)
        }

        keyLabel.font = .monospacedSystemFont(ofSize: 11, weight: .medium)
        keyLabel.textColor = Theme.accent

        valueLabel.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        valueLabel.textColor = Theme.textPrimary
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func update(key: String, value: String, isAlternate: Bool) {
        layer?.backgroundColor = isAlternate
            ? NSColor(white: 1.0, alpha: 0.02).cgColor
            : NSColor.clear.cgColor

        keyLabel.stringValue = key
        valueLabel.stringValue = value
        needsLayout = true
    }

    override func layout() {
        super.layout()
        let h = bounds.height
        let cols = envColumnLayout(width: bounds.width)
        keyLabel.frame = NSRect(x: cols.key.x, y: (h - 14) / 2, width: cols.key.w, height: 14)
        valueLabel.frame = NSRect(x: cols.value.x, y: (h - 14) / 2, width: cols.value.w, height: 14)
    }
}

// MARK: - Column Layout

private struct EnvColRect {
    let x: CGFloat
    let w: CGFloat
}

private struct EnvColumnLayout {
    let key: EnvColRect
    let value: EnvColRect
}

private func envColumnLayout(width: CGFloat) -> EnvColumnLayout {
    let pad: CGFloat = 12
    let gap: CGFloat = 8
    let keyW: CGFloat = max(120, width * 0.30)
    let valueW = max(100, width - pad - keyW - gap - pad)

    var x = pad
    let key = EnvColRect(x: x, w: keyW); x += keyW + gap
    let value = EnvColRect(x: x, w: valueW)

    return EnvColumnLayout(key: key, value: value)
}
