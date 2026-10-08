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
