import AppKit
import Darwin

/// Information about a single open file descriptor.
private struct FileDescriptorInfo {
    let pid: pid_t
    let processName: String
    let fd: Int32
    let fdType: String        // "file", "pipe", "kqueue", "other"
    let path: String          // vnode path or description
    let stdLabel: String?     // "stdin", "stdout", "stderr" for fd 0,1,2
}

/// Smart panel that shows open file descriptors for the shell's process tree.
/// Skips socket FDs (handled by NetworkPanel). Uses proc_pidinfo / proc_pidfdinfo
/// to enumerate vnode paths for each process.
final class FileActivityPanel: SmartPanelView {
    static let plugin = SmartPanelPlugin(
        id: "fileActivity",
        title: "Files",
        iconName: "doc.text.magnifyingglass",
        commandDescription: "View open files",
        commandAliases: ["files", "file activity"]
    ) {
        FileActivityPanel()
    }

    private var rows: [FileDescriptorRow] = []
    private var allEntries: [FileDescriptorInfo] = []
    private var filteredEntries: [FileDescriptorInfo] = []
    private let headerRow = FileDescriptorHeaderRow()
    private let emptyLabel = NSTextField(labelWithString: "")
    private let searchField = NSTextField()

    init() {
        super.init(plugin: Self.plugin)

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

    // MARK: - Search Field

    private func setupSearchField() {
        searchField.placeholderString = "Filter by process, path, or type..."
        searchField.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        searchField.textColor = Theme.textPrimary
        searchField.backgroundColor = Theme.surface
        searchField.isBezeled = true
        searchField.bezelStyle = .roundedBezel
        searchField.focusRingType = .none
        searchField.target = self
        searchField.action = #selector(searchChanged)
        (searchField.cell as? NSSearchFieldCell)?.sendsSearchStringImmediately = true
        searchField.cell?.sendsActionOnEndEditing = true
        addSubview(searchField)
    }

    @objc private func searchChanged() {
        applyFilter()
    }

    private func applyFilter() {
        let query = searchField.stringValue.lowercased().trimmingCharacters(in: .whitespaces)
        if query.isEmpty {
            filteredEntries = allEntries
        } else {
            filteredEntries = allEntries.filter { entry in
                entry.processName.lowercased().contains(query)
                    || entry.path.lowercased().contains(query)
                    || entry.fdType.lowercased().contains(query)
                    || (entry.stdLabel?.lowercased().contains(query) ?? false)
                    || "\(entry.fd)".contains(query)
            }
        }
        updateRows()
    }

    // MARK: - Refresh

    override func refresh() {
        guard let pid = shellPID else {
            showEmpty("No shell process")
            return
        }

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let pids = ProcessMonitor.allDescendants(of: pid)
            var entries: [FileDescriptorInfo] = []

            for p in pids {
                entries.append(contentsOf: Self.fileDescriptors(for: p))
            }

            // Sort by process name then FD number
            entries.sort {
                if $0.processName != $1.processName {
                    return $0.processName.localizedCaseInsensitiveCompare($1.processName) == .orderedAscending
                }
                return $0.fd < $1.fd
            }

            DispatchQueue.main.async {
                guard let self else { return }
                self.allEntries = entries
                self.applyFilter()
            }
        }
    }

    // MARK: - libproc FD Enumeration

    private static func fileDescriptors(for pid: pid_t) -> [FileDescriptorInfo] {
        let name = processName(pid: pid)

        // Get FD list size
        let bufSize = proc_pidinfo(pid, PROC_PIDLISTFDS, 0, nil, 0)
        guard bufSize > 0 else { return [] }

        let fdCount = Int(bufSize) / MemoryLayout<proc_fdinfo>.size
        var fdInfos = [proc_fdinfo](repeating: proc_fdinfo(), count: fdCount)
        let actual = proc_pidinfo(pid, PROC_PIDLISTFDS, 0, &fdInfos, bufSize)
        guard actual > 0 else { return [] }

        let actualCount = Int(actual) / MemoryLayout<proc_fdinfo>.size
        var results: [FileDescriptorInfo] = []

        for i in 0..<actualCount {
            let fd = fdInfos[i]

            // Skip sockets — those are handled by NetworkPanel
            if fd.proc_fdtype == PROX_FDTYPE_SOCKET { continue }

            let fdNum = fd.proc_fd
            let stdLabel = Self.stdLabel(for: fdNum)

            switch Int32(fd.proc_fdtype) {
            case PROX_FDTYPE_VNODE:
                let path = vnodePath(pid: pid, fd: fdNum)
                results.append(FileDescriptorInfo(
                    pid: pid, processName: name, fd: fdNum,
                    fdType: "file", path: path ?? "???",
                    stdLabel: stdLabel
                ))

            case PROX_FDTYPE_PIPE:
                results.append(FileDescriptorInfo(
                    pid: pid, processName: name, fd: fdNum,
                    fdType: "pipe", path: "pipe",
                    stdLabel: stdLabel
                ))

            case PROX_FDTYPE_KQUEUE:
                results.append(FileDescriptorInfo(
                    pid: pid, processName: name, fd: fdNum,
                    fdType: "kqueue", path: "kqueue",
                    stdLabel: stdLabel
                ))

            default:
                results.append(FileDescriptorInfo(
                    pid: pid, processName: name, fd: fdNum,
                    fdType: "other", path: "fd:\(fdNum)",
                    stdLabel: stdLabel
                ))
            }
        }

        return results
    }

    /// Resolve a vnode FD to its file path using PROC_PIDFDVNODEPATHINFO.
    private static func vnodePath(pid: pid_t, fd: Int32) -> String? {
        var vnodeInfo = vnode_fdinfowithpath()
        let size = MemoryLayout<vnode_fdinfowithpath>.size
        let ret = proc_pidfdinfo(
            pid, fd, PROC_PIDFDVNODEPATHINFO,
            &vnodeInfo, Int32(size)
        )
        guard ret == size else { return nil }
        return withUnsafePointer(to: vnodeInfo.pvip.vip_path) { ptr in
            ptr.withMemoryRebound(to: CChar.self, capacity: Int(MAXPATHLEN)) {
                String(cString: $0)
            }
        }
    }

    private static func stdLabel(for fd: Int32) -> String? {
        switch fd {
        case 0: return "stdin"
        case 1: return "stdout"
        case 2: return "stderr"
        default: return nil
        }
    }

    private static func processName(pid: pid_t) -> String {
        var buffer = [CChar](repeating: 0, count: Int(MAXPATHLEN))
        let ret = proc_name(pid, &buffer, UInt32(buffer.count))
        return ret > 0 ? String(cString: buffer) : "pid:\(pid)"
    }

    // MARK: - Row Management

    private func updateRows() {
        let entries = filteredEntries

        if entries.isEmpty {
            let message = allEntries.isEmpty ? "No open files" : "No matches"
            showEmpty(message)
            return
        }

        emptyLabel.isHidden = true
        headerRow.isHidden = false

        // Recycle rows
        while rows.count > entries.count {
            rows.removeLast().removeFromSuperview()
        }
        while rows.count < entries.count {
            let row = FileDescriptorRow()
            contentView.addSubview(row)
            rows.append(row)
        }

        for (i, entry) in entries.enumerated() {
            rows[i].update(entry: entry, isAlternate: i % 2 == 1)
        }

        layoutContent()
    }

    private func showEmpty(_ message: String) {
        filteredEntries.removeAll()
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

        // Position search field between header and scroll view
        let headerH: CGFloat = 36
        let sfY = bounds.height - headerH - searchFieldPadding - searchFieldHeight
        searchField.frame = NSRect(
            x: 8, y: sfY,
            width: bounds.width - 16, height: searchFieldHeight
        )

        // Adjust scroll view to sit below the search field
        let scrollTop = sfY - searchFieldPadding
        scrollView.frame = NSRect(x: 0, y: 0, width: bounds.width, height: scrollTop)
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

// MARK: - Header Row

private final class FileDescriptorHeaderRow: NSView {
    private let processLabel = NSTextField(labelWithString: "PROCESS")
    private let fdLabel = NSTextField(labelWithString: "FD#")
    private let typeLabel = NSTextField(labelWithString: "TYPE")
    private let pathLabel = NSTextField(labelWithString: "PATH")

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = NSColor(white: 1.0, alpha: 0.03).cgColor

        for label in [processLabel, fdLabel, typeLabel, pathLabel] {
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
        let cols = fileColumnLayout(width: bounds.width)
        processLabel.frame = NSRect(x: cols.process.x, y: (h - 12) / 2, width: cols.process.w, height: 12)
        fdLabel.frame = NSRect(x: cols.fd.x, y: (h - 12) / 2, width: cols.fd.w, height: 12)
        typeLabel.frame = NSRect(x: cols.type.x, y: (h - 12) / 2, width: cols.type.w, height: 12)
        pathLabel.frame = NSRect(x: cols.path.x, y: (h - 12) / 2, width: cols.path.w, height: 12)
    }
}

// MARK: - Data Row

private final class FileDescriptorRow: NSView {
    private let processLabel = NSTextField(labelWithString: "")
    private let fdLabel = NSTextField(labelWithString: "")
    private let typeLabel = NSTextField(labelWithString: "")
    private let pathLabel = NSTextField(labelWithString: "")
    private let stdBadge = NSTextField(labelWithString: "")

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true

        for label in [processLabel, fdLabel, typeLabel, pathLabel] {
            label.isEditable = false
            label.isBezeled = false
            label.drawsBackground = false
            label.lineBreakMode = .byTruncatingTail
            label.maximumNumberOfLines = 1
            addSubview(label)
        }

        processLabel.font = .monospacedSystemFont(ofSize: 11, weight: .medium)
        processLabel.textColor = Theme.textPrimary

        fdLabel.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        fdLabel.textColor = Theme.textSecondary

        typeLabel.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        typeLabel.textColor = Theme.textSecondary

        pathLabel.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        pathLabel.textColor = Theme.textPrimary
        pathLabel.lineBreakMode = .byTruncatingMiddle

        // Badge for stdin/stdout/stderr
        stdBadge.font = .monospacedSystemFont(ofSize: 9, weight: .semibold)
        stdBadge.alignment = .center
        stdBadge.isEditable = false
        stdBadge.isBezeled = false
        stdBadge.drawsBackground = false
        stdBadge.wantsLayer = true
        stdBadge.layer?.cornerRadius = 3
        addSubview(stdBadge)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func update(entry: FileDescriptorInfo, isAlternate: Bool) {
        layer?.backgroundColor = isAlternate
            ? NSColor(white: 1.0, alpha: 0.02).cgColor
            : NSColor.clear.cgColor

        processLabel.stringValue = entry.processName

        if let label = entry.stdLabel {
            fdLabel.stringValue = "\(entry.fd)"
            stdBadge.isHidden = false
            stdBadge.stringValue = label
            stdBadge.textColor = colorForStdFd(entry.fd)
            stdBadge.layer?.backgroundColor = colorForStdFd(entry.fd).withAlphaComponent(0.15).cgColor
        } else {
            fdLabel.stringValue = "\(entry.fd)"
            stdBadge.isHidden = true
        }

        typeLabel.stringValue = entry.fdType
        typeLabel.textColor = colorForType(entry.fdType)

        pathLabel.stringValue = entry.path

        needsLayout = true
    }

    private func colorForType(_ type: String) -> NSColor {
        switch type {
        case "file":   return NSColor.systemGreen
        case "pipe":   return NSColor.systemBlue
        case "kqueue": return NSColor.systemOrange
        default:       return Theme.textMuted
        }
    }

    private func colorForStdFd(_ fd: Int32) -> NSColor {
        switch fd {
        case 0: return NSColor.systemCyan    // stdin
        case 1: return NSColor.systemGreen   // stdout
        case 2: return NSColor.systemRed     // stderr
        default: return Theme.textMuted
        }
    }

    override func layout() {
        super.layout()
        let h = bounds.height
        let cols = fileColumnLayout(width: bounds.width)

        processLabel.frame = NSRect(x: cols.process.x, y: (h - 14) / 2, width: cols.process.w, height: 14)
        fdLabel.frame = NSRect(x: cols.fd.x, y: (h - 14) / 2, width: 28, height: 14)

        if !stdBadge.isHidden {
            let badgeW: CGFloat = 42
            stdBadge.frame = NSRect(x: cols.fd.x + 30, y: (h - 14) / 2, width: badgeW, height: 14)
        }

        typeLabel.frame = NSRect(x: cols.type.x, y: (h - 14) / 2, width: cols.type.w, height: 14)
        pathLabel.frame = NSRect(x: cols.path.x, y: (h - 14) / 2, width: cols.path.w, height: 14)
    }
}

// MARK: - Column Layout

private struct FileColRect {
    let x: CGFloat
    let w: CGFloat
}

private struct FileColumnLayout {
    let process: FileColRect
    let fd: FileColRect
    let type: FileColRect
    let path: FileColRect
}

private func fileColumnLayout(width: CGFloat) -> FileColumnLayout {
    let pad: CGFloat = 12
    let processW: CGFloat = max(90, width * 0.16)
    let fdW: CGFloat = 76  // room for number + std badge
    let typeW: CGFloat = 56
    let pathW = max(100, width - pad - processW - 8 - fdW - 8 - typeW - 8 - pad)

    var x = pad
    let process = FileColRect(x: x, w: processW); x += processW + 8
    let fd = FileColRect(x: x, w: fdW); x += fdW + 8
    let type = FileColRect(x: x, w: typeW); x += typeW + 8
    let path = FileColRect(x: x, w: pathW)

    return FileColumnLayout(process: process, fd: fd, type: type, path: path)
}
