import AppKit

/// Floating HUD overlay that shows contextual info:
/// git branch, working directory, time.
/// Fades in on trigger, fades out on release or after a delay.
final class HUDView: NSView {
    private let backdrop = NSVisualEffectView()
    private let stackView = NSStackView()
    private var hideTimer: Timer?

    private let cwdLabel = HUDItem(icon: "folder.fill", color: Theme.accent)
    private let gitLabel = HUDItem(icon: "arrow.triangle.branch", color: NSColor.systemGreen)
    private let timeLabel = HUDItem(icon: "clock.fill", color: Theme.textSecondary)

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
        backdrop.blendingMode = .behindWindow
        backdrop.state = .active
        backdrop.appearance = NSAppearance(named: .darkAqua)
        addSubview(backdrop)

        // Border
        let border = CALayer()
        border.borderColor = NSColor(white: 1.0, alpha: 0.08).cgColor
        border.borderWidth = 0.5
        border.cornerRadius = Theme.radiusPanel
        layer?.addSublayer(border)

        // Stack of info items
        stackView.orientation = .vertical
        stackView.alignment = .leading
        stackView.spacing = 6
        stackView.edgeInsets = NSEdgeInsets(top: 12, left: 14, bottom: 12, right: 14)
        addSubview(stackView)

        stackView.addArrangedSubview(cwdLabel)
        stackView.addArrangedSubview(gitLabel)
        stackView.addArrangedSubview(timeLabel)
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

    func refresh() {
        // Working directory
        let cwd = currentCwd
        let home = NSHomeDirectory()
        let displayPath = cwd.hasPrefix(home) ? "~" + cwd.dropFirst(home.count) : cwd
        cwdLabel.text = String(displayPath)

        // Git branch
        let branch = gitBranch()
        if let branch {
            gitLabel.text = branch
            gitLabel.isHidden = false
        } else {
            gitLabel.isHidden = true
        }

        // Time
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        timeLabel.text = formatter.string(from: Date())
    }

    private func gitBranch() -> String? {
        let pipe = Pipe()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["-C", currentCwd, "branch", "--show-current"]
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

        let width: CGFloat = 240
        let height: CGFloat = gitLabel.isHidden ? 76 : 98
        let x = parent.bounds.width - width - 16
        let y = parent.bounds.height - height - 48

        frame = NSRect(x: x, y: y, width: width, height: height)

        if superview == nil {
            parent.addSubview(self)
        }

        hideTimer?.invalidate()

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = Theme.animFast
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            self.animator().alphaValue = 1
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

    func scheduleHide(after interval: TimeInterval = 2.0) {
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
