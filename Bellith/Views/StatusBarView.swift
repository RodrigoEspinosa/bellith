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
    private let ghPRSegment = GitHubStatusSegmentView(symbolName: "arrow.triangle.pull", tintColor: Theme.accent)
    private let ghIssueSegment = GitHubStatusSegmentView(symbolName: "exclamationmark.circle", tintColor: Theme.warning)
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

        ghPRSegment.attributedTitle = Self.gitHubCountAttributedText(
            count: prCount,
            label: prCount == 1 ? "PR" : "PRS",
            color: Theme.accent
        )
        ghIssueSegment.attributedTitle = Self.gitHubCountAttributedText(
            count: issueCount,
            label: issueCount == 1 ? "ISSUE" : "ISSUES",
            color: Theme.warning
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

    private static func gitHubCountAttributedText(
        count: Int,
        label: String,
        color: NSColor
    ) -> NSAttributedString {
        NSAttributedString(
            string: "\(label) \(count)",
            attributes: [
                .font: BellithFont.mono(10.5, weight: .medium),
                .foregroundColor: color,
            ]
        )
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
            } else {
                let segmentGap: CGFloat = 6
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
    private let label = NSTextField(labelWithString: "")
    private let underlineView = NSView()
    private var tintColor: NSColor

    var attributedTitle: NSAttributedString = NSAttributedString() {
        didSet {
            label.attributedStringValue = attributedTitle
            invalidateIntrinsicContentSize()
            needsLayout = true
        }
    }

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

        label.isEditable = false
        label.isBezeled = false
        label.drawsBackground = false
        label.maximumNumberOfLines = 1
        addSubview(label)

        underlineView.wantsLayer = true
        underlineView.isHidden = true
        addSubview(underlineView)

        refreshTheme(tintColor: tintColor)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override var intrinsicContentSize: NSSize {
        let labelWidth = label.attributedStringValue.size().width.rounded(.up)
        return NSSize(width: labelWidth + 6, height: 18)
    }

    override func layout() {
        super.layout()
        label.frame = NSRect(x: 0, y: floor((bounds.height - 13) / 2), width: bounds.width, height: 13)
        underlineView.frame = NSRect(x: 0, y: 0, width: bounds.width, height: 1)
    }

    func refreshTheme(tintColor: NSColor) {
        self.tintColor = tintColor
        applyAppearance(animated: false)
    }

    private func applyAppearance(animated: Bool) {
        let updates = {
            self.underlineView.isHidden = !self.isHighlighted
            self.underlineView.layer?.backgroundColor = self.tintColor.withAlphaComponent(0.85).cgColor
            self.label.alphaValue = self.isHighlighted ? 1.0 : 0.92
        }

        if animated {
            Theme.animate(duration: 0.08) { _ in updates() }
        } else {
            updates()
        }
    }
}

private struct GitHubPopoverRowModel: Equatable {
    let number: Int
    let isPullRequest: Bool
    let title: String
    let subtitle: String
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
    private let headerIconView = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let repoLabel = NSTextField(labelWithString: "")
    private let countPill = NSView()
    private let countLabel = NSTextField(labelWithString: "")
    private let separatorLine = NSView()
    private let scrollView = NSScrollView()
    private let stackView = NSStackView()
    private let emptyStateLabel = NSTextField(labelWithString: "")
    private let loadingIndicator = NSProgressIndicator()
    private var currentModel: Model?
    private let countLabelVerticalInset: CGFloat = 2

    override func loadView() {
        view = contentView
        contentView.onHoverChanged = { [weak self] hovering in
            self?.onHoverChanged?(hovering)
        }

        headerIconView.imageScaling = .scaleProportionallyDown
        view.addSubview(headerIconView)

        titleLabel.font = BellithFont.ui(13.5, weight: .semibold)
        titleLabel.lineBreakMode = .byTruncatingTail
        view.addSubview(titleLabel)

        repoLabel.font = BellithFont.mono(10, weight: .regular)
        repoLabel.lineBreakMode = .byTruncatingMiddle
        view.addSubview(repoLabel)

        countPill.wantsLayer = true
        countPill.layer?.cornerRadius = 9
        countPill.layer?.cornerCurve = .continuous
        view.addSubview(countPill)

        countLabel.font = BellithFont.mono(11, weight: .medium)
        countLabel.alignment = .center
        countPill.addSubview(countLabel)

        separatorLine.wantsLayer = true
        view.addSubview(separatorLine)

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
        headerIconView.frame = NSRect(x: 18, y: bounds.height - 34, width: 15, height: 15)

        let pillWidth = countPill.isHidden ? 0 : max(32, countLabel.intrinsicContentSize.width + 16)
        let pillX = bounds.width - pillWidth - 18
        if !countPill.isHidden {
            countPill.frame = NSRect(x: pillX, y: bounds.height - 37, width: pillWidth, height: 22)
            let labelSize = countLabel.intrinsicContentSize
            countLabel.frame = NSRect(
                x: floor((pillWidth - labelSize.width) / 2),
                y: floor((countPill.bounds.height - labelSize.height) / 2) + countLabelVerticalInset,
                width: labelSize.width,
                height: labelSize.height
            )
        }

        let titleRightInset = countPill.isHidden ? 18 : (bounds.width - pillX + 12)
        titleLabel.frame = NSRect(x: 40, y: bounds.height - 35, width: bounds.width - 40 - titleRightInset, height: 18)
        repoLabel.frame = NSRect(x: 18, y: bounds.height - 56, width: bounds.width - 36, height: 13)
        separatorLine.frame = NSRect(x: 18, y: bounds.height - 68, width: bounds.width - 36, height: 1)

        let bodyFrame = NSRect(x: 16, y: 16, width: bounds.width - 32, height: bounds.height - 90)
        scrollView.frame = bodyFrame
        stackView.frame = NSRect(origin: .zero, size: NSSize(width: bodyFrame.width, height: stackView.fittingSize.height))

        if !emptyStateLabel.isHidden {
            let stateWidth = min(bodyFrame.width - 28, 230)
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
            let rows = details?.pullRequests.map {
                GitHubPopoverRowModel(
                    number: $0.number,
                    isPullRequest: true,
                    title: "#\($0.number) \($0.title)",
                    subtitle: "@\($0.author) · \($0.headBranch)"
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
            let rows = details?.issues.map {
                GitHubPopoverRowModel(
                    number: $0.number,
                    isPullRequest: false,
                    title: "#\($0.number) \($0.title)",
                    subtitle: "@\($0.author) · \($0.createdAt)"
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

        titleLabel.stringValue = model.title
        repoLabel.stringValue = model.repoName
        countPill.isHidden = model.countText == nil
        countLabel.stringValue = model.countText ?? ""
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

        rebuildRows(rows: model.rows, overflowText: model.overflowText, kind: model.kind)

        let width: CGFloat = 432
        let contentHeight: CGFloat
        if model.rows.isEmpty {
            contentHeight = 118
        } else {
            contentHeight = min(max(CGFloat(model.rows.count) * 52 + (model.overflowText == nil ? 0 : 22) + 96, 152), 412)
        }
        preferredContentSize = NSSize(width: width, height: contentHeight)
        view.needsLayout = true
    }

    private func refreshTheme(for kind: GitHubPopoverKind) {
        contentView.refreshTheme()
        separatorLine.layer?.backgroundColor = Theme.chromeHairline.cgColor
        titleLabel.textColor = Theme.textPrimary
        repoLabel.textColor = Theme.textTertiary
        emptyStateLabel.textColor = Theme.textSecondary

        let accent: NSColor
        let symbolName: String
        switch kind {
        case .pullRequests:
            accent = Theme.accent
            symbolName = "arrow.triangle.pull"
        case .issues:
            accent = Theme.warning
            symbolName = "exclamationmark.circle"
        case .loading:
            accent = Theme.accent
            symbolName = "clock.arrow.trianglehead.counterclockwise.rotate.90"
        }

        headerIconView.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)
        headerIconView.contentTintColor = accent
        countPill.layer?.backgroundColor = accent.withAlphaComponent(0.14).cgColor
        countPill.layer?.borderWidth = 1
        countPill.layer?.borderColor = accent.withAlphaComponent(0.22).cgColor
        countLabel.textColor = accent
    }

    private func rebuildRows(rows: [GitHubPopoverRowModel], overflowText: String?, kind: GitHubPopoverKind) {
        stackView.arrangedSubviews.forEach {
            stackView.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }

        for (index, row) in rows.enumerated() {
            stackView.addArrangedSubview(
                GitHubPopoverRowView(
                    row: row,
                    kind: kind,
                    showsDivider: index < rows.count - 1,
                    onPress: { [weak self] row in
                        self?.onOpenItem?(row)
                    }
                )
            )
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
    private let showsDivider: Bool
    private let onPress: (GitHubPopoverRowModel) -> Void
    private let backgroundView = NSView()
    private let accentBar = NSView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let subtitleLabel = NSTextField(labelWithString: "")
    private let dividerLine = NSView()
    private var trackingAreaRef: NSTrackingArea?
    private var isHovered = false {
        didSet {
            guard oldValue != isHovered else { return }
            refreshTheme()
        }
    }

    init(row: GitHubPopoverRowModel, kind: GitHubPopoverKind, showsDivider: Bool, onPress: @escaping (GitHubPopoverRowModel) -> Void) {
        self.row = row
        self.kind = kind
        self.showsDivider = showsDivider
        self.onPress = onPress
        super.init(frame: .zero)
        wantsLayer = true

        backgroundView.wantsLayer = true
        addSubview(backgroundView)

        accentBar.wantsLayer = true
        accentBar.layer?.cornerRadius = 1
        accentBar.layer?.cornerCurve = .continuous
        accentBar.isHidden = true
        backgroundView.addSubview(accentBar)

        titleLabel.font = BellithFont.ui(13, weight: .semibold)
        titleLabel.lineBreakMode = .byTruncatingTail
        backgroundView.addSubview(titleLabel)

        subtitleLabel.stringValue = row.subtitle
        subtitleLabel.font = BellithFont.mono(10.5, weight: .regular)
        subtitleLabel.lineBreakMode = .byTruncatingTail
        backgroundView.addSubview(subtitleLabel)

        dividerLine.wantsLayer = true
        dividerLine.isHidden = !showsDivider
        backgroundView.addSubview(dividerLine)

        translatesAutoresizingMaskIntoConstraints = false
        heightAnchor.constraint(equalToConstant: 52).isActive = true

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
        backgroundView.frame = bounds
        accentBar.frame = NSRect(x: 0, y: 8, width: 2, height: bounds.height - 16)
        titleLabel.frame = NSRect(x: 12, y: bounds.height - 24, width: bounds.width - 20, height: 17)
        subtitleLabel.frame = NSRect(x: 12, y: 10, width: bounds.width - 20, height: 14)
        dividerLine.frame = NSRect(x: 12, y: 0, width: bounds.width - 12, height: 1)
    }

    private func refreshTheme() {
        let accent: NSColor = switch kind {
        case .pullRequests, .loading:
            Theme.accent
        case .issues:
            Theme.warning
        }
        backgroundView.layer?.backgroundColor = isHovered ? Theme.hoverOverlay.withAlphaComponent(1.35).cgColor : NSColor.clear.cgColor
        accentBar.isHidden = !isHovered
        accentBar.layer?.backgroundColor = accent.cgColor
        titleLabel.attributedStringValue = Self.makeTitle(row.title, accent: accent)
        subtitleLabel.textColor = Theme.textTertiary
        dividerLine.layer?.backgroundColor = Theme.borderSubtle.cgColor
    }

    private static func makeTitle(_ title: String, accent: NSColor) -> NSAttributedString {
        let attributed = NSMutableAttributedString(
            string: title,
            attributes: [
                .font: BellithFont.ui(13, weight: .semibold),
                .foregroundColor: Theme.textPrimary,
            ]
        )

        if let range = title.range(of: #"^#\d+"#, options: .regularExpression) {
            let nsRange = NSRange(range, in: title)
            attributed.addAttributes([
                .foregroundColor: accent,
                .font: BellithFont.mono(11.5, weight: .medium),
            ], range: nsRange)
        }

        return attributed
    }
}
