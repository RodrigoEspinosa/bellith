import AppKit

/// Floating HUD overlay that shows contextual info:
/// git branch, working directory, time.
/// Fades in on trigger, fades out on release or after a delay.
final class HUDView: NSView {
    private let backdrop = NSVisualEffectView()
    private let stackView = NSStackView()
    private var hideTimer: Timer?

    private let cwdLabel = HUDItem(icon: "folder.fill", color: Theme.accent)
    private let gitLabel = HUDItem(icon: "arrow.triangle.branch", color: Theme.success)
    private let shellLabel = HUDItem(icon: "terminal.fill", color: Theme.textSecondary)
    private let processLabel = HUDItem(icon: "gearshape.fill", color: Theme.warning)
    private let sizeLabel = HUDItem(icon: "rectangle.split.3x3", color: Theme.textSecondary)
    private let timeLabel = HUDItem(icon: "clock.fill", color: Theme.textMuted)

    override init(frame: NSRect) {
        super.init(frame: frame)
        setupViews()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    private func setupViews() {
        wantsLayer = true
        alphaValue = 0
        layer?.cornerRadius = Theme.radiusPanel
        layer?.masksToBounds = true

        // Shadow
        shadow = NSShadow()
        layer?.shadowColor = NSColor.black.withAlphaComponent(0.4).cgColor
        layer?.shadowOffset = CGSize(width: 0, height: -2)
        layer?.shadowRadius = 12
        layer?.shadowOpacity = 1

        // Frosted backdrop
        backdrop.material = .sidebar
        backdrop.blendingMode = .withinWindow
        backdrop.state = .active
        backdrop.appearance = NSAppearance(named: .darkAqua)
        addSubview(backdrop)

        // Border
        let border = CALayer()
        border.borderColor = Theme.border.cgColor
        border.borderWidth = 0.5
        border.cornerRadius = Theme.radiusPanel
        layer?.addSublayer(border)

        // Stack of info items
        stackView.orientation = .vertical
        stackView.alignment = .leading
        stackView.spacing = 6
        stackView.edgeInsets = NSEdgeInsets(top: 12, left: 14, bottom: 12, right: 14)
        addSubview(stackView)

        let items: [NSView] = [cwdLabel, gitLabel, shellLabel, processLabel, sizeLabel, timeLabel]
        for (index, item) in items.enumerated() {
            stackView.addArrangedSubview(item)
            if index < items.count - 1 {
                let separator = NSView()
                separator.wantsLayer = true
                separator.layer?.backgroundColor = Theme.border.cgColor
                separator.translatesAutoresizingMaskIntoConstraints = false
                separator.heightAnchor.constraint(equalToConstant: 1).isActive = true
                stackView.addArrangedSubview(separator)
                // Stretch separator to full width
                separator.leadingAnchor.constraint(equalTo: stackView.leadingAnchor, constant: 14).isActive = true
                separator.trailingAnchor.constraint(equalTo: stackView.trailingAnchor, constant: -14).isActive = true
            }
        }
    }

    override func layout() {
        super.layout()
        backdrop.frame = bounds
        stackView.frame = bounds
        // Update border sublayer
        if let border = layer?.sublayers?.first(where: { $0.borderWidth > 0 }) {
            border.frame = bounds
        }
    }

    // MARK: - Data

    var currentCwd: String = "~"
    var shellPID: pid_t?
    var terminalSize: (cols: Int, rows: Int)?

    func refresh() {
        // Working directory
        let cwd = currentCwd
        let home = NSHomeDirectory()
        let displayPath = cwd.hasPrefix(home) ? "~" + cwd.dropFirst(home.count) : cwd
        cwdLabel.text = String(displayPath)

        // Time
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        timeLabel.text = formatter.string(from: Date())

        // Terminal size
        if let size = terminalSize {
            sizeLabel.text = "\(size.cols)\u{00D7}\(size.rows)"
            sizeLabel.isHidden = false
        } else {
            sizeLabel.isHidden = true
        }

        // Shell info — run off main thread
        gitLabel.text = "..."
        gitLabel.isHidden = false
        processLabel.isHidden = true
        shellLabel.isHidden = true

        let cwdForGit = cwd
        let pid = shellPID

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let branch = Self.gitBranch(in: cwdForGit)

            // Get shell name and foreground process
            var shellName: String?
            var foregroundProcess: String?
            if let pid {
                shellName = ProcessMonitor.processName(for: pid)
                if let tree = ProcessMonitor.processTree(rootPID: pid) {
                    // The deepest child that's not the shell itself is the foreground process
                    var deepest: TerminalProcessInfo?
                    func findDeepest(_ node: TerminalProcessInfo) {
                        if node.children.isEmpty && node.pid != pid {
                            deepest = node
                        }
                        for child in node.children { findDeepest(child) }
                    }
                    findDeepest(tree)
                    if let d = deepest, d.name.lowercased() != shellName?.lowercased() {
                        foregroundProcess = d.name
                    }
                }
            }

            DispatchQueue.main.async {
                guard let self else { return }
                if let branch {
                    self.gitLabel.text = branch
                    self.gitLabel.isHidden = false
                } else {
                    self.gitLabel.isHidden = true
                }
                if let shellName {
                    self.shellLabel.text = shellName
                    self.shellLabel.isHidden = false
                } else {
                    self.shellLabel.isHidden = true
                }
                if let foregroundProcess {
                    self.processLabel.text = foregroundProcess
                    self.processLabel.isHidden = false
                } else {
                    self.processLabel.isHidden = true
                }
            }
        }
    }

    private static func gitBranch(in directory: String) -> String? {
        let pipe = Pipe()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["-C", directory, "branch", "--show-current"]
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
            return output?.isEmpty == false ? output : nil
        } catch {
            return nil
        }
    }

    // MARK: - Show / Hide

    func show(in parent: NSView) {
        refresh()

        let width: CGFloat = 260
        // Count visible items
        var itemCount = 2 // cwd + time are always visible
        if !gitLabel.isHidden { itemCount += 1 }
        if !shellLabel.isHidden { itemCount += 1 }
        if !processLabel.isHidden { itemCount += 1 }
        if !sizeLabel.isHidden { itemCount += 1 }
        let height: CGFloat = CGFloat(itemCount) * 24 + 24
        let x = parent.bounds.width - width - 16
        let y = parent.bounds.height - height - 48

        frame = NSRect(x: x, y: y, width: width, height: height)

        let isNew = superview == nil
        if isNew {
            parent.addSubview(self)
        }

        hideTimer?.invalidate()

        // Slide-in from right entrance for first show
        if isNew {
            layer?.setAffineTransform(CGAffineTransform(translationX: 10, y: 0))
        }

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = Theme.animMedium
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            ctx.allowsImplicitAnimation = true
            self.animator().alphaValue = 1
            self.layer?.setAffineTransform(.identity)
        }
    }

    func hide() {
        hideTimer?.invalidate()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = Theme.animMedium
            ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
            self.animator().alphaValue = 0
        } completionHandler: {
            self.removeFromSuperview()
        }
    }

    func scheduleHide(after interval: TimeInterval = 3.0) {
        hideTimer?.invalidate()
        hideTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { [weak self] _ in
            self?.hide()
        }
    }
}

// MARK: - HUD Item Row

private final class HUDItem: NSView {
    private let iconView = NSImageView()
    private let label = NSTextField(labelWithString: "")

    var text: String {
        get { label.stringValue }
        set { label.stringValue = newValue }
    }

    init(icon: String, color: NSColor) {
        super.init(frame: .zero)

        iconView.image = NSImage(systemSymbolName: icon, accessibilityDescription: nil)
        iconView.contentTintColor = color
        addSubview(iconView)

        label.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        label.textColor = Theme.textPrimary
        label.lineBreakMode = .byTruncatingMiddle
        addSubview(label)

        translatesAutoresizingMaskIntoConstraints = false
        heightAnchor.constraint(equalToConstant: 18).isActive = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        iconView.frame = NSRect(x: 0, y: (bounds.height - 14) / 2, width: 14, height: 14)
        label.frame = NSRect(x: 20, y: (bounds.height - 14) / 2, width: bounds.width - 24, height: 14)
    }
}
