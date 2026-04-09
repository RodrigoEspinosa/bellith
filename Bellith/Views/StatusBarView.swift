import AppKit

/// Optional status bar shown beneath the terminal content area.
/// It mirrors the light-touch feel of the title/context strip and is meant for
/// secondary metadata that the user explicitly wants at the bottom edge.
final class StatusBarView: NSView {
    static let height: CGFloat = 28

    private let settings: BellithSettings

    // Left items
    private let hostBadge = ContextBadgeView()
    private let environmentBadge = ContextBadgeView()
    private let worktreeBadge = ContextBadgeView()
    private let cwdIcon = NSImageView()
    private let cwdLabel = NSTextField(labelWithString: "")
    private let separator1 = NSTextField(labelWithString: "·")
    private let gitIcon = NSImageView()
    private let gitLabel = NSTextField(labelWithString: "")
    private let separator2 = NSTextField(labelWithString: "·")
    private let processIcon = NSImageView()
    private let processLabel = NSTextField(labelWithString: "")
    private let separator3 = NSTextField(labelWithString: "·")
    private let ghIcon = NSImageView()
    private let ghLabel = NSTextField(labelWithString: "")
    private let ghLoadingIndicator = NSProgressIndicator()
    private let ghLoadingLabel = NSTextField(labelWithString: "loading…")

    // Right item
    private let sizeLabel = NSTextField(labelWithString: "")

    private var currentContext: TerminalContext?
    private var currentCwd: String?
    private var currentGitWorktree: String?
    private var currentGitBranch: String?
    private var currentProcessPresentation: ForegroundProcessPresentation?
    private var currentGHSummary: GitHubService.StatusSummary?
    private var currentSizeText: String?
    private var isGitHubLoading = false
    private var lastReportedVisibility = false

    var onGitHubBadgeClicked: (() -> Void)?
    var onVisibilityChanged: ((Bool) -> Void)?

    var hasVisibleContent: Bool {
        showsContext
            || showsPath
            || showsGitWorktree
            || showsGitBranch
            || showsProcess
            || showsGitHub
            || showsGitHubLoading
            || showsSize
    }

    init(frame: NSRect = .zero, settings: BellithSettings = .shared) {
        self.settings = settings
        super.init(frame: frame)
        wantsLayer = true

        hostBadge.isHidden = true
        addSubview(hostBadge)

        environmentBadge.isHidden = true
        addSubview(environmentBadge)

        worktreeBadge.isHidden = true
        addSubview(worktreeBadge)

        setupIcon(cwdIcon, symbol: "folder.fill", tint: Theme.textSecondary)
        setupLabel(cwdLabel, size: 12, weight: .regular, color: Theme.textSecondary)

        setupSeparator(separator1)

        setupIcon(gitIcon, symbol: "arrow.triangle.branch", tint: Theme.success)
        setupLabel(gitLabel, size: 12, weight: .regular, color: Theme.textSecondary)

        setupSeparator(separator2)

        setupIcon(processIcon, symbol: "gearshape.fill", tint: Theme.textSecondary)
        setupLabel(processLabel, size: 12, weight: .regular, color: Theme.textSecondary)

        setupSeparator(separator3)

        setupIcon(ghIcon, symbol: "arrow.triangle.pull", tint: Theme.accent)
        setupLabel(ghLabel, size: 12, weight: .medium, color: Theme.accent)

        ghLoadingIndicator.style = .spinning
        ghLoadingIndicator.controlSize = .small
        ghLoadingIndicator.isIndeterminate = true
        ghLoadingIndicator.isDisplayedWhenStopped = false
        ghLoadingIndicator.isHidden = true
        addSubview(ghLoadingIndicator)

        ghLoadingLabel.font = BellithFont.mono(11, weight: .regular)
        ghLoadingLabel.textColor = Theme.textMuted
        ghLoadingLabel.isEditable = false
        ghLoadingLabel.isBezeled = false
        ghLoadingLabel.drawsBackground = false
        ghLoadingLabel.maximumNumberOfLines = 1
        ghLoadingLabel.isHidden = true
        addSubview(ghLoadingLabel)

        sizeLabel.font = BellithFont.mono(12, weight: .medium)
        sizeLabel.textColor = Theme.textSecondary
        sizeLabel.isEditable = false
        sizeLabel.isBezeled = false
        sizeLabel.drawsBackground = false
        sizeLabel.alignment = .right
        sizeLabel.maximumNumberOfLines = 1
        addSubview(sizeLabel)

        refreshTheme()
        lastReportedVisibility = hasVisibleContent
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    private func setupIcon(_ imageView: NSImageView, symbol: String, tint: NSColor) {
        imageView.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        imageView.contentTintColor = tint
        imageView.imageScaling = .scaleProportionallyDown
        imageView.isHidden = true
        addSubview(imageView)
    }

    private func setupLabel(_ label: NSTextField, size: CGFloat, weight: NSFont.Weight, color: NSColor) {
        label.font = BellithFont.mono(size, weight: weight)
        label.textColor = color
        label.isEditable = false
        label.isBezeled = false
        label.drawsBackground = false
        label.lineBreakMode = .byTruncatingMiddle
        label.maximumNumberOfLines = 1
        label.isHidden = true
        addSubview(label)
    }

    private func setupSeparator(_ label: NSTextField) {
        label.font = BellithFont.mono(12, weight: .regular)
        label.textColor = Theme.textMuted.withAlphaComponent(0.55)
        label.isEditable = false
        label.isBezeled = false
        label.drawsBackground = false
        label.isHidden = true
        addSubview(label)
    }

    private func reportVisibilityIfNeeded() {
        let isVisible = hasVisibleContent
        guard isVisible != lastReportedVisibility else { return }
        lastReportedVisibility = isVisible
        onVisibilityChanged?(isVisible)
    }

    // MARK: - Visibility

    private var showsContext: Bool {
        settings.showStatusBarContext && currentContext != nil
    }

    private var showsPath: Bool {
        settings.showStatusBarPath && !(currentCwdDisplay?.isEmpty ?? true)
    }

    private var showsGitWorktree: Bool {
        settings.showStatusBarGitWorktree && !(currentGitWorktree?.isEmpty ?? true)
    }

    private var showsGitBranch: Bool {
        settings.showStatusBarGitBranch && !(currentGitBranch?.isEmpty ?? true)
    }

    private var showsProcess: Bool {
        settings.showStatusBarProcess && !(currentProcessPresentation?.text.isEmpty ?? true)
    }

    private var showsGitHub: Bool {
        settings.showStatusBarGitHub && currentGHSummary != nil && !ghLabel.stringValue.isEmpty
    }

    private var showsGitHubLoading: Bool {
        settings.showStatusBarGitHub && isGitHubLoading
    }

    private var showsSize: Bool {
        settings.showStatusBarSize && !(currentSizeText?.isEmpty ?? true)
    }

    private var currentCwdDisplay: String? {
        guard let cwd = currentCwd, !cwd.isEmpty else { return nil }
        let home = NSHomeDirectory()
        if cwd.hasPrefix(home) {
            return "~" + cwd.dropFirst(home.count)
        }
        return cwd
    }

    // MARK: - Update

    func updateContext(_ context: TerminalContext?) {
        currentContext = context

        if showsContext, let context {
            hostBadge.text = context.hostDisplayText.uppercased()
            hostBadge.iconName = context.isRemote ? "network" : "laptopcomputer"
            hostBadge.tone = tone(for: context)
            hostBadge.isHidden = false

            if let environment = context.environmentDisplayText {
                environmentBadge.text = environment
                environmentBadge.iconName = nil
                environmentBadge.tone = tone(for: context, preferEnvironment: true)
                environmentBadge.isHidden = false
            } else {
                environmentBadge.text = ""
                environmentBadge.iconName = nil
                environmentBadge.isHidden = true
            }
        } else {
            hostBadge.text = ""
            hostBadge.iconName = nil
            hostBadge.isHidden = true
            environmentBadge.text = ""
            environmentBadge.iconName = nil
            environmentBadge.isHidden = true
        }

        needsLayout = true
        reportVisibilityIfNeeded()
    }

    func updateGitWorktree(_ worktreeName: String?) {
        let normalized = worktreeName?.trimmingCharacters(in: .whitespacesAndNewlines)
        currentGitWorktree = (normalized?.isEmpty == false) ? normalized : nil

        worktreeBadge.text = currentGitWorktree ?? ""
        worktreeBadge.iconName = currentGitWorktree == nil ? nil : "folder.badge.gearshape"
        worktreeBadge.tone = .neutral
        worktreeBadge.isHidden = !showsGitWorktree
        needsLayout = true
        reportVisibilityIfNeeded()
    }

    func updateCwd(_ cwd: String?) {
        currentCwd = cwd
        cwdLabel.stringValue = currentCwdDisplay ?? ""
        cwdIcon.isHidden = !showsPath
        cwdLabel.isHidden = !showsPath
        needsLayout = true
        reportVisibilityIfNeeded()
    }

    func updateGitBranch(_ branch: String?) {
        let normalized = branch?.trimmingCharacters(in: .whitespacesAndNewlines)
        currentGitBranch = (normalized?.isEmpty == false) ? normalized : nil

        gitLabel.stringValue = currentGitBranch ?? ""
        gitIcon.isHidden = !showsGitBranch
        gitLabel.isHidden = !showsGitBranch
        needsLayout = true
        reportVisibilityIfNeeded()
    }

    func updateProcess(_ presentation: ForegroundProcessPresentation?) {
        currentProcessPresentation = presentation

        if showsProcess, let presentation {
            processLabel.stringValue = presentation.text
            processIcon.image = NSImage(systemSymbolName: presentation.iconName, accessibilityDescription: nil)
            processIcon.contentTintColor = presentation.style == .tool ? Theme.accent : Theme.textSecondary
            processLabel.textColor = presentation.style == .tool ? Theme.textPrimary : Theme.textSecondary
            processIcon.isHidden = false
            processLabel.isHidden = false
        } else {
            processLabel.stringValue = ""
            processIcon.isHidden = true
            processLabel.isHidden = true
        }

        needsLayout = true
        reportVisibilityIfNeeded()
    }

    func setGitHubLoading(_ loading: Bool) {
        guard isGitHubLoading != loading else { return }
        isGitHubLoading = loading

        if loading {
            ghLoadingIndicator.startAnimation(nil)
        } else {
            ghLoadingIndicator.stopAnimation(nil)
        }

        ghLoadingIndicator.isHidden = !showsGitHubLoading
        ghLoadingLabel.isHidden = !showsGitHubLoading
        ghIcon.isHidden = !(showsGitHub || showsGitHubLoading)
        ghLabel.isHidden = !showsGitHub

        needsLayout = true
        reportVisibilityIfNeeded()
    }

    func updateGitHub(_ summary: GitHubService.StatusSummary?) {
        currentGHSummary = summary

        if let summary {
            var parts: [String] = []
            if summary.openPRs > 0 { parts.append("\(summary.openPRs) PR\(summary.openPRs == 1 ? "" : "s")") }
            if summary.openIssues > 0 { parts.append("\(summary.openIssues) issue\(summary.openIssues == 1 ? "" : "s")") }
            ghLabel.stringValue = parts.joined(separator: " · ")
        } else {
            ghLabel.stringValue = ""
        }

        ghIcon.isHidden = !(showsGitHub || showsGitHubLoading)
        ghLabel.isHidden = !showsGitHub
        ghLoadingIndicator.isHidden = !showsGitHubLoading
        ghLoadingLabel.isHidden = !showsGitHubLoading

        needsLayout = true
        reportVisibilityIfNeeded()
    }

    func updateSize(cols: Int, rows: Int) {
        currentSizeText = "\(cols)×\(rows)"
        sizeLabel.stringValue = showsSize ? currentSizeText ?? "" : ""
        needsLayout = true
        reportVisibilityIfNeeded()
    }

    func clear() {
        currentContext = nil
        currentCwd = nil
        currentGitWorktree = nil
        currentGitBranch = nil
        currentProcessPresentation = nil
        currentGHSummary = nil
        currentSizeText = nil
        isGitHubLoading = false

        hostBadge.text = ""
        environmentBadge.text = ""
        worktreeBadge.text = ""
        worktreeBadge.iconName = nil
        cwdLabel.stringValue = ""
        gitLabel.stringValue = ""
        processLabel.stringValue = ""
        ghLabel.stringValue = ""
        sizeLabel.stringValue = ""

        ghLoadingIndicator.stopAnimation(nil)

        hostBadge.isHidden = true
        environmentBadge.isHidden = true
        worktreeBadge.isHidden = true
        cwdIcon.isHidden = true
        cwdLabel.isHidden = true
        gitIcon.isHidden = true
        gitLabel.isHidden = true
        processIcon.isHidden = true
        processLabel.isHidden = true
        ghIcon.isHidden = true
        ghLabel.isHidden = true
        ghLoadingIndicator.isHidden = true
        ghLoadingLabel.isHidden = true
        needsLayout = true
        reportVisibilityIfNeeded()
    }

    // MARK: - Interaction

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if showsGitHub {
            let hitRect = NSRect(
                x: ghIcon.frame.minX - 4,
                y: 0,
                width: ghLabel.frame.maxX - ghIcon.frame.minX + 8,
                height: bounds.height
            )
            if hitRect.contains(point) {
                onGitHubBadgeClicked?()
                return
            }
        }
        super.mouseDown(with: event)
    }

    // MARK: - Layout

    override func layout() {
        super.layout()

        hostBadge.frame = .zero
        environmentBadge.frame = .zero
        worktreeBadge.frame = .zero
        cwdIcon.frame = .zero
        cwdLabel.frame = .zero
        gitIcon.frame = .zero
        gitLabel.frame = .zero
        processIcon.frame = .zero
        processLabel.frame = .zero
        ghIcon.frame = .zero
        ghLabel.frame = .zero
        ghLoadingIndicator.frame = .zero
        ghLoadingLabel.frame = .zero
        separator1.frame = .zero
        separator2.frame = .zero
        separator3.frame = .zero
        sizeLabel.frame = .zero
        separator1.isHidden = true
        separator2.isHidden = true
        separator3.isHidden = true

        let h = bounds.height
        let iconSize: CGFloat = 13
        let iconY = floor((h - iconSize) / 2)
        let labelH: CGFloat = 16
        let labelY = floor((h - labelH) / 2)
        let gap: CGFloat = 5
        let groupGap: CGFloat = 4
        let sepW: CGFloat = 8

        let sizeWidth: CGFloat = showsSize ? max(44, sizeLabel.attributedStringValue.size().width + 2) : 0
        let trailingX = sizeWidth > 0 ? bounds.width - sizeWidth - 10 : bounds.width - 10
        if sizeWidth > 0 {
            sizeLabel.frame = NSRect(x: trailingX, y: labelY, width: sizeWidth, height: labelH)
        }

        var x: CGFloat = 14
        var hasContent = false
        let separators = [separator1, separator2, separator3]
        var separatorIndex = 0

        func placeSeparatorIfNeeded() {
            guard hasContent, separatorIndex < separators.count else { return }
            let separator = separators[separatorIndex]
            separator.frame = NSRect(x: x, y: labelY, width: sepW, height: labelH)
            separator.isHidden = false
            x += sepW + groupGap
            separatorIndex += 1
        }

        if showsContext {
            let hostSize = hostBadge.intrinsicContentSize
            hostBadge.frame = NSRect(x: x, y: floor((h - hostSize.height) / 2), width: hostSize.width, height: hostSize.height)
            x += hostSize.width + 8
            hasContent = true

            if !environmentBadge.isHidden {
                let environmentSize = environmentBadge.intrinsicContentSize
                environmentBadge.frame = NSRect(x: x, y: floor((h - environmentSize.height) / 2), width: environmentSize.width, height: environmentSize.height)
                x += environmentSize.width + 8
            }
        }

        if showsGitWorktree {
            placeSeparatorIfNeeded()
            let worktreeSize = worktreeBadge.intrinsicContentSize
            worktreeBadge.frame = NSRect(x: x, y: floor((h - worktreeSize.height) / 2), width: worktreeSize.width, height: worktreeSize.height)
            x += worktreeSize.width + 8
            hasContent = true
        }

        if showsPath {
            placeSeparatorIfNeeded()
            cwdIcon.frame = NSRect(x: x, y: iconY, width: iconSize, height: iconSize)
            x += iconSize + gap
            let availableWidth = max(0, trailingX - x - 8)
            let preferredWidth = cwdLabel.attributedStringValue.size().width + 6
            let width = min(260, min(availableWidth, preferredWidth))
            cwdLabel.frame = NSRect(x: x, y: labelY, width: width, height: labelH)
            x += width + 8
            hasContent = true
        }

        if showsGitBranch {
            placeSeparatorIfNeeded()
            gitIcon.frame = NSRect(x: x, y: iconY, width: iconSize, height: iconSize)
            x += iconSize + gap
            let availableWidth = max(0, trailingX - x - 8)
            let preferredWidth = gitLabel.attributedStringValue.size().width + 6
            let width = min(140, min(availableWidth, preferredWidth))
            gitLabel.frame = NSRect(x: x, y: labelY, width: width, height: labelH)
            x += width + 8
            hasContent = true
        }

        if showsProcess {
            placeSeparatorIfNeeded()
            processIcon.frame = NSRect(x: x, y: iconY, width: iconSize, height: iconSize)
            x += iconSize + gap
            let availableWidth = max(0, trailingX - x - 8)
            let preferredWidth = processLabel.attributedStringValue.size().width + 6
            let width = min(120, min(availableWidth, preferredWidth))
            processLabel.frame = NSRect(x: x, y: labelY, width: width, height: labelH)
            x += width + 8
            hasContent = true
        }

        if showsGitHub || showsGitHubLoading {
            placeSeparatorIfNeeded()
            ghIcon.frame = NSRect(x: x, y: iconY, width: iconSize, height: iconSize)
            x += iconSize + gap

            if showsGitHubLoading {
                let spinnerSize: CGFloat = 12
                ghLoadingIndicator.frame = NSRect(x: x, y: floor((h - spinnerSize) / 2), width: spinnerSize, height: spinnerSize)
                x += spinnerSize + 5
                let loadingWidth = ghLoadingLabel.attributedStringValue.size().width + 4
                ghLoadingLabel.frame = NSRect(x: x, y: labelY, width: loadingWidth, height: labelH)
            } else if showsGitHub {
                let availableWidth = max(0, trailingX - x - 8)
                let preferredWidth = ghLabel.attributedStringValue.size().width + 6
                let width = min(180, min(availableWidth, preferredWidth))
                ghLabel.frame = NSRect(x: x, y: labelY, width: width, height: labelH)
            }
            hasContent = true
        }
    }

    // MARK: - Theme

    func refreshTheme() {
        layer?.backgroundColor = NSColor.clear.cgColor
        layer?.borderWidth = 0
        layer?.borderColor = NSColor.clear.cgColor

        hostBadge.refreshTheme()
        environmentBadge.refreshTheme()
        worktreeBadge.refreshTheme()

        cwdIcon.contentTintColor = Theme.textSecondary
        cwdLabel.textColor = Theme.textSecondary
        gitIcon.contentTintColor = Theme.success
        gitLabel.textColor = Theme.textSecondary
        processIcon.contentTintColor = Theme.textSecondary
        processLabel.textColor = Theme.textSecondary
        ghIcon.contentTintColor = Theme.accent
        ghLabel.textColor = Theme.accent
        ghLoadingLabel.textColor = Theme.textMuted
        sizeLabel.textColor = Theme.textSecondary
        separator1.textColor = Theme.textMuted.withAlphaComponent(0.55)
        separator2.textColor = Theme.textMuted.withAlphaComponent(0.55)
        separator3.textColor = Theme.textMuted.withAlphaComponent(0.55)

        updateContext(currentContext)
        updateGitWorktree(currentGitWorktree)
        updateCwd(currentCwd)
        updateGitBranch(currentGitBranch)
        updateProcess(currentProcessPresentation)
        updateGitHub(currentGHSummary)
        setGitHubLoading(isGitHubLoading)
        if let currentSizeText {
            sizeLabel.stringValue = showsSize ? currentSizeText : ""
        } else {
            sizeLabel.stringValue = ""
        }
        needsLayout = true
        reportVisibilityIfNeeded()
    }

    private func tone(for context: TerminalContext, preferEnvironment: Bool = false) -> ContextBadgeView.Tone {
        if context.isSensitive {
            return .destructive
        }

        let tag = context.environmentTag?.lowercased()
        switch tag {
        case "prod", "production":
            return .destructive
        case "stage", "staging", "preprod":
            return .warning
        case "dev", "development", "test", "qa":
            return .success
        default:
            return preferEnvironment && context.isRemote ? .warning : .neutral
        }
    }
}
