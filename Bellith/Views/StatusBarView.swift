import AppKit

/// Optional status bar shown beneath the terminal content area.
/// It mirrors the light-touch feel of the title/context strip and is meant for
/// secondary metadata that the user explicitly wants at the bottom edge.
final class StatusBarView: NSView {
    static let height: CGFloat = 26

    private let settings: BellithSettings

    private let backgroundGradient = CAGradientLayer()
    private let topHairline = CALayer()

    // Left lead pill (mode indicator) — purely cosmetic, mirrors the v2 design's NORMAL chip.
    private let modePill = NSTextField(labelWithString: "NORMAL")

    // Left items
    private let hostBadge = ContextBadgeView()
    private let environmentBadge = ContextBadgeView()
    private let worktreeBadge = ContextBadgeView()
    private let cwdIcon = NSImageView()
    private let cwdLabel = NSTextField(labelWithString: "")
    private let separator1 = NSTextField(labelWithString: "·")
    private let cleanDot = NSTextField(labelWithString: "●")
    private let gitIcon = NSImageView()
    private let gitLabel = NSTextField(labelWithString: "")
    private let separator2 = NSTextField(labelWithString: "·")
    private let processIcon = NSImageView()
    private let processLabel = NSTextField(labelWithString: "")
    private let separator3 = NSTextField(labelWithString: "·")
    private let ghIcon = NSImageView()
    private let ghPRSegment = GitHubStatusSegmentView(symbolName: "arrow.triangle.pull", tintColor: Theme.accent)
    private let ghIssueSegment = GitHubStatusSegmentView(symbolName: "exclamationmark.circle", tintColor: Theme.warning)
    private let ghLoadingIndicator = NSProgressIndicator()
    private let ghLoadingLabel = NSTextField(labelWithString: "loading…")

    // Right item: terminal size, plus shortcut hints.
    private let sizeLabel = NSTextField(labelWithString: "")
    private let shortcutHintsLabel = NSTextField(labelWithString: "")

    private var currentContext: TerminalContext?
    private var currentCwd: String?
    private var currentGitWorktree: String?
    private var currentGitBranch: String?
    private var currentProcessPresentation: ForegroundProcessPresentation?
    private var currentGHSummary: GitHubService.StatusSummary?
    private var currentGitHubDetails: GitHubService.StatusDetails?
    private var currentSizeText: String?
    private var isGitHubLoading = false
    private var lastReportedVisibility = false
    private var gitHubTrackingAreas: [GitHubPopoverKind: NSTrackingArea] = [:]
    private var gitHubPopover = NSPopover()
    private var gitHubPopoverController = GitHubHoverPopoverViewController()
    private var gitHubHoverDelayTimer: Timer?
    private var gitHubHideDelayTimer: Timer?
    private var hoveredGitHubPopoverKind: GitHubPopoverKind?
    private var presentedGitHubPopoverKind: GitHubPopoverKind?
    private var isHoveringGitHubPopover = false
    private var gitHubPopoverDirectory: String?

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

        layer?.addSublayer(backgroundGradient)
        layer?.addSublayer(topHairline)

        modePill.font = BellithFont.mono(10, weight: .medium)
        modePill.textColor = Theme.textSecondary
        modePill.alignment = .center
        modePill.isEditable = false
        modePill.isBezeled = false
        modePill.drawsBackground = false
        modePill.wantsLayer = true
        modePill.layer?.cornerRadius = 3
        modePill.layer?.cornerCurve = .continuous
        addSubview(modePill)

        cleanDot.font = BellithFont.mono(11, weight: .bold)
        cleanDot.textColor = Theme.success
        cleanDot.isEditable = false
        cleanDot.isBezeled = false
        cleanDot.drawsBackground = false
        cleanDot.isHidden = true
        addSubview(cleanDot)

        shortcutHintsLabel.font = BellithFont.mono(10.5, weight: .regular)
        shortcutHintsLabel.textColor = Theme.textTertiary
        shortcutHintsLabel.isEditable = false
        shortcutHintsLabel.isBezeled = false
        shortcutHintsLabel.drawsBackground = false
        shortcutHintsLabel.alignment = .right
        shortcutHintsLabel.maximumNumberOfLines = 1
        shortcutHintsLabel.lineBreakMode = .byTruncatingTail
        shortcutHintsLabel.attributedStringValue = Self.makeShortcutHints()
        addSubview(shortcutHintsLabel)

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

        setupIcon(ghIcon, symbol: "chevron.left.forwardslash.chevron.right", tint: Theme.accent)
        ghPRSegment.isHidden = true
        ghIssueSegment.isHidden = true
        addSubview(ghPRSegment)
        addSubview(ghIssueSegment)

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

        gitHubPopover.behavior = .applicationDefined
        gitHubPopover.animates = false
        gitHubPopover.appearance = Theme.overlayAppearance
        gitHubPopover.contentViewController = gitHubPopoverController
        gitHubPopoverController.onHoverChanged = { [weak self] hovering in
            guard let self else { return }
            self.isHoveringGitHubPopover = hovering
            if hovering {
                self.gitHubHideDelayTimer?.invalidate()
            } else {
                self.scheduleGitHubPopoverHideIfNeeded()
            }
        }
        gitHubPopoverController.onOpenItem = { [weak self] row in
            guard let self, let directory = self.gitHubPopoverDirectory else { return }
            self.closeGitHubPopover()
            GitHubService.openInBrowser(number: row.number, isPR: row.isPullRequest, directory: directory)
        }

        refreshTheme()
        lastReportedVisibility = hasVisibleContent
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    deinit {
        gitHubHoverDelayTimer?.invalidate()
        gitHubHideDelayTimer?.invalidate()
        gitHubPopover.performClose(nil)
    }

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

    private var showsGitHubPullRequests: Bool {
        settings.showStatusBarGitHub && (currentGHSummary?.openPRs ?? 0) > 0
    }

    private var showsGitHubIssues: Bool {
        settings.showStatusBarGitHub && (currentGHSummary?.openIssues ?? 0) > 0
    }

    private var showsGitHub: Bool {
        showsGitHubPullRequests || showsGitHubIssues
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

    private func refreshGitHubSummaryViews() {
        let prCount = currentGHSummary?.openPRs ?? 0
        let issueCount = currentGHSummary?.openIssues ?? 0

        ghPRSegment.update(
            count: prCount,
            label: prCount == 1 ? "PR" : "PRs"
        )
        ghIssueSegment.update(
            count: issueCount,
            label: issueCount == 1 ? "Issue" : "Issues"
        )

        ghIcon.isHidden = !showsGitHubLoading
        ghPRSegment.isHidden = showsGitHubLoading || !showsGitHubPullRequests
        ghIssueSegment.isHidden = showsGitHubLoading || !showsGitHubIssues
        ghLoadingIndicator.isHidden = !showsGitHubLoading
        ghLoadingLabel.isHidden = !showsGitHubLoading
        refreshGitHubSegmentHighlighting()
    }

    private func refreshGitHubSegmentHighlighting() {
        let activeKind = hoveredGitHubPopoverKind ?? (gitHubPopover.isShown ? presentedGitHubPopoverKind : nil)
        ghPRSegment.isHighlighted = activeKind == .pullRequests
        ghIssueSegment.isHighlighted = activeKind == .issues
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
        gitHubPopoverDirectory = cwd
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

        refreshGitHubSummaryViews()
        refreshGitHubPopoverIfNeeded()

        needsLayout = true
        updateTrackingAreas()
        reportVisibilityIfNeeded()
    }

    func updateGitHubDetails(_ details: GitHubService.StatusDetails?) {
        currentGitHubDetails = details
        gitHubPopoverDirectory = currentCwd
        refreshGitHubPopoverIfNeeded()
    }

    func updateGitHub(_ summary: GitHubService.StatusSummary?) {
        currentGHSummary = summary
        refreshGitHubSummaryViews()
        refreshGitHubPopoverIfNeeded()

        needsLayout = true
        updateTrackingAreas()
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
        currentGitHubDetails = nil
        gitHubPopoverDirectory = nil
        currentSizeText = nil
        isGitHubLoading = false

        hostBadge.text = ""
        environmentBadge.text = ""
        worktreeBadge.text = ""
        worktreeBadge.iconName = nil
        cwdLabel.stringValue = ""
        gitLabel.stringValue = ""
        processLabel.stringValue = ""
        sizeLabel.stringValue = ""

        ghLoadingIndicator.stopAnimation(nil)
        hoveredGitHubPopoverKind = nil
        refreshGitHubSummaryViews()
        refreshGitHubPopoverIfNeeded()
        updateTrackingAreas()

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
        ghPRSegment.isHidden = true
        ghIssueSegment.isHidden = true
        ghLoadingIndicator.isHidden = true
        ghLoadingLabel.isHidden = true
        needsLayout = true
        reportVisibilityIfNeeded()
    }

    // MARK: - Interaction

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if gitHubInteractiveRect.contains(point) {
            onGitHubBadgeClicked?()
            return
        }
        super.mouseDown(with: event)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()

        gitHubTrackingAreas.values.forEach { removeTrackingArea($0) }
        gitHubTrackingAreas.removeAll()

        for kind in GitHubPopoverKind.allCases {
            let rect = gitHubSourceRect(for: kind)
            guard !rect.isEmpty, canPresentGitHubPopover(for: kind) else { continue }
            let area = NSTrackingArea(
                rect: rect,
                options: [.mouseEnteredAndExited, .activeInKeyWindow],
                owner: self,
                userInfo: ["zone": kind.rawValue]
            )
            addTrackingArea(area)
            gitHubTrackingAreas[kind] = area
        }
    }

    override func mouseEntered(with event: NSEvent) {
        if let info = event.trackingArea?.userInfo as? [String: String],
           let rawValue = info["zone"],
           let kind = GitHubPopoverKind(rawValue: rawValue) {
            hoveredGitHubPopoverKind = kind
            refreshGitHubSegmentHighlighting()
            if gitHubPopover.isShown {
                showGitHubPopover(for: kind)
            } else {
                scheduleGitHubPopoverShowIfNeeded()
            }
            return
        }
        super.mouseEntered(with: event)
    }

    override func mouseExited(with event: NSEvent) {
        if let info = event.trackingArea?.userInfo as? [String: String],
           let rawValue = info["zone"],
           GitHubPopoverKind(rawValue: rawValue) != nil {
            hoveredGitHubPopoverKind = nil
            refreshGitHubSegmentHighlighting()
            scheduleGitHubPopoverHideIfNeeded()
            return
        }
        super.mouseExited(with: event)
    }

    static func gitHubToolTip(details: GitHubService.StatusDetails?) -> String? {
        guard let details else { return nil }

        var lines: [String] = [details.repoName]

        if !details.pullRequests.isEmpty {
            lines.append("")
            lines.append("Pull requests")
            lines.append(contentsOf: details.pullRequests.map {
                "#\($0.number) \($0.title) — @\($0.author)"
            })
            if details.openPRs > details.pullRequests.count {
                lines.append("…and \(details.openPRs - details.pullRequests.count) more PRs")
            }
        }

        if !details.issues.isEmpty {
            lines.append("")
            lines.append("Issues")
            lines.append(contentsOf: details.issues.map {
                "#\($0.number) \($0.title) — @\($0.author)"
            })
            if details.openIssues > details.issues.count {
                lines.append("…and \(details.openIssues - details.issues.count) more issues")
            }
        }

        return lines.joined(separator: "\n")
    }

    private var gitHubInteractiveRect: NSRect {
        var rect = NSRect.zero
        for candidate in [
            ghIcon.frame,
            ghPRSegment.frame,
            ghIssueSegment.frame,
            ghLoadingIndicator.frame,
            ghLoadingLabel.frame,
        ] where !candidate.isEmpty {
            rect = rect.isEmpty ? candidate : rect.union(candidate)
        }
        return rect.insetBy(dx: -4, dy: -3)
    }

    private func gitHubSourceRect(for kind: GitHubPopoverKind) -> NSRect {
        let rect: NSRect = switch kind {
        case .pullRequests:
            ghPRSegment.frame
        case .issues:
            ghIssueSegment.frame
        case .loading:
            [ghIcon.frame, ghLoadingIndicator.frame, ghLoadingLabel.frame]
                .filter { !$0.isEmpty }
                .reduce(into: NSRect.zero) { partialResult, candidate in
                    partialResult = partialResult.isEmpty ? candidate : partialResult.union(candidate)
                }
        }
        return rect.insetBy(dx: -3, dy: -3)
    }

    private func canPresentGitHubPopover(for kind: GitHubPopoverKind) -> Bool {
        switch kind {
        case .pullRequests:
            showsGitHubPullRequests
        case .issues:
            showsGitHubIssues
        case .loading:
            showsGitHubLoading
        }
    }

    private func refreshGitHubPopoverIfNeeded() {
        gitHubPopoverController.update(
            summary: currentGHSummary,
            details: currentGitHubDetails,
            kind: presentedGitHubPopoverKind ?? hoveredGitHubPopoverKind,
            loading: showsGitHubLoading
        )

        guard gitHubPopover.isShown else { return }
        guard let kind = presentedGitHubPopoverKind, canPresentGitHubPopover(for: kind) else {
            closeGitHubPopover()
            return
        }

        if let hoveredGitHubPopoverKind, hoveredGitHubPopoverKind != kind {
            showGitHubPopover(for: hoveredGitHubPopoverKind)
        }
    }

    private func scheduleGitHubPopoverShowIfNeeded() {
        guard let kind = hoveredGitHubPopoverKind, canPresentGitHubPopover(for: kind) else { return }
        gitHubHideDelayTimer?.invalidate()

        guard !gitHubPopover.isShown else {
            showGitHubPopover(for: kind)
            return
        }

        gitHubHoverDelayTimer?.invalidate()
        gitHubHoverDelayTimer = Timer.scheduledTimer(withTimeInterval: 0.12, repeats: false) { [weak self] _ in
            self?.showGitHubPopover(for: kind)
        }
    }

    private func scheduleGitHubPopoverHideIfNeeded() {
        gitHubHoverDelayTimer?.invalidate()
        guard gitHubPopover.isShown else { return }
        guard hoveredGitHubPopoverKind == nil, !isHoveringGitHubPopover else { return }

        gitHubHideDelayTimer?.invalidate()
        gitHubHideDelayTimer = Timer.scheduledTimer(withTimeInterval: 0.14, repeats: false) { [weak self] _ in
            self?.closeGitHubPopover()
        }
    }

    private func showGitHubPopover(for kind: GitHubPopoverKind) {
        guard canPresentGitHubPopover(for: kind) else { return }
        let sourceRect = gitHubSourceRect(for: kind)
        guard window != nil, !sourceRect.isEmpty else { return }

        gitHubHideDelayTimer?.invalidate()
        let needsReanchor = presentedGitHubPopoverKind != kind
        presentedGitHubPopoverKind = kind
        refreshGitHubSegmentHighlighting()
        gitHubPopoverController.update(
            summary: currentGHSummary,
            details: currentGitHubDetails,
            kind: kind,
            loading: showsGitHubLoading
        )

        guard needsReanchor || !gitHubPopover.isShown else { return }

        if gitHubPopover.isShown {
            gitHubPopover.performClose(nil)
        }
        gitHubPopover.show(relativeTo: sourceRect, of: self, preferredEdge: .minY)
    }

    private func closeGitHubPopover() {
        gitHubHideDelayTimer?.invalidate()
        gitHubHoverDelayTimer?.invalidate()
        presentedGitHubPopoverKind = nil
        refreshGitHubSegmentHighlighting()
        if gitHubPopover.isShown {
            gitHubPopover.performClose(nil)
        }
    }

    // MARK: - Layout

    override func layout() {
        super.layout()

        backgroundGradient.frame = bounds
        topHairline.frame = NSRect(x: 0, y: bounds.height - 1, width: bounds.width, height: 1)

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
        ghPRSegment.frame = .zero
        ghIssueSegment.frame = .zero
        ghLoadingIndicator.frame = .zero
        ghLoadingLabel.frame = .zero
        separator1.frame = .zero
        separator2.frame = .zero
        separator3.frame = .zero
        sizeLabel.frame = .zero
        cleanDot.frame = .zero
        cleanDot.isHidden = true
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

        // Right edge: shortcut hints, then size label.
        let hintsSize = shortcutHintsLabel.attributedStringValue.size()
        let hintsW: CGFloat = ceil(hintsSize.width)
        let hintsX = bounds.width - hintsW - 12
        shortcutHintsLabel.frame = NSRect(x: hintsX, y: labelY, width: hintsW, height: labelH)

        let sizeWidth: CGFloat = showsSize ? max(44, sizeLabel.attributedStringValue.size().width + 2) : 0
        let trailingX: CGFloat = {
            let stop = hintsX - 16
            return sizeWidth > 0 ? stop - sizeWidth : stop
        }()
        if sizeWidth > 0 {
            sizeLabel.frame = NSRect(x: trailingX, y: labelY, width: sizeWidth, height: labelH)
        }

        // Mode pill on the far left.
        let modeText = modePill.stringValue
        let modeFontW = (modeText as NSString).size(withAttributes: [.font: modePill.font ?? NSFont.systemFont(ofSize: 10)]).width
        let modePillW = ceil(modeFontW) + 12
        let modePillH: CGFloat = 16
        modePill.frame = NSRect(x: 10, y: floor((h - modePillH) / 2), width: modePillW, height: modePillH)

        var x: CGFloat = modePill.frame.maxX + 10
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
            // Green clean-dot ahead of the branch, mirroring the v2 design's "● clean" cluster.
            let dotW: CGFloat = 10
            cleanDot.frame = NSRect(x: x, y: labelY, width: dotW, height: labelH)
            cleanDot.isHidden = false
            x += dotW + 5

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

            if showsGitHubLoading {
                ghIcon.frame = NSRect(x: x, y: iconY, width: iconSize, height: iconSize)
                x += iconSize + gap

                let spinnerSize: CGFloat = 12
                ghLoadingIndicator.frame = NSRect(x: x, y: floor((h - spinnerSize) / 2), width: spinnerSize, height: spinnerSize)
                x += spinnerSize + 5
                let loadingWidth = ghLoadingLabel.attributedStringValue.size().width + 4
                ghLoadingLabel.frame = NSRect(x: x, y: labelY, width: loadingWidth, height: labelH)
            } else {
                let segmentGap: CGFloat = 12
                if showsGitHubPullRequests {
                    let size = ghPRSegment.intrinsicContentSize
                    ghPRSegment.frame = NSRect(
                        x: x,
                        y: floor((h - size.height) / 2),
                        width: min(size.width, max(0, trailingX - x - 8)),
                        height: size.height
                    )
                    x += ghPRSegment.frame.width + segmentGap
                }
                if showsGitHubIssues {
                    let size = ghIssueSegment.intrinsicContentSize
                    ghIssueSegment.frame = NSRect(
                        x: x,
                        y: floor((h - size.height) / 2),
                        width: min(size.width, max(0, trailingX - x - 8)),
                        height: size.height
                    )
                }
            }
            hasContent = true
        }

        updateTrackingAreas()
    }

    // MARK: - Theme

    func refreshTheme() {
        layer?.backgroundColor = NSColor.clear.cgColor
        layer?.borderWidth = 0
        layer?.borderColor = NSColor.clear.cgColor

        // Subtle top→bottom darkening gradient mirrors the v2 design statusbar.
        let isLight = Theme.colors.isLight
        let topColor = isLight
            ? NSColor.white.withAlphaComponent(0.25).cgColor
            : NSColor(white: 0.0, alpha: 0.18).cgColor
        let bottomColor = isLight
            ? NSColor.white.withAlphaComponent(0.05).cgColor
            : NSColor(white: 0.0, alpha: 0.32).cgColor
        backgroundGradient.colors = [topColor, bottomColor]
        backgroundGradient.locations = [0, 1]
        backgroundGradient.startPoint = CGPoint(x: 0.5, y: 1)
        backgroundGradient.endPoint = CGPoint(x: 0.5, y: 0)

        topHairline.backgroundColor = Theme.chromeHairline.withAlphaComponent(isLight ? 0.6 : 0.5).cgColor

        modePill.layer?.backgroundColor = Theme.chromeElevated.withAlphaComponent(isLight ? 0.6 : 0.55).cgColor
        modePill.textColor = Theme.textSecondary

        cleanDot.textColor = Theme.success

        shortcutHintsLabel.attributedStringValue = Self.makeShortcutHints()

        gitHubPopover.appearance = Theme.overlayAppearance

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
        ghPRSegment.refreshTheme(tintColor: Theme.accent)
        ghIssueSegment.refreshTheme(tintColor: Theme.warning)
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
        updateGitHubDetails(currentGitHubDetails)
        setGitHubLoading(isGitHubLoading)
        if let currentSizeText {
            sizeLabel.stringValue = showsSize ? currentSizeText : ""
        } else {
            sizeLabel.stringValue = ""
        }
        needsLayout = true
        updateTrackingAreas()
        reportVisibilityIfNeeded()
    }

    private static func makeShortcutHints() -> NSAttributedString {
        let mono = BellithFont.mono(10.5, weight: .regular)
        let accent = Theme.accent
        let muted = Theme.textTertiary
        let dim = Theme.textTertiary.withAlphaComponent(0.5)
        let result = NSMutableAttributedString()
        let pairs: [(kbd: String, label: String)] = [
            ("⌘P", "PRs"),
            ("⌘K", "palette"),
        ]
        for (idx, pair) in pairs.enumerated() {
            if idx > 0 {
                result.append(NSAttributedString(
                    string: " · ",
                    attributes: [.font: mono, .foregroundColor: dim]
                ))
            }
            result.append(NSAttributedString(
                string: pair.kbd,
                attributes: [.font: mono, .foregroundColor: accent]
            ))
            result.append(NSAttributedString(
                string: " " + pair.label,
                attributes: [.font: mono, .foregroundColor: muted]
            ))
        }
        return result
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

private enum GitHubPopoverKind: String, CaseIterable {
    case pullRequests
    case issues
    case loading
}

private final class GitHubStatusSegmentView: NSView {
    private enum Metrics {
        static let height: CGFloat = 18
        static let horizontalInset: CGFloat = 1
        static let interLabelGap: CGFloat = 5
        static let underlineInset: CGFloat = 1
    }

    private let countLabel = NSTextField(labelWithString: "")
    private let descriptorLabel = NSTextField(labelWithString: "")
    private let underlineLayer = CAShapeLayer()
    private var tintColor: NSColor

    var isHighlighted = false {
        didSet {
            guard oldValue != isHighlighted else { return }
            applyAppearance(animated: true)
        }
    }

    init(symbolName: String, tintColor: NSColor) {
        self.tintColor = tintColor
        super.init(frame: .zero)
        wantsLayer = true

        countLabel.isEditable = false
        countLabel.isBezeled = false
        countLabel.drawsBackground = false
        countLabel.maximumNumberOfLines = 1
        countLabel.alignment = .left
        addSubview(countLabel)

        descriptorLabel.isEditable = false
        descriptorLabel.isBezeled = false
        descriptorLabel.drawsBackground = false
        descriptorLabel.maximumNumberOfLines = 1
        descriptorLabel.lineBreakMode = .byTruncatingTail
        descriptorLabel.alignment = .left
        addSubview(descriptorLabel)

        underlineLayer.fillColor = nil
        underlineLayer.lineWidth = 1
        underlineLayer.lineCap = .round
        underlineLayer.lineDashPattern = [1, 3]
        layer?.addSublayer(underlineLayer)

        refreshTheme(tintColor: tintColor)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override var intrinsicContentSize: NSSize {
        let countWidth = measuredWidth(for: countLabel)
        let descriptorWidth = measuredWidth(for: descriptorLabel)
        let spacing: CGFloat = descriptorLabel.stringValue.isEmpty ? 0 : Metrics.interLabelGap
        let contentWidth = countWidth + descriptorWidth + spacing + (Metrics.horizontalInset * 2)
        return NSSize(width: contentWidth, height: Metrics.height)
    }

    override func layout() {
        super.layout()
        let contentY = floor((bounds.height - 13) / 2) + 1
        let countWidth = measuredWidth(for: countLabel)
        let descriptorWidth = min(measuredWidth(for: descriptorLabel), max(0, bounds.width - (Metrics.horizontalInset * 2) - countWidth - Metrics.interLabelGap))
        let spacing: CGFloat = descriptorLabel.stringValue.isEmpty ? 0 : Metrics.interLabelGap
        let contentX = Metrics.horizontalInset

        countLabel.frame = NSRect(x: contentX, y: contentY, width: countWidth, height: 13)
        descriptorLabel.frame = NSRect(
            x: countLabel.frame.maxX + spacing,
            y: contentY,
            width: descriptorWidth,
            height: 13
        )

        let underlineY = bounds.minY + 2
        let underlinePath = CGMutablePath()
        underlinePath.move(to: CGPoint(x: Metrics.underlineInset, y: underlineY))
        underlinePath.addLine(to: CGPoint(x: bounds.width - Metrics.underlineInset, y: underlineY))
        underlineLayer.path = underlinePath
        underlineLayer.frame = bounds
    }

    func refreshTheme(tintColor: NSColor) {
        self.tintColor = tintColor
        countLabel.font = BellithFont.mono(11, weight: .semibold)
        descriptorLabel.font = BellithFont.mono(10.5, weight: .medium)
        invalidateIntrinsicContentSize()
        needsLayout = true
        applyAppearance(animated: false)
    }

    func update(count: Int, label: String) {
        countLabel.stringValue = "\(count)"
        descriptorLabel.stringValue = label
        invalidateIntrinsicContentSize()
        needsLayout = true
    }

    private func measuredWidth(for label: NSTextField) -> CGFloat {
        ceil(label.fittingSize.width) + 1
    }

    private func applyAppearance(animated: Bool) {
        let updates = {
            self.countLabel.textColor = self.tintColor
            self.descriptorLabel.textColor = self.tintColor.withAlphaComponent(self.isHighlighted ? 0.88 : 0.76)
            self.countLabel.alphaValue = 1.0
            self.descriptorLabel.alphaValue = 1.0
            self.layer?.backgroundColor = NSColor.clear.cgColor
            self.layer?.borderWidth = 0
            self.underlineLayer.strokeColor = self.tintColor.withAlphaComponent(self.isHighlighted ? 0.9 : 0.52).cgColor
        }

        if animated {
            Theme.animate(duration: 0.08) { _ in updates() }
        } else {
            updates()
        }
    }
}

private enum GitHubPopoverLayout {
    static let gutterX: CGFloat = 16                // popover-level leading/trailing gutter
    static let bodyX: CGFloat = 8                   // bodyFrame.x
    static let rowHoverInsetX: CGFloat = 4          // row hover background inset
    static let rowContentInsetX: CGFloat = 4
    static let statusColumnWidth: CGFloat = 18      // PR status glyph column (●/○/✗)
    static let statusGap: CGFloat = 8
    static let numColumnWidth: CGFloat = 38
    static let numToTitleGap: CGFloat = 12
    static let ciIconWidth: CGFloat = 14
    static let numToCIGap: CGFloat = 6
    static let ciToTitleGap: CGFloat = 10
    static let branchColumnWidth: CGFloat = 130     // PR head branch column
    static let diffColumnWidth: CGFloat = 96        // "+1,284 −342"
    static let tailGap: CGFloat = 10

    static func titleColumnX_bg(isPR: Bool) -> CGFloat {
        let statusOffset = isPR ? statusColumnWidth + statusGap : 0
        let ciOffset = isPR ? numToCIGap + ciIconWidth + ciToTitleGap : numToTitleGap
        return rowContentInsetX + statusOffset + numColumnWidth + ciOffset
    }
    static func titleColumnX_popover(isPR: Bool) -> CGFloat {
        let statusOffset = isPR ? statusColumnWidth + statusGap : 0
        let ciOffset = isPR ? numToCIGap + ciIconWidth + ciToTitleGap : numToTitleGap
        return gutterX + statusOffset + numColumnWidth + ciOffset
    }
    static func ciColumnX_popover() -> CGFloat {
        gutterX + statusColumnWidth + statusGap + numColumnWidth + numToCIGap
    }
}

private enum PRDisplayStatus {
    case open
    case draft
    case conflict

    var glyph: String {
        switch self {
        case .open:     return "●"
        case .draft:    return "○"
        case .conflict: return "✗"
        }
    }

    func color() -> NSColor {
        switch self {
        case .open:     return Theme.success
        case .draft:    return Theme.textTertiary
        case .conflict: return Theme.destructive
        }
    }
}

private struct GitHubPopoverRowModel: Equatable {
    let number: Int
    let isPullRequest: Bool
    let isDraft: Bool
    let typeTag: String?
    let title: String
    let author: String
    /// For PRs: head branch (shown in branch column). Nil for issues.
    let branch: String?
    /// Relative age, e.g. "2h ago". For issues, doubles as the right-column date.
    let age: String
    let checkState: GitHubService.CheckState
    let additions: Int
    let deletions: Int

    var prStatus: PRDisplayStatus {
        guard isPullRequest else { return .open }
        if isDraft { return .draft }
        if checkState == .failure { return .conflict }
        return .open
    }
}

private enum ConventionalCommitParser {
    private static let pattern = #"^(feat|fix|chore|docs|style|refactor|perf|test|build|ci|revert)(\([^)]+\))?!?:\s*"#

    static func split(_ title: String) -> (tag: String?, rest: String) {
        guard let range = title.range(of: pattern, options: [.regularExpression, .caseInsensitive]) else {
            return (nil, title)
        }
        let prefix = title[range]
        guard let tagRange = prefix.range(of: #"^[a-zA-Z]+"#, options: .regularExpression) else {
            return (nil, title)
        }
        let tag = String(prefix[tagRange]).lowercased()
        let rest = String(title[range.upperBound...])
        return (tag, rest)
    }
}

private final class GitHubHoverPopoverViewController: NSViewController {
    private struct Model: Equatable {
        let kind: GitHubPopoverKind
        let repoName: String
        let title: String
        let countText: String?
        let rows: [GitHubPopoverRowModel]
        let overflowText: String?
        let stateText: String?
        let showsLoadingIndicator: Bool
    }

    var onHoverChanged: ((Bool) -> Void)?
    var onOpenItem: ((GitHubPopoverRowModel) -> Void)?

    private let contentView = GitHubPopoverContentView()
    private let commandLabel = NSTextField(labelWithString: "")
    private let countLabel = NSTextField(labelWithString: "")
    private let columnStatusLabel = NSTextField(labelWithString: "")
    private let columnHashLabel = NSTextField(labelWithString: "#")
    private let columnCILabel = NSTextField(labelWithString: "CI")
    private let columnTitleLabel = NSTextField(labelWithString: "TITLE")
    private let columnBranchLabel = NSTextField(labelWithString: "BRANCH")
    private let columnDiffLabel = NSTextField(labelWithString: "DIFF")
    private let scrollView = NSScrollView()
    private let stackView = NSStackView()
    private let emptyStateLabel = NSTextField(labelWithString: "")
    private let loadingIndicator = NSProgressIndicator()
    private let previewView = GitHubPopoverPreviewView()
    private let footerKeymapView = GitHubPopoverFooterKeymapView()
    private var rowViews: [GitHubPopoverRowView] = []
    private var selectedIndex: Int = 0
    private var currentModel: Model?

    override func loadView() {
        view = contentView
        contentView.onHoverChanged = { [weak self] hovering in
            self?.onHoverChanged?(hovering)
        }

        commandLabel.font = BellithFont.mono(11.5, weight: .regular)
        commandLabel.lineBreakMode = .byTruncatingMiddle
        view.addSubview(commandLabel)

        countLabel.font = BellithFont.mono(10.5, weight: .regular)
        countLabel.alignment = .right
        view.addSubview(countLabel)

        for label in [columnStatusLabel, columnHashLabel, columnCILabel, columnTitleLabel, columnBranchLabel, columnDiffLabel] {
            label.font = BellithFont.mono(9, weight: .regular)
            label.lineBreakMode = .byTruncatingTail
            view.addSubview(label)
        }
        columnDiffLabel.alignment = .right

        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.scrollerStyle = .overlay
        scrollView.verticalScrollElasticity = .automatic
        view.addSubview(scrollView)

        stackView.orientation = .vertical
        stackView.alignment = .width
        stackView.spacing = 0
        scrollView.documentView = stackView

        emptyStateLabel.font = BellithFont.ui(12, weight: .regular)
        emptyStateLabel.alignment = .center
        emptyStateLabel.maximumNumberOfLines = 3
        emptyStateLabel.lineBreakMode = .byWordWrapping
        emptyStateLabel.isHidden = true
        view.addSubview(emptyStateLabel)

        loadingIndicator.style = .spinning
        loadingIndicator.controlSize = .small
        loadingIndicator.isDisplayedWhenStopped = false
        loadingIndicator.isHidden = true
        view.addSubview(loadingIndicator)

        previewView.isHidden = true
        view.addSubview(previewView)

        footerKeymapView.isHidden = true
        view.addSubview(footerKeymapView)
    }

    func update(
        summary: GitHubService.StatusSummary?,
        details: GitHubService.StatusDetails?,
        kind: GitHubPopoverKind?,
        loading: Bool
    ) {
        let resolvedKind = kind ?? (loading ? .loading : .pullRequests)
        let model = makeModel(summary: summary, details: details, kind: resolvedKind, loading: loading)
        guard currentModel != model else { return }
        currentModel = model
        apply(model)
    }

    override func viewDidLayout() {
        super.viewDidLayout()

        let bounds = view.bounds

        let countWidth = countLabel.isHidden ? 0 : ceil(countLabel.intrinsicContentSize.width)
        let countX = bounds.width - countWidth - 16
        countLabel.frame = NSRect(x: countX, y: bounds.height - 30, width: countWidth, height: 16)

        let commandRightInset = countLabel.isHidden ? 16 : (bounds.width - countX + 16)
        commandLabel.frame = NSRect(
            x: 16,
            y: bounds.height - 30,
            width: bounds.width - 16 - commandRightInset,
            height: 18
        )

        let columnY = bounds.height - 52
        let L = GitHubPopoverLayout.self
        let isPR = (currentModel?.kind ?? .pullRequests) != .issues

        var x = L.gutterX
        if isPR {
            columnStatusLabel.frame = NSRect(x: x, y: columnY, width: L.statusColumnWidth, height: 12)
            x += L.statusColumnWidth + L.statusGap
        } else {
            columnStatusLabel.frame = .zero
        }
        columnStatusLabel.isHidden = !isPR || columnHashLabel.isHidden

        columnHashLabel.frame = NSRect(x: x, y: columnY, width: L.numColumnWidth, height: 12)
        columnHashLabel.alignment = .right
        x += L.numColumnWidth

        if isPR {
            columnCILabel.frame = NSRect(
                x: x + L.numToCIGap,
                y: columnY,
                width: L.ciIconWidth + 8,
                height: 12
            )
            x += L.numToCIGap + L.ciIconWidth + L.ciToTitleGap
            columnCILabel.alignment = .center
        } else {
            x += L.numToTitleGap
        }
        columnCILabel.isHidden = !isPR || columnHashLabel.isHidden

        // Right columns (PR only): branch + diff. Issues use a single date column.
        var rightCursor = bounds.width - L.gutterX
        if isPR {
            columnDiffLabel.frame = NSRect(
                x: rightCursor - L.diffColumnWidth,
                y: columnY,
                width: L.diffColumnWidth,
                height: 12
            )
            rightCursor -= L.diffColumnWidth + L.tailGap
            columnBranchLabel.frame = NSRect(
                x: rightCursor - L.branchColumnWidth,
                y: columnY,
                width: L.branchColumnWidth,
                height: 12
            )
            columnBranchLabel.stringValue = "BRANCH"
            columnBranchLabel.alignment = .left
            rightCursor -= L.branchColumnWidth + L.tailGap
        } else {
            // Issues: date moves into the sub-row, so we don't reserve a tail column.
            columnDiffLabel.frame = .zero
            columnBranchLabel.frame = .zero
        }
        columnDiffLabel.isHidden = !isPR || columnHashLabel.isHidden
        columnBranchLabel.isHidden = !isPR || columnHashLabel.isHidden

        columnTitleLabel.frame = NSRect(
            x: x,
            y: columnY,
            width: max(40, rightCursor - x),
            height: 12
        )

        // Optional preview + footer for PR mode (when rows exist).
        let showsPreview = !previewView.isHidden
        let showsFooter = !footerKeymapView.isHidden
        let footerHeight: CGFloat = 28
        let previewHeight: CGFloat = 56
        var bottomCursor: CGFloat = 0
        if showsFooter {
            footerKeymapView.frame = NSRect(x: 0, y: 0, width: bounds.width, height: footerHeight)
            bottomCursor += footerHeight
        }
        if showsPreview {
            previewView.frame = NSRect(x: 0, y: bottomCursor, width: bounds.width, height: previewHeight)
            bottomCursor += previewHeight
        }

        let bodyTop: CGFloat = 64
        let bodyFrame = NSRect(
            x: L.bodyX,
            y: bottomCursor + 4,
            width: bounds.width - L.bodyX * 2,
            height: bounds.height - bodyTop - bottomCursor - 4
        )
        scrollView.frame = bodyFrame
        stackView.frame = NSRect(origin: .zero, size: NSSize(width: bodyFrame.width, height: stackView.fittingSize.height))

        if !emptyStateLabel.isHidden {
            let stateWidth = min(bodyFrame.width - 28, 240)
            let stateHeight = emptyStateLabel.intrinsicContentSize.height
            emptyStateLabel.frame = NSRect(
                x: floor((bounds.width - stateWidth) / 2),
                y: floor(bodyFrame.minY + (bodyFrame.height - stateHeight) / 2) - 4,
                width: stateWidth,
                height: stateHeight
            )
            let indicatorX = emptyStateLabel.frame.minX - 18
            loadingIndicator.frame = NSRect(x: indicatorX, y: emptyStateLabel.frame.midY - 6, width: 12, height: 12)
        }
    }

    private func makeModel(
        summary: GitHubService.StatusSummary?,
        details: GitHubService.StatusDetails?,
        kind: GitHubPopoverKind,
        loading: Bool
    ) -> Model {
        let repoName = details?.repoName ?? summary?.repoName ?? "GitHub"

        switch kind {
        case .pullRequests:
            let total = details?.openPRs ?? summary?.openPRs ?? 0
            let rows = details?.pullRequests.map { pr -> GitHubPopoverRowModel in
                let (tag, cleanTitle) = ConventionalCommitParser.split(pr.title)
                return GitHubPopoverRowModel(
                    number: pr.number,
                    isPullRequest: true,
                    isDraft: pr.isDraft,
                    typeTag: tag,
                    title: cleanTitle,
                    author: "@\(pr.author)",
                    branch: pr.headBranch,
                    age: pr.createdAt,
                    checkState: pr.checkState,
                    additions: pr.additions,
                    deletions: pr.deletions
                )
            } ?? []
            let stateText: String?
            if loading && details == nil {
                stateText = "Fetching pull requests…"
            } else if total > 0 && rows.isEmpty {
                stateText = "Pull request previews are still loading."
            } else if total == 0 {
                stateText = "No open pull requests."
            } else {
                stateText = nil
            }
            return Model(
                kind: kind,
                repoName: repoName,
                title: "Pull requests",
                countText: total > 0 ? "\(total)" : nil,
                rows: rows,
                overflowText: total > rows.count ? "…and \(total - rows.count) more PRs" : nil,
                stateText: stateText,
                showsLoadingIndicator: loading && rows.isEmpty
            )

        case .issues:
            let total = details?.openIssues ?? summary?.openIssues ?? 0
            let rows = details?.issues.map { issue -> GitHubPopoverRowModel in
                let (tag, cleanTitle) = ConventionalCommitParser.split(issue.title)
                return GitHubPopoverRowModel(
                    number: issue.number,
                    isPullRequest: false,
                    isDraft: false,
                    typeTag: tag,
                    title: cleanTitle,
                    author: "@\(issue.author)",
                    branch: nil,
                    age: issue.createdAt,
                    checkState: .none,
                    additions: 0,
                    deletions: 0
                )
            } ?? []
            let stateText: String?
            if loading && details == nil {
                stateText = "Fetching issues…"
            } else if total > 0 && rows.isEmpty {
                stateText = "Issue previews are still loading."
            } else if total == 0 {
                stateText = "No open issues."
            } else {
                stateText = nil
            }
            return Model(
                kind: kind,
                repoName: repoName,
                title: "Issues",
                countText: total > 0 ? "\(total)" : nil,
                rows: rows,
                overflowText: total > rows.count ? "…and \(total - rows.count) more issues" : nil,
                stateText: stateText,
                showsLoadingIndicator: loading && rows.isEmpty
            )

        case .loading:
            return Model(
                kind: kind,
                repoName: repoName,
                title: "GitHub activity",
                countText: nil,
                rows: [],
                overflowText: nil,
                stateText: "Fetching latest repository activity…",
                showsLoadingIndicator: true
            )
        }
    }

    private func apply(_ model: Model) {
        refreshTheme(for: model.kind)

        commandLabel.attributedStringValue = Self.makeCommandString(kind: model.kind, repo: model.repoName)
        countLabel.stringValue = Self.makeCountText(countText: model.countText, rows: model.rows)
        countLabel.isHidden = model.countText == nil

        let isPR = model.kind != .issues
        columnStatusLabel.stringValue = isPR ? "" : ""
        columnHashLabel.stringValue = "#"
        columnCILabel.stringValue = "CI"
        columnTitleLabel.stringValue = "TITLE"
        columnDiffLabel.stringValue = "DIFF"

        let columnsVisible = !model.rows.isEmpty
        columnStatusLabel.isHidden = !columnsVisible || !isPR
        columnHashLabel.isHidden = !columnsVisible
        columnTitleLabel.isHidden = !columnsVisible
        columnBranchLabel.isHidden = !columnsVisible
        columnCILabel.isHidden = !columnsVisible || !isPR
        columnDiffLabel.isHidden = !columnsVisible || !isPR

        emptyStateLabel.stringValue = model.stateText ?? ""
        emptyStateLabel.isHidden = model.stateText == nil
        scrollView.isHidden = model.rows.isEmpty

        if model.showsLoadingIndicator {
            loadingIndicator.isHidden = false
            loadingIndicator.startAnimation(nil)
        } else {
            loadingIndicator.stopAnimation(nil)
            loadingIndicator.isHidden = true
        }

        // Preview + footer keymap show only for the PR popover when rows are visible.
        let showsPRChrome = isPR && !model.rows.isEmpty
        previewView.isHidden = !showsPRChrome
        footerKeymapView.isHidden = !showsPRChrome
        previewView.refreshTheme()
        footerKeymapView.refreshTheme()

        rebuildRows(rows: model.rows, overflowText: model.overflowText, kind: model.kind)
        selectedIndex = 0
        applySelection()

        let width: CGFloat = 600
        let chromeHeight: CGFloat = (previewView.isHidden ? 0 : 56) + (footerKeymapView.isHidden ? 0 : 28)
        let contentHeight: CGFloat
        if model.rows.isEmpty {
            contentHeight = 118
        } else {
            let rowsHeight = CGFloat(model.rows.count) * 46
            let overflowHeight: CGFloat = model.overflowText == nil ? 0 : 22
            let bodyHeight = min(max(rowsHeight + overflowHeight + 76, 152), 420)
            contentHeight = bodyHeight + chromeHeight
        }
        preferredContentSize = NSSize(width: width, height: contentHeight)
        view.needsLayout = true
    }

    private func refreshTheme(for _: GitHubPopoverKind) {
        contentView.refreshTheme()
        emptyStateLabel.textColor = Theme.textSecondary
        countLabel.textColor = Theme.textTertiary

        let columnColor = Theme.textTertiary.withAlphaComponent(0.7)
        columnStatusLabel.textColor = columnColor
        columnHashLabel.textColor = columnColor
        columnCILabel.textColor = columnColor
        columnTitleLabel.textColor = columnColor
        columnBranchLabel.textColor = columnColor
        columnDiffLabel.textColor = columnColor
    }

    private func applySelection() {
        guard !rowViews.isEmpty else {
            previewView.update(with: nil)
            return
        }
        let clamped = max(0, min(selectedIndex, rowViews.count - 1))
        for (idx, rowView) in rowViews.enumerated() {
            rowView.isSelected = (idx == clamped)
        }
        if let model = currentModel, clamped < model.rows.count {
            previewView.update(with: model.rows[clamped])
        }
    }

    private static func makeCountText(countText: String?, rows: [GitHubPopoverRowModel]) -> String {
        guard let count = countText else { return "" }
        let draftCount = rows.filter { $0.isDraft }.count
        guard draftCount > 0 else { return "\(count) open" }
        return "\(count) open · \(draftCount) draft"
    }

    private static func makeCommandString(kind: GitHubPopoverKind, repo: String) -> NSAttributedString {
        let font = BellithFont.mono(11.5, weight: .regular)
        let subcommand: String
        switch kind {
        case .pullRequests: subcommand = "pr"
        case .issues:       subcommand = "issue"
        case .loading:      subcommand = "status"
        }
        let result = NSMutableAttributedString()
        result.append(NSAttributedString(
            string: "› ",
            attributes: [.font: font, .foregroundColor: Theme.accent]
        ))
        result.append(NSAttributedString(
            string: "gh \(subcommand) list ",
            attributes: [.font: font, .foregroundColor: Theme.textPrimary]
        ))
        result.append(NSAttributedString(
            string: "--repo ",
            attributes: [.font: font, .foregroundColor: Theme.textTertiary]
        ))
        result.append(NSAttributedString(
            string: repo,
            attributes: [.font: font, .foregroundColor: Theme.textPrimary]
        ))
        return result
    }

    private func rebuildRows(rows: [GitHubPopoverRowModel], overflowText: String?, kind: GitHubPopoverKind) {
        stackView.arrangedSubviews.forEach {
            stackView.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }
        rowViews.removeAll(keepingCapacity: true)

        for (idx, row) in rows.enumerated() {
            let rowView = GitHubPopoverRowView(
                row: row,
                kind: kind,
                onPress: { [weak self] row in
                    self?.onOpenItem?(row)
                }
            )
            rowView.onHoverChanged = { [weak self] hovering in
                guard let self, hovering else { return }
                self.selectedIndex = idx
                self.applySelection()
            }
            stackView.addArrangedSubview(rowView)
            rowViews.append(rowView)
        }

        if let overflowText {
            let label = NSTextField(labelWithString: overflowText)
            label.font = BellithFont.mono(10, weight: .regular)
            label.textColor = Theme.textTertiary
            label.alignment = .left
            label.frame.size.height = 18
            stackView.addArrangedSubview(label)
        }
    }
}

private final class GitHubPopoverContentView: NSView {
    var onHoverChanged: ((Bool) -> Void)?

    private let backdrop = NSVisualEffectView()
    private let chromeLayer = CALayer()
    private var borderLayer: CALayer?
    private var trackingAreaRef: NSTrackingArea?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = 12
        layer?.cornerCurve = .continuous

        chromeLayer.cornerRadius = 12
        chromeLayer.cornerCurve = .continuous
        chromeLayer.masksToBounds = true
        layer?.addSublayer(chromeLayer)

        backdrop.material = .popover
        backdrop.blendingMode = .withinWindow
        backdrop.state = .active
        backdrop.wantsLayer = true
        backdrop.layer?.cornerRadius = 12
        backdrop.layer?.cornerCurve = .continuous
        backdrop.layer?.masksToBounds = true
        backdrop.appearance = Theme.overlayAppearance
        addSubview(backdrop, positioned: .below, relativeTo: nil)

        let border = CALayer()
        border.cornerRadius = 12
        border.cornerCurve = .continuous
        border.borderWidth = 1
        backdrop.layer?.addSublayer(border)
        borderLayer = border
        refreshTheme()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        chromeLayer.frame = bounds
        backdrop.frame = bounds
        borderLayer?.frame = bounds
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingAreaRef {
            removeTrackingArea(trackingAreaRef)
        }
        let area = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeInKeyWindow], owner: self, userInfo: nil)
        addTrackingArea(area)
        trackingAreaRef = area
    }

    override func mouseEntered(with event: NSEvent) {
        onHoverChanged?(true)
    }

    override func mouseExited(with event: NSEvent) {
        onHoverChanged?(false)
    }

    func refreshTheme() {
        backdrop.appearance = Theme.overlayAppearance
        chromeLayer.backgroundColor = Theme.chromeElevated.withAlphaComponent(0.98).cgColor
        backdrop.layer?.backgroundColor = Theme.chromePanel.withAlphaComponent(0.9).cgColor
        borderLayer?.borderColor = Theme.chromeHairline.cgColor
    }
}

private final class GitHubPopoverRowView: NSView {
    private let row: GitHubPopoverRowModel
    private let kind: GitHubPopoverKind
    private let onPress: (GitHubPopoverRowModel) -> Void
    private enum Metrics {
        static let hoverInsetY: CGFloat = 1
        static let topRowY: CGFloat = 22
        static let subRowY: CGFloat = 4
        static let topRowHeight: CGFloat = 16
        static let subRowHeight: CGFloat = 13
    }
    private let backgroundView = NSView()
    private let accentBar = NSView()
    private let statusGlyphLabel = NSTextField(labelWithString: "")
    private let numberLabel = NSTextField(labelWithString: "")
    private let ciIconView = NSImageView()
    private let tagView = NSView()
    private let tagLabel = NSTextField(labelWithString: "")
    private let titleLabel = NSTextField(labelWithString: "")
    private let subRowLabel = NSTextField(labelWithString: "")
    private let branchLabel = NSTextField(labelWithString: "")
    private let diffLabel = NSTextField(labelWithString: "")
    var onHoverChanged: ((Bool) -> Void)?
    private var trackingAreaRef: NSTrackingArea?
    var isSelected = false {
        didSet {
            guard oldValue != isSelected else { return }
            refreshTheme()
        }
    }
    private var isHovered = false {
        didSet {
            guard oldValue != isHovered else { return }
            refreshTheme()
            onHoverChanged?(isHovered)
        }
    }

    init(row: GitHubPopoverRowModel, kind: GitHubPopoverKind, onPress: @escaping (GitHubPopoverRowModel) -> Void) {
        self.row = row
        self.kind = kind
        self.onPress = onPress
        super.init(frame: .zero)
        wantsLayer = true

        backgroundView.wantsLayer = true
        backgroundView.layer?.cornerRadius = 4
        backgroundView.layer?.cornerCurve = .continuous
        addSubview(backgroundView)

        accentBar.wantsLayer = true
        accentBar.layer?.cornerRadius = 1
        backgroundView.addSubview(accentBar)

        if row.isPullRequest {
            statusGlyphLabel.stringValue = row.prStatus.glyph
            statusGlyphLabel.font = BellithFont.mono(13, weight: .bold)
            statusGlyphLabel.alignment = .center
            statusGlyphLabel.textColor = row.prStatus.color()
            backgroundView.addSubview(statusGlyphLabel)
        } else {
            statusGlyphLabel.isHidden = true
        }

        numberLabel.stringValue = "#\(row.number)"
        numberLabel.font = BellithFont.mono(11, weight: .regular)
        numberLabel.alignment = .right
        numberLabel.lineBreakMode = .byTruncatingMiddle
        backgroundView.addSubview(numberLabel)

        ciIconView.imageScaling = .scaleProportionallyDown
        ciIconView.isHidden = !row.isPullRequest
        backgroundView.addSubview(ciIconView)

        tagView.wantsLayer = true
        tagView.layer?.cornerRadius = 3
        tagView.layer?.cornerCurve = .continuous
        tagView.isHidden = row.typeTag == nil
        backgroundView.addSubview(tagView)

        tagLabel.stringValue = (row.typeTag ?? "")
        tagLabel.font = BellithFont.mono(9.5, weight: .medium)
        tagLabel.alignment = .center
        tagView.addSubview(tagLabel)

        titleLabel.lineBreakMode = .byTruncatingTail
        backgroundView.addSubview(titleLabel)

        subRowLabel.font = BellithFont.mono(10, weight: .regular)
        subRowLabel.lineBreakMode = .byTruncatingTail
        subRowLabel.alignment = .left
        backgroundView.addSubview(subRowLabel)

        branchLabel.font = BellithFont.mono(10.5, weight: .regular)
        branchLabel.lineBreakMode = .byTruncatingMiddle
        branchLabel.alignment = .left
        branchLabel.isHidden = !row.isPullRequest || (row.branch?.isEmpty ?? true)
        backgroundView.addSubview(branchLabel)

        diffLabel.font = BellithFont.mono(10, weight: .regular)
        diffLabel.alignment = .right
        diffLabel.lineBreakMode = .byTruncatingTail
        diffLabel.isHidden = !row.isPullRequest || (row.additions == 0 && row.deletions == 0)
        backgroundView.addSubview(diffLabel)

        translatesAutoresizingMaskIntoConstraints = false
        heightAnchor.constraint(equalToConstant: 46).isActive = true

        refreshTheme()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingAreaRef {
            removeTrackingArea(trackingAreaRef)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingAreaRef = area
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .pointingHand)
    }

    override func mouseEntered(with event: NSEvent) {
        isHovered = true
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
    }

    override func mouseDown(with event: NSEvent) {
        onPress(row)
    }

    override func layout() {
        super.layout()
        let L = GitHubPopoverLayout.self
        backgroundView.frame = bounds.insetBy(dx: L.rowHoverInsetX, dy: Metrics.hoverInsetY)

        let contentWidth = backgroundView.bounds.width
        let topY = Metrics.topRowY
        let subY = Metrics.subRowY

        accentBar.frame = NSRect(x: 0, y: 6, width: 2, height: backgroundView.bounds.height - 12)

        var x = L.rowContentInsetX

        if row.isPullRequest {
            statusGlyphLabel.frame = NSRect(
                x: x,
                y: topY,
                width: L.statusColumnWidth,
                height: Metrics.topRowHeight
            )
            x += L.statusColumnWidth + L.statusGap
        }

        numberLabel.frame = NSRect(
            x: x,
            y: topY + 1,
            width: L.numColumnWidth,
            height: Metrics.topRowHeight
        )
        x += L.numColumnWidth

        if row.isPullRequest {
            x += L.numToCIGap
            ciIconView.frame = NSRect(
                x: x,
                y: topY + 2,
                width: L.ciIconWidth,
                height: 14
            )
            x += L.ciIconWidth + L.ciToTitleGap
        } else {
            x += L.numToTitleGap
        }

        let titleColumnX = x

        // Right-side columns (PR only): branch then diff (rightmost).
        let rightInset = L.rowContentInsetX
        var rightCursor = contentWidth - rightInset
        var diffWidth: CGFloat = 0
        if !diffLabel.isHidden {
            diffWidth = L.diffColumnWidth
            diffLabel.frame = NSRect(
                x: rightCursor - diffWidth,
                y: topY + 1,
                width: diffWidth,
                height: Metrics.topRowHeight
            )
            rightCursor -= diffWidth + L.tailGap
        }
        var branchWidth: CGFloat = 0
        if !branchLabel.isHidden {
            branchWidth = L.branchColumnWidth
            branchLabel.frame = NSRect(
                x: rightCursor - branchWidth,
                y: topY + 1,
                width: branchWidth,
                height: Metrics.topRowHeight
            )
            rightCursor -= branchWidth + L.tailGap
        }

        // Title row (with optional type label).
        var titleX = titleColumnX
        if !tagView.isHidden {
            let tagIntrinsic = ceil(tagLabel.intrinsicContentSize.width)
            let tagWidth = min(tagIntrinsic + 10, 64)
            tagView.frame = NSRect(x: titleColumnX, y: topY + 1, width: tagWidth, height: 15)
            tagLabel.frame = tagView.bounds
            titleX = titleColumnX + tagWidth + 8
        }
        let titleMaxX = max(titleX + 40, rightCursor)
        titleLabel.frame = NSRect(
            x: titleX,
            y: topY,
            width: titleMaxX - titleX,
            height: 18
        )

        // Sub-row spans the title region.
        let subMaxX: CGFloat = {
            if !diffLabel.isHidden { return contentWidth - rightInset - diffWidth - L.tailGap }
            if !branchLabel.isHidden { return contentWidth - rightInset - branchWidth - L.tailGap }
            return contentWidth - rightInset
        }()
        subRowLabel.frame = NSRect(
            x: titleColumnX,
            y: subY,
            width: subMaxX - titleColumnX,
            height: Metrics.subRowHeight
        )
    }

    private func refreshTheme() {
        let isActive = isSelected || isHovered
        backgroundView.layer?.backgroundColor = isActive
            ? Theme.chromeElevated.withAlphaComponent(0.5).cgColor
            : NSColor.clear.cgColor
        accentBar.layer?.backgroundColor = isActive ? Theme.accent.cgColor : NSColor.clear.cgColor

        statusGlyphLabel.textColor = row.prStatus.color()
        numberLabel.textColor = Theme.textTertiary
        titleLabel.attributedStringValue = Self.makeTitle(row.title, isDraft: row.isDraft)
        subRowLabel.attributedStringValue = Self.makeSubRowString(row: row)

        let tagColors = Self.tagColors(for: row.typeTag)
        tagView.layer?.backgroundColor = tagColors.fill.cgColor
        tagView.layer?.borderColor = tagColors.border.cgColor
        tagView.layer?.borderWidth = 1
        tagLabel.textColor = tagColors.text

        if row.isPullRequest {
            let ci = Self.ciIconSpec(for: row.checkState)
            ciIconView.image = NSImage(systemSymbolName: ci.symbol, accessibilityDescription: nil)
            ciIconView.contentTintColor = ci.tint
        }

        if !branchLabel.isHidden, let branch = row.branch {
            branchLabel.attributedStringValue = Self.makeBranchString(branch)
        }

        if !diffLabel.isHidden {
            diffLabel.attributedStringValue = Self.makeDiffString(
                additions: row.additions, deletions: row.deletions
            )
        }
    }

    private static func ciIconSpec(for state: GitHubService.CheckState) -> (symbol: String, tint: NSColor) {
        switch state {
        case .success: return ("checkmark", Theme.success)
        case .failure: return ("xmark", Theme.destructive)
        case .pending: return ("circle.dotted", Theme.warning)
        case .none:    return ("minus", Theme.textTertiary.withAlphaComponent(0.5))
        }
    }

    private static func makeBranchString(_ branch: String) -> NSAttributedString {
        let font = BellithFont.mono(10.5, weight: .regular)
        let result = NSMutableAttributedString()
        result.append(NSAttributedString(
            string: "⎇ ",
            attributes: [.font: font, .foregroundColor: Theme.textTertiary.withAlphaComponent(0.7)]
        ))
        result.append(NSAttributedString(
            string: branch,
            attributes: [.font: font, .foregroundColor: Theme.textTertiary]
        ))
        return result
    }

    private static func makeDiffString(additions: Int, deletions: Int) -> NSAttributedString {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        let plus = formatter.string(from: NSNumber(value: additions)) ?? "\(additions)"
        let minus = formatter.string(from: NSNumber(value: deletions)) ?? "\(deletions)"
        let font = BellithFont.mono(10, weight: .regular)
        let result = NSMutableAttributedString()
        result.append(NSAttributedString(
            string: "+\(plus) ",
            attributes: [.font: font, .foregroundColor: Theme.success]
        ))
        result.append(NSAttributedString(
            string: "−\(minus)",
            attributes: [.font: font, .foregroundColor: Theme.destructive]
        ))
        return result
    }

    private static func makeSubRowString(row: GitHubPopoverRowModel) -> NSAttributedString {
        let font = BellithFont.mono(10, weight: .regular)
        let secondary = Theme.textTertiary
        let muted = Theme.textTertiary.withAlphaComponent(0.5)
        let result = NSMutableAttributedString()
        result.append(NSAttributedString(
            string: row.author,
            attributes: [.font: font, .foregroundColor: secondary]
        ))
        if !row.age.isEmpty {
            result.append(NSAttributedString(
                string: " · ",
                attributes: [.font: font, .foregroundColor: muted]
            ))
            result.append(NSAttributedString(
                string: row.age,
                attributes: [.font: font, .foregroundColor: secondary]
            ))
        }
        return result
    }

    private static func makeTitle(_ title: String, isDraft: Bool) -> NSAttributedString {
        NSAttributedString(
            string: title,
            attributes: [
                .font: BellithFont.ui(13, weight: .medium),
                .foregroundColor: isDraft ? Theme.textSecondary : Theme.textPrimary,
            ]
        )
    }

    private static func tagColors(for tag: String?) -> (fill: NSColor, border: NSColor, text: NSColor) {
        switch tag {
        case "feat", "perf":
            return (Theme.success.withAlphaComponent(0.14), Theme.success.withAlphaComponent(0.30), Theme.success)
        case "fix", "revert":
            return (Theme.warning.withAlphaComponent(0.14), Theme.warning.withAlphaComponent(0.30), Theme.warning)
        case "docs":
            let blue = Theme.accent
            return (blue.withAlphaComponent(0.14), blue.withAlphaComponent(0.30), blue)
        case "refactor", "style":
            // Magenta-ish: blend destructive + accent
            let pink = NSColor(red: 0.86, green: 0.45, blue: 0.78, alpha: 1.0)
            return (pink.withAlphaComponent(0.14), pink.withAlphaComponent(0.30), pink)
        case "chore", "build", "ci", "test":
            return (Theme.borderSubtle.withAlphaComponent(0.5), Theme.borderSubtle, Theme.textTertiary)
        default:
            return (NSColor.clear, Theme.borderSubtle, Theme.textTertiary)
        }
    }
}

private final class GitHubPopoverPreviewView: NSView {
    private let topDivider = CALayer()
    private let branchLabel = NSTextField(labelWithString: "")
    private let metaLabel = NSTextField(labelWithString: "")
    private let actionsContainer = NSStackView()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true

        layer?.addSublayer(topDivider)

        branchLabel.font = BellithFont.mono(11, weight: .regular)
        branchLabel.lineBreakMode = .byTruncatingMiddle
        addSubview(branchLabel)

        metaLabel.font = BellithFont.mono(10, weight: .regular)
        metaLabel.lineBreakMode = .byTruncatingTail
        addSubview(metaLabel)

        actionsContainer.orientation = .horizontal
        actionsContainer.spacing = 4
        actionsContainer.alignment = .centerY
        actionsContainer.distribution = .fill
        addSubview(actionsContainer)

        actionsContainer.addArrangedSubview(Self.makeAction(label: "Checkout", kbd: "⏎", primary: false))
        actionsContainer.addArrangedSubview(Self.makeAction(label: "Diff", kbd: "d", primary: false))
        actionsContainer.addArrangedSubview(Self.makeAction(label: "Open", kbd: "⇧⏎", primary: true))

        refreshTheme()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        topDivider.frame = NSRect(x: 0, y: bounds.height - 1, width: bounds.width, height: 1)
        let inset: CGFloat = 14
        let actionsSize = actionsContainer.fittingSize
        let actionsX = bounds.width - inset - actionsSize.width
        actionsContainer.frame = NSRect(
            x: actionsX,
            y: floor((bounds.height - actionsSize.height) / 2),
            width: actionsSize.width,
            height: actionsSize.height
        )

        let leftMaxX = actionsX - 12
        branchLabel.frame = NSRect(
            x: inset,
            y: bounds.height - 24,
            width: leftMaxX - inset,
            height: 16
        )
        metaLabel.frame = NSRect(
            x: inset,
            y: 8,
            width: leftMaxX - inset,
            height: 14
        )
    }

    func update(with row: GitHubPopoverRowModel?) {
        guard let row else {
            branchLabel.stringValue = ""
            metaLabel.stringValue = ""
            return
        }
        branchLabel.attributedStringValue = Self.makeBranchString(row)
        metaLabel.attributedStringValue = Self.makeMetaString(row)
    }

    func refreshTheme() {
        layer?.backgroundColor = Theme.chromePanel.withAlphaComponent(0.6).cgColor
        topDivider.backgroundColor = Theme.chromeHairline.cgColor
    }

    private static func makeBranchString(_ row: GitHubPopoverRowModel) -> NSAttributedString {
        let font = BellithFont.mono(11, weight: .regular)
        let result = NSMutableAttributedString()
        result.append(NSAttributedString(
            string: "main",
            attributes: [.font: font, .foregroundColor: Theme.textTertiary]
        ))
        result.append(NSAttributedString(
            string: "  ←  ",
            attributes: [.font: font, .foregroundColor: Theme.textTertiary.withAlphaComponent(0.5)]
        ))
        result.append(NSAttributedString(
            string: row.branch ?? "",
            attributes: [.font: font, .foregroundColor: Theme.accent]
        ))
        return result
    }

    private static func makeMetaString(_ row: GitHubPopoverRowModel) -> NSAttributedString {
        let font = BellithFont.mono(10, weight: .regular)
        let muted = Theme.textTertiary
        let dim = Theme.textTertiary.withAlphaComponent(0.5)
        let result = NSMutableAttributedString()

        if row.additions > 0 || row.deletions > 0 {
            let formatter = NumberFormatter()
            formatter.numberStyle = .decimal
            let plus = formatter.string(from: NSNumber(value: row.additions)) ?? "\(row.additions)"
            let minus = formatter.string(from: NSNumber(value: row.deletions)) ?? "\(row.deletions)"
            result.append(NSAttributedString(
                string: "+\(plus) ",
                attributes: [.font: font, .foregroundColor: Theme.success]
            ))
            result.append(NSAttributedString(
                string: "−\(minus)",
                attributes: [.font: font, .foregroundColor: Theme.destructive]
            ))
            if !row.age.isEmpty {
                result.append(NSAttributedString(
                    string: "   ·   ",
                    attributes: [.font: font, .foregroundColor: dim]
                ))
            }
        }
        if !row.age.isEmpty {
            result.append(NSAttributedString(
                string: "updated ",
                attributes: [.font: font, .foregroundColor: dim]
            ))
            result.append(NSAttributedString(
                string: row.age,
                attributes: [.font: font, .foregroundColor: muted]
            ))
        }
        return result
    }

    private static func makeAction(label: String, kbd: String, primary: Bool) -> NSView {
        let view = NSView()
        view.wantsLayer = true
        view.layer?.cornerRadius = 4
        view.layer?.cornerCurve = .continuous
        view.layer?.borderWidth = 1
        let fill: NSColor
        let border: NSColor
        let textColor: NSColor
        if primary {
            fill = Theme.accent.withAlphaComponent(0.14)
            border = Theme.accent.withAlphaComponent(0.34)
            textColor = Theme.accent
        } else {
            fill = Theme.chromeElevated.withAlphaComponent(0.6)
            border = Theme.chromeHairline
            textColor = Theme.textSecondary
        }
        view.layer?.backgroundColor = fill.cgColor
        view.layer?.borderColor = border.cgColor

        let labelView = NSTextField(labelWithString: label)
        labelView.font = BellithFont.mono(10.5, weight: .regular)
        labelView.textColor = textColor
        view.addSubview(labelView)

        let kbdView = NSTextField(labelWithString: kbd)
        kbdView.font = BellithFont.mono(9.5, weight: .regular)
        kbdView.textColor = primary ? Theme.accent.withAlphaComponent(0.7) : Theme.textTertiary.withAlphaComponent(0.7)
        view.addSubview(kbdView)

        labelView.translatesAutoresizingMaskIntoConstraints = false
        kbdView.translatesAutoresizingMaskIntoConstraints = false
        view.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            view.heightAnchor.constraint(equalToConstant: 22),
            labelView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 8),
            labelView.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            kbdView.leadingAnchor.constraint(equalTo: labelView.trailingAnchor, constant: 6),
            kbdView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -8),
            kbdView.centerYAnchor.constraint(equalTo: view.centerYAnchor),
        ])
        return view
    }
}

private final class GitHubPopoverFooterKeymapView: NSView {
    private let topDivider = CALayer()
    private let stack = NSStackView()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.addSublayer(topDivider)

        stack.orientation = .horizontal
        stack.spacing = 14
        stack.alignment = .centerY
        addSubview(stack)

        let entries: [(String, String)] = [
            ("↑↓", "navigate"),
            ("⏎",  "checkout"),
            ("d",  "diff"),
            ("r",  "review"),
            ("m",  "merge"),
            ("esc", "close"),
        ]
        for (kbd, label) in entries {
            stack.addArrangedSubview(Self.makeEntry(kbd: kbd, label: label))
        }
        refreshTheme()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        topDivider.frame = NSRect(x: 0, y: bounds.height - 1, width: bounds.width, height: 1)
        let stackSize = stack.fittingSize
        stack.frame = NSRect(
            x: 14,
            y: floor((bounds.height - stackSize.height) / 2),
            width: bounds.width - 28,
            height: stackSize.height
        )
    }

    func refreshTheme() {
        layer?.backgroundColor = Theme.chromePanel.withAlphaComponent(0.5).cgColor
        topDivider.backgroundColor = Theme.chromeHairline.cgColor
    }

    private static func makeEntry(kbd: String, label: String) -> NSView {
        let row = NSStackView()
        row.orientation = .horizontal
        row.spacing = 5
        row.alignment = .centerY

        let kbdView = NSTextField(labelWithString: kbd)
        kbdView.font = BellithFont.mono(9.5, weight: .regular)
        kbdView.textColor = Theme.textSecondary
        kbdView.wantsLayer = true
        kbdView.layer?.cornerRadius = 3
        kbdView.layer?.cornerCurve = .continuous
        kbdView.layer?.borderWidth = 1
        kbdView.layer?.borderColor = Theme.chromeHairline.cgColor
        kbdView.layer?.backgroundColor = Theme.chromeElevated.withAlphaComponent(0.6).cgColor
        kbdView.alignment = .center
        let kbdSize = kbdView.intrinsicContentSize
        let kbdWidth = max(kbdSize.width + 10, 18)
        kbdView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            kbdView.widthAnchor.constraint(greaterThanOrEqualToConstant: kbdWidth),
            kbdView.heightAnchor.constraint(equalToConstant: 16),
        ])

        let labelView = NSTextField(labelWithString: label)
        labelView.font = BellithFont.mono(10, weight: .regular)
        labelView.textColor = Theme.textTertiary

        row.addArrangedSubview(kbdView)
        row.addArrangedSubview(labelView)
        return row
    }
}
