import AppKit

/// Always-visible status bar at the bottom of the terminal content area.
/// Shows cwd, git branch, foreground process, and terminal dimensions.
/// Designed to be a clear, readable strip — like VS Code's status bar.
final class StatusBarView: NSView {
    static let height: CGFloat = 30

    // Left items
    private let cwdIcon = NSImageView()
    private let cwdLabel = NSTextField(labelWithString: "~")
    private let separator1 = NSTextField(labelWithString: "·")
    private let gitIcon = NSImageView()
    private let gitLabel = NSTextField(labelWithString: "")
    private let separator2 = NSTextField(labelWithString: "·")
    private let processIcon = NSImageView()
    private let processLabel = NSTextField(labelWithString: "")

    // Right items
    private let sizeLabel = NSTextField(labelWithString: "")

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = Theme.surface.cgColor

        setupIcon(cwdIcon, symbol: "folder.fill", tint: Theme.accent)
        setupLabel(cwdLabel, size: 12, weight: .medium, color: Theme.textPrimary)

        setupSeparator(separator1)

        setupIcon(gitIcon, symbol: "arrow.triangle.branch", tint: Theme.success)
        setupLabel(gitLabel, size: 12, weight: .regular, color: Theme.textSecondary)
        gitIcon.isHidden = true
        gitLabel.isHidden = true
        separator1.isHidden = true

        setupSeparator(separator2)

        setupIcon(processIcon, symbol: "gearshape.fill", tint: Theme.warning)
        setupLabel(processLabel, size: 12, weight: .regular, color: Theme.textSecondary)
        processIcon.isHidden = true
        processLabel.isHidden = true
        separator2.isHidden = true

        setupLabel(sizeLabel, size: 11, weight: .medium, color: Theme.textMuted)
        sizeLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .medium)
        sizeLabel.alignment = .right
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    private func setupIcon(_ imageView: NSImageView, symbol: String, tint: NSColor) {
        imageView.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        imageView.contentTintColor = tint
        imageView.imageScaling = .scaleProportionallyDown
        addSubview(imageView)
    }

    private func setupLabel(_ label: NSTextField, size: CGFloat, weight: NSFont.Weight, color: NSColor) {
        label.font = .systemFont(ofSize: size, weight: weight)
        label.textColor = color
        label.isEditable = false
        label.isBezeled = false
        label.drawsBackground = false
        label.lineBreakMode = .byTruncatingMiddle
        label.maximumNumberOfLines = 1
        addSubview(label)
    }

    private func setupSeparator(_ label: NSTextField) {
        label.font = .systemFont(ofSize: 12, weight: .regular)
        label.textColor = Theme.textMuted.withAlphaComponent(0.5)
        label.isEditable = false
        label.isBezeled = false
        label.drawsBackground = false
        addSubview(label)
    }

    // MARK: - Update

    func updateCwd(_ cwd: String?) {
        guard let cwd else { cwdLabel.stringValue = "~"; return }
        let home = NSHomeDirectory()
        var display = cwd
        if display.hasPrefix(home) {
            display = "~" + display.dropFirst(home.count)
        }
        cwdLabel.stringValue = display
    }

    func updateGitBranch(_ branch: String?) {
        if let branch, !branch.isEmpty {
            gitLabel.stringValue = branch
            gitIcon.isHidden = false
            gitLabel.isHidden = false
            separator1.isHidden = false
        } else {
            gitIcon.isHidden = true
            gitLabel.isHidden = true
            separator1.isHidden = true
        }
        needsLayout = true
    }

    func updateProcess(_ name: String?) {
        if let name, !name.isEmpty {
            processLabel.stringValue = name
            processIcon.isHidden = false
            processLabel.isHidden = false
            separator2.isHidden = !gitIcon.isHidden // only show if git is also showing
        } else {
            processIcon.isHidden = true
            processLabel.isHidden = true
            separator2.isHidden = true
        }
        needsLayout = true
    }

    func updateSize(cols: Int, rows: Int) {
        sizeLabel.stringValue = "\(cols)×\(rows)"
    }

    // MARK: - Layout

    override func layout() {
        super.layout()
        let h = bounds.height
        let iconSize: CGFloat = 14
        let iconY = (h - iconSize) / 2
        let labelH: CGFloat = 16
        let labelY = (h - labelH) / 2
        let gap: CGFloat = 5
        let sepW: CGFloat = 8

        var x: CGFloat = 14

        // CWD
        cwdIcon.frame = NSRect(x: x, y: iconY, width: iconSize, height: iconSize)
        x += iconSize + gap
        let cwdW = min(260, cwdLabel.attributedStringValue.size().width + 6)
        cwdLabel.frame = NSRect(x: x, y: labelY, width: cwdW, height: labelH)
        x += cwdW

        // Git branch
        if !gitIcon.isHidden {
            x += 4
            separator1.frame = NSRect(x: x, y: labelY, width: sepW, height: labelH)
            x += sepW + 4

            gitIcon.frame = NSRect(x: x, y: iconY, width: iconSize, height: iconSize)
            x += iconSize + gap
            let gitW = min(140, gitLabel.attributedStringValue.size().width + 6)
            gitLabel.frame = NSRect(x: x, y: labelY, width: gitW, height: labelH)
            x += gitW
        }

        // Process
        if !processIcon.isHidden {
            if !separator2.isHidden {
                x += 4
                separator2.frame = NSRect(x: x, y: labelY, width: sepW, height: labelH)
                x += sepW + 4
            } else {
                x += 12
            }

            processIcon.frame = NSRect(x: x, y: iconY, width: iconSize, height: iconSize)
            x += iconSize + gap
            let procW = min(120, processLabel.attributedStringValue.size().width + 6)
            processLabel.frame = NSRect(x: x, y: labelY, width: procW, height: labelH)
        }

        // Right: terminal size
        let sizeW: CGFloat = 60
        sizeLabel.frame = NSRect(x: bounds.width - sizeW - 14, y: labelY, width: sizeW, height: labelH)
    }

    // MARK: - Theme

    func refreshTheme() {
        layer?.backgroundColor = Theme.surface.cgColor
        cwdIcon.contentTintColor = Theme.accent
        cwdLabel.textColor = Theme.textPrimary
        separator1.textColor = Theme.textMuted.withAlphaComponent(0.5)
        separator2.textColor = Theme.textMuted.withAlphaComponent(0.5)
        gitIcon.contentTintColor = Theme.success
        gitLabel.textColor = Theme.textSecondary
        processIcon.contentTintColor = Theme.warning
        processLabel.textColor = Theme.textSecondary
        sizeLabel.textColor = Theme.textMuted
    }
}
