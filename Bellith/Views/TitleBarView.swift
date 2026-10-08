import AppKit
import QuartzCore

/// Compact context strip for the active working directory and shell state.
final class TitleBarView: NSView {
    private let settings: BellithSettings
    private enum Metrics {
        static let textSize: CGFloat = 14.5
        static let metaTextSize: CGFloat = 13
        static let sizeTextSize: CGFloat = 13
        static let iconSize: CGFloat = 14
        static let chevronSize: CGFloat = 8
        static let labelHeight: CGFloat = 18
    }

    private let backdropLayer = CALayer()
    private let innerStrokeLayer = CALayer()
    private let leftGlowLayer = CAGradientLayer()
    private let bottomSeparatorLayer = CALayer()

    private let folderIcon = NSImageView()
    private let hostBadge = ContextBadgeView()
    private let environmentBadge = ContextBadgeView()
    private let worktreeBadge = ContextBadgeView()
    private let gitIcon = NSImageView()
    private let gitLabel = NSTextField(labelWithString: "")
    private let processIcon = NSImageView()
    private let processLabel = NSTextField(labelWithString: "")
    private let sizeLabel = NSTextField(labelWithString: "")
    private let centerTitleLabel = NSTextField(labelWithString: "")
    private let panePill = PaneCountPillView()
    private let backgroundGradient = CAGradientLayer()
    private let bottomLineLayer = CALayer()

    private var breadcrumbViews: [NSView] = []
    private var currentPath: String = "~"
    private var currentGitBranch: String?
    private var currentProcess: String?
    private var currentProcessPresentation: ForegroundProcessPresentation?
    private var currentContext: TerminalContext?
    private var currentSessionShell: String = "zsh"
    private var currentWorkspaceName: String = ""
    private var currentPaneCount: Int = 1
    private var segmentTrackingAreas: [NSTrackingArea] = []
    private var hoveredView: NSView?

    /// Whether the centered title takes over (always, in PR Popover v2 chrome).
    private var hidesBreadcrumbsForTitle: Bool { true }

    var leadingInset: CGFloat = 0 {
        didSet {
            if leadingInset != oldValue { needsLayout = true }
        }
    }

    init(frame: NSRect = .zero, settings: BellithSettings = .shared) {
        self.settings = settings
        super.init(frame: frame)
        wantsLayer = true

        backdropLayer.cornerRadius = 0
        backdropLayer.cornerCurve = .continuous
        backdropLayer.borderWidth = 0
        layer?.addSublayer(backdropLayer)

        innerStrokeLayer.cornerRadius = 0
        innerStrokeLayer.cornerCurve = .continuous
        innerStrokeLayer.borderWidth = 0
        innerStrokeLayer.backgroundColor = NSColor.clear.cgColor
        layer?.addSublayer(innerStrokeLayer)

        leftGlowLayer.startPoint = CGPoint(x: 0, y: 0.5)
        leftGlowLayer.endPoint = CGPoint(x: 1, y: 0.5)
        leftGlowLayer.cornerRadius = 0
        leftGlowLayer.cornerCurve = .continuous
        layer?.addSublayer(leftGlowLayer)

        layer?.addSublayer(bottomSeparatorLayer)

        folderIcon.image = NSImage(systemSymbolName: "folder.fill", accessibilityDescription: nil)
        folderIcon.imageScaling = .scaleProportionallyDown
        addSubview(folderIcon)

        hostBadge.isHidden = true
        addSubview(hostBadge)

        environmentBadge.isHidden = true
        addSubview(environmentBadge)

        worktreeBadge.isHidden = true
        addSubview(worktreeBadge)

        gitIcon.image = NSImage(systemSymbolName: "arrow.triangle.branch", accessibilityDescription: nil)
        gitIcon.imageScaling = .scaleProportionallyDown
        gitIcon.isHidden = true
        addSubview(gitIcon)

        configureMetadataLabel(gitLabel)
        gitLabel.isHidden = true
        addSubview(gitLabel)

        processIcon.image = NSImage(systemSymbolName: "gearshape.fill", accessibilityDescription: nil)
        processIcon.imageScaling = .scaleProportionallyDown
        processIcon.isHidden = true
        addSubview(processIcon)

        configureMetadataLabel(processLabel)
        processLabel.isHidden = true
        addSubview(processLabel)

        sizeLabel.font = BellithFont.mono(Metrics.sizeTextSize, weight: .medium)
        sizeLabel.alignment = .right
        sizeLabel.isEditable = false
        sizeLabel.isBezeled = false
        sizeLabel.drawsBackground = false
        sizeLabel.maximumNumberOfLines = 1
        addSubview(sizeLabel)

        // Centered title label (PR Popover v2 design): bold shell — accent workspace [pane pill]
        centerTitleLabel.alignment = .left
        centerTitleLabel.isEditable = false
        centerTitleLabel.isBezeled = false
        centerTitleLabel.drawsBackground = false
        centerTitleLabel.maximumNumberOfLines = 1
        centerTitleLabel.lineBreakMode = .byTruncatingTail
        addSubview(centerTitleLabel)

        panePill.isHidden = true
        addSubview(panePill)

        layer?.insertSublayer(backgroundGradient, at: 0)
        layer?.addSublayer(bottomLineLayer)

        refreshTheme()
    }

    func updateWorkspaceContext(shell: String?, name: String?, paneCount: Int) {
        let trimmedShell = (shell?.trimmingCharacters(in: .whitespacesAndNewlines)).flatMap { $0.isEmpty ? nil : $0 }
        let trimmedName = (name?.trimmingCharacters(in: .whitespacesAndNewlines)).flatMap { $0.isEmpty ? nil : $0 }
        let newShell = trimmedShell ?? currentSessionShell
        let newName = trimmedName ?? ""
        let newCount = max(0, paneCount)
        guard newShell != currentSessionShell
            || newName != currentWorkspaceName
            || newCount != currentPaneCount else { return }
        currentSessionShell = newShell
        currentWorkspaceName = newName
        currentPaneCount = newCount
        rebuildCenterTitle()
        rebuildBreadcrumbs()
        needsLayout = true
    }

    private var workspaceTint: NSColor {
        currentWorkspaceName.isEmpty
            ? Theme.accent
            : WorkspaceTint.accent(for: currentWorkspaceName)
    }

    private func rebuildCenterTitle() {
        // Always render the centered title now that the breadcrumbs are gone; an
        // empty workspace name simply falls back to "session" inside makeTitleString.
        centerTitleLabel.isHidden = false
        centerTitleLabel.attributedStringValue = Self.makeTitleString(
            shell: currentSessionShell,
            workspace: currentWorkspaceName,
            workspaceColor: workspaceTint
        )
        centerTitleLabel.invalidateIntrinsicContentSize()
        centerTitleLabel.sizeToFit()

        if currentPaneCount > 1 {
            panePill.text = "\(currentPaneCount) panes"
            panePill.isHidden = false
        } else {
            panePill.isHidden = true
        }
    }

    private static func makeTitleString(shell: String, workspace: String, workspaceColor: NSColor) -> NSAttributedString {
        let fontPrimary = BellithFont.mono(12, weight: .medium)
        let workspaceText = workspace.isEmpty ? "session" : workspace
        let result = NSMutableAttributedString()
        result.append(NSAttributedString(
            string: shell,
            attributes: [.font: fontPrimary, .foregroundColor: Theme.textPrimary]
        ))
        result.append(NSAttributedString(
            string: " — ",
            attributes: [.font: fontPrimary, .foregroundColor: Theme.textTertiary]
        ))
        result.append(NSAttributedString(
            string: workspaceText,
            attributes: [.font: fontPrimary, .foregroundColor: workspaceColor]
        ))
        return result
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    private func configureMetadataLabel(_ label: NSTextField) {
        label.font = BellithFont.mono(Metrics.metaTextSize, weight: .regular)
        label.isEditable = false
        label.isBezeled = false
        label.drawsBackground = false
        label.maximumNumberOfLines = 1
        label.lineBreakMode = .byTruncatingTail
    }

    func updatePath(_ path: String?) {
        let raw = path ?? "~"
        let home = NSHomeDirectory()
        var display = raw
        if display.hasPrefix(home) {
            display = "~" + display.dropFirst(home.count)
        }
        guard display != currentPath else { return }
        currentPath = display
        rebuildBreadcrumbs()
    }

    private var showsGitBranchInHeader: Bool {
        !settings.showStatusBar || !settings.showStatusBarGitBranch
    }

    func updateGitBranch(_ branch: String?) {
        let normalizedBranch = branch?.trimmingCharacters(in: .whitespacesAndNewlines)
        currentGitBranch = (normalizedBranch?.isEmpty == false) ? normalizedBranch : nil

        gitLabel.stringValue = currentGitBranch ?? ""
        let visible = currentGitBranch != nil && showsGitBranchInHeader
        gitIcon.isHidden = !visible
        gitLabel.isHidden = !visible
        rebuildBreadcrumbs()
        needsLayout = true
    }

    func updateProcess(_ presentation: ForegroundProcessPresentation?) {
        currentProcessPresentation = presentation
        let normalizedName = presentation?.text.trimmingCharacters(in: .whitespacesAndNewlines)
        let value = (normalizedName?.isEmpty == false) ? normalizedName : nil
        guard value != currentProcess else { return }

        currentProcess = value
        processLabel.stringValue = value ?? ""
        processIcon.image = NSImage(systemSymbolName: presentation?.iconName ?? "gearshape.fill", accessibilityDescription: nil)
        processIcon.contentTintColor = presentation?.style == .tool ? Theme.accent : Theme.textSecondary
        processLabel.textColor = presentation?.style == .tool ? Theme.textPrimary : Theme.textSecondary
        let visible = value != nil
        processIcon.isHidden = !visible
        processLabel.isHidden = !visible
        rebuildBreadcrumbs()
        needsLayout = true
    }

    func updateContext(_ context: TerminalContext?) {
        currentContext = context

        guard let context else {
            hostBadge.text = ""
            environmentBadge.text = ""
            worktreeBadge.text = ""
            worktreeBadge.iconName = nil
            needsLayout = true
            return
        }

        // PR Popover v2: hide the LOCAL host pill — only surface the host chip for
        // remote sessions, where the connection target is genuinely useful chrome.
        hostBadge.text = context.hostDisplayText.uppercased()
        hostBadge.iconName = context.isRemote ? "network" : "laptopcomputer"
        hostBadge.tone = tone(for: context)
        hostBadge.isHidden = !context.isRemote

        if let environment = context.environmentDisplayText {
            environmentBadge.text = environment
            environmentBadge.iconName = nil
            environmentBadge.tone = tone(for: context, preferEnvironment: true)
        } else {
            environmentBadge.text = ""
            environmentBadge.iconName = nil
        }

        needsLayout = true
    }

    func updateGitWorktree(_ worktreeName: String?) {
        let normalizedName = worktreeName?.trimmingCharacters(in: .whitespacesAndNewlines)
        let value = (normalizedName?.isEmpty == false) ? normalizedName : nil
        worktreeBadge.text = value ?? ""
        worktreeBadge.iconName = value == nil ? nil : "folder.badge.gearshape"
        worktreeBadge.tone = .neutral
        needsLayout = true
    }

    private func visiblePathParts() -> [String] {
        let components = currentPath.split(separator: "/", omittingEmptySubsequences: true)
        let allParts: [String]
        if currentPath.hasPrefix("~") {
            if components.count <= 1 {
                allParts = ["~"]
            } else {
                allParts = ["~"] + components.dropFirst().map(String.init)
            }
        } else {
            allParts = ["/"] + components.map(String.init)
        }

        guard allParts.count > 4 else { return allParts }

        let trailingPartCount = ((currentGitBranch != nil && showsGitBranchInHeader) || currentProcess != nil) ? 2 : 3
        let suffixParts = Array(allParts.suffix(trailingPartCount))
        return [allParts[0], "…"] + suffixParts
    }

    private func rebuildBreadcrumbs() {
        breadcrumbViews.forEach { $0.removeFromSuperview() }
        breadcrumbViews.removeAll()

        if hidesBreadcrumbsForTitle {
            folderIcon.isHidden = true
            applyBreadcrumbColors()
            needsLayout = true
            return
        }
        folderIcon.isHidden = false

        let parts = visiblePathParts()
        for (index, part) in parts.enumerated() {
            let isLast = index == parts.count - 1

            if index > 0 {
                let chevron = NSImageView()
                chevron.image = NSImage(systemSymbolName: "chevron.right", accessibilityDescription: nil)
                chevron.imageScaling = .scaleProportionallyDown
                addSubview(chevron)
                breadcrumbViews.append(chevron)
            }

            let label = NSTextField(labelWithString: part)
            label.font = BellithFont.mono(Metrics.textSize, weight: isLast ? .semibold : .regular)
            label.isEditable = false
            label.isBezeled = false
            label.drawsBackground = false
            label.maximumNumberOfLines = 1
            label.lineBreakMode = .byTruncatingMiddle
            addSubview(label)
            breadcrumbViews.append(label)
        }

        applyBreadcrumbColors()
        needsLayout = true
    }

    private func applyBreadcrumbColors() {
        for (index, view) in breadcrumbViews.enumerated() {
            if let chevron = view as? NSImageView {
                chevron.contentTintColor = Theme.textTertiary.withAlphaComponent(0.72)
            } else if let label = view as? NSTextField {
                let isLast = index == breadcrumbViews.count - 1
                label.textColor = isLast ? Theme.textPrimary : Theme.textSecondary
            }
        }
    }

    private func updateSegmentTracking() {
        segmentTrackingAreas.forEach { removeTrackingArea($0) }
        segmentTrackingAreas.removeAll()

        for view in breadcrumbViews {
            guard view is NSTextField else { continue }
            let area = NSTrackingArea(
                rect: view.frame,
                options: [.mouseEnteredAndExited, .activeAlways],
                owner: self,
                userInfo: ["view": view]
            )
            addTrackingArea(area)
            segmentTrackingAreas.append(area)
        }
    }

    override func layout() {
        super.layout()

        let h = bounds.height
        let iconSize = Metrics.iconSize
        let chevronSize = Metrics.chevronSize
        let labelHeight = Metrics.labelHeight
        let gap: CGFloat = 5
        let interGroupGap: CGFloat = 14

        backdropLayer.frame = .zero
        innerStrokeLayer.frame = .zero
        leftGlowLayer.frame = .zero
        bottomSeparatorLayer.frame = NSRect(x: leadingInset, y: 0, width: max(0, bounds.width - leadingInset), height: 1)

        var trailingX = bounds.width - 6

        let sizeWidth: CGFloat = sizeLabel.stringValue.isEmpty ? 0 : max(48, sizeLabel.attributedStringValue.size().width + 2)
        if sizeWidth > 0 {
            sizeLabel.frame = NSRect(x: trailingX - sizeWidth, y: floor((h - labelHeight) / 2), width: sizeWidth, height: labelHeight)
            trailingX -= sizeWidth + interGroupGap
        } else {
            sizeLabel.frame = .zero
        }

        if currentProcess != nil {
            let processLabelWidth = min(120, processLabel.attributedStringValue.size().width + 2)
            let processGroupWidth = iconSize + gap + processLabelWidth
            let processX = max(leadingInset + 32, trailingX - processGroupWidth)
            processIcon.frame = NSRect(x: processX, y: floor((h - iconSize) / 2), width: iconSize, height: iconSize)
            processLabel.frame = NSRect(x: processX + iconSize + gap, y: floor((h - labelHeight) / 2), width: processLabelWidth, height: labelHeight)
            processIcon.isHidden = false
            processLabel.isHidden = false
            trailingX = processX - interGroupGap
        } else {
            processIcon.frame = .zero
            processLabel.frame = .zero
            processIcon.isHidden = true
            processLabel.isHidden = true
        }

        if currentGitBranch != nil && showsGitBranchInHeader {
            let branchLabelWidth = min(140, gitLabel.attributedStringValue.size().width + 2)
            let branchGroupWidth = iconSize + gap + branchLabelWidth
            let branchX = max(leadingInset + 32, trailingX - branchGroupWidth)
            gitIcon.frame = NSRect(x: branchX, y: floor((h - iconSize) / 2), width: iconSize, height: iconSize)
            gitLabel.frame = NSRect(x: branchX + iconSize + gap, y: floor((h - labelHeight) / 2), width: branchLabelWidth, height: labelHeight)
            gitIcon.isHidden = false
            gitLabel.isHidden = false
            trailingX = branchX - interGroupGap
        } else {
            gitIcon.frame = .zero
            gitLabel.frame = .zero
            gitIcon.isHidden = true
            gitLabel.isHidden = true
        }

        let maxContentX = max(leadingInset + 20, trailingX)

        var x: CGFloat = leadingInset + 6
        if !hostBadge.isHidden {
            let size = hostBadge.intrinsicContentSize
            hostBadge.frame = NSRect(x: x, y: floor((h - size.height) / 2), width: size.width, height: size.height)
            x += size.width + 8
        } else {
            hostBadge.frame = .zero
        }

        if !environmentBadge.isHidden {
            let size = environmentBadge.intrinsicContentSize
            environmentBadge.frame = NSRect(x: x, y: floor((h - size.height) / 2), width: size.width, height: size.height)
            x += size.width + 10
        } else {
            environmentBadge.frame = .zero
        }

        if !worktreeBadge.isHidden {
            let size = worktreeBadge.intrinsicContentSize
            worktreeBadge.frame = NSRect(x: x, y: floor((h - size.height) / 2), width: size.width, height: size.height)
            x += size.width + 10
        } else {
            worktreeBadge.frame = .zero
        }

        if !folderIcon.isHidden {
            folderIcon.frame = NSRect(x: x, y: floor((h - iconSize) / 2), width: iconSize, height: iconSize)
            x += iconSize + gap + 1
        } else {
            folderIcon.frame = .zero
        }

        for view in breadcrumbViews {
            if let imageView = view as? NSImageView {
                imageView.frame = NSRect(x: x, y: floor((h - chevronSize) / 2), width: chevronSize, height: chevronSize)
                x += chevronSize + gap
            } else if let label = view as? NSTextField {
                let preferredWidth = label.attributedStringValue.size().width + 4
                let textWidth = min(max(0, maxContentX - x), preferredWidth)
                label.frame = NSRect(x: x, y: floor((h - labelHeight) / 2), width: textWidth, height: labelHeight)
                x += textWidth + gap
            }
        }

        // Background gradient + bottom hairline (PR Popover v2 chrome).
        backgroundGradient.frame = bounds
        bottomLineLayer.frame = NSRect(x: leadingInset, y: 0, width: max(0, bounds.width - leadingInset), height: 1)

        // Centered title overlay (replaces the breadcrumb path when a workspace name is set).
        if hidesBreadcrumbsForTitle {
            let leftEdge = max(leadingInset + 6, x + 4)
            let rightEdge = max(leftEdge, trailingX)
            let availableWidth = max(0, rightEdge - leftEdge - 24)

            let titleIntrinsic = ceil(centerTitleLabel.attributedStringValue.size().width) + 4
            let pillSize = panePill.isHidden ? .zero : panePill.intrinsicContentSize
            let pillGap: CGFloat = panePill.isHidden ? 0 : 8
            let groupIdeal = max(0, titleIntrinsic) + pillGap + pillSize.width
            let groupWidth = min(groupIdeal > 0 ? groupIdeal : 200, availableWidth)
            // Allocate width: pill gets its intrinsic, title takes the rest.
            let pillWidth = min(pillSize.width, max(0, groupWidth - pillGap - 40))
            let titleWidth = max(0, groupWidth - pillGap - pillWidth)

            var centerX = floor((bounds.width - groupWidth) / 2)
            if centerX < leftEdge { centerX = leftEdge }
            if centerX + groupWidth > rightEdge { centerX = max(leftEdge, rightEdge - groupWidth) }

            let titleY = floor((h - labelHeight) / 2)
            centerTitleLabel.frame = NSRect(
                x: max(0, centerX),
                y: titleY,
                width: titleWidth,
                height: labelHeight
            )
            if !panePill.isHidden {
                let pillY = floor((h - pillSize.height) / 2)
                panePill.frame = NSRect(
                    x: centerTitleLabel.frame.maxX + pillGap,
                    y: pillY,
                    width: pillWidth,
                    height: pillSize.height
                )
            } else {
                panePill.frame = .zero
            }
        } else {
            centerTitleLabel.frame = .zero
            panePill.frame = .zero
        }

        updateSegmentTracking()
    }

    /// Show the columns × rows readout briefly during a resize, then auto-hide.
    /// The status bar carries the persistent size; the title bar only flashes
    /// it so the user gets feedback while dragging the window edge.
    private var sizeAutoHideWorkItem: DispatchWorkItem?

    func updateSize(cols: Int, rows: Int) {
        sizeLabel.stringValue = "\(cols)×\(rows)"
        needsLayout = true
        sizeAutoHideWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.clearSize() }
        sizeAutoHideWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2, execute: work)
    }

    func clearSize() {
        sizeAutoHideWorkItem?.cancel()
        sizeAutoHideWorkItem = nil
        sizeLabel.stringValue = ""
        needsLayout = true
    }

    override func mouseEntered(with event: NSEvent) {
        guard let info = event.trackingArea?.userInfo,
              let view = info["view"] as? NSTextField else { return }
        hoveredView = view
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = Theme.animFast
            view.animator().textColor = Theme.textPrimary
        }
    }

    override func mouseExited(with event: NSEvent) {
        guard let info = event.trackingArea?.userInfo,
              let view = info["view"] as? NSTextField else { return }
        if hoveredView === view { hoveredView = nil }
        let isLast = view === breadcrumbViews.last
        let color = isLast ? Theme.textPrimary : Theme.textSecondary
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = Theme.animFast
            view.animator().textColor = color
        }
    }

    func refreshTheme() {
        backdropLayer.backgroundColor = NSColor.clear.cgColor
        backdropLayer.borderColor = NSColor.clear.cgColor
        innerStrokeLayer.borderColor = NSColor.clear.cgColor
        leftGlowLayer.colors = [NSColor.clear.cgColor, NSColor.clear.cgColor, NSColor.clear.cgColor]
        leftGlowLayer.locations = [0, 1]
        bottomSeparatorLayer.backgroundColor = NSColor.clear.cgColor

        // Subtle top→bottom gradient + bottom hairline (PR Popover v2 chrome).
        let isLight = Theme.colors.isLight
        let topColor = isLight
            ? NSColor.white.withAlphaComponent(0.18).cgColor
            : NSColor(white: 1.0, alpha: 0.04).cgColor
        let bottomColor = isLight
            ? NSColor.white.withAlphaComponent(0.04).cgColor
            : NSColor(white: 0.0, alpha: 0.18).cgColor
        backgroundGradient.colors = [topColor, bottomColor]
        backgroundGradient.locations = [0, 1]
        backgroundGradient.startPoint = CGPoint(x: 0.5, y: 1)
        backgroundGradient.endPoint = CGPoint(x: 0.5, y: 0)
        bottomLineLayer.backgroundColor = Theme.chromeHairline.withAlphaComponent(isLight ? 0.85 : 0.7).cgColor

        folderIcon.contentTintColor = Theme.textSecondary
        hostBadge.refreshTheme()
        environmentBadge.refreshTheme()
        worktreeBadge.refreshTheme()
        gitIcon.contentTintColor = Theme.success
        gitLabel.textColor = Theme.textSecondary
        sizeLabel.textColor = Theme.textSecondary
        updateGitBranch(currentGitBranch)
        updateProcess(currentProcessPresentation)
        rebuildCenterTitle()
        panePill.refreshTheme()
        rebuildBreadcrumbs()
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

/// Bordered chip rendering the active tab's pane count in the centered title.
/// Mirrors the `.title .mux` chip from the PR Popover v2 design: small mono font,
/// 1px hairline border, 3px corner radius.
private final class PaneCountPillView: NSView {
    private let label = NSTextField(labelWithString: "")

    var text: String = "" {
        didSet {
            label.stringValue = text
            invalidateIntrinsicContentSize()
            needsLayout = true
        }
    }

    override init(frame: NSRect = .zero) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.cornerRadius = 3
        layer?.cornerCurve = .continuous
        layer?.borderWidth = 1

        label.font = BellithFont.mono(10.5, weight: .regular)
        label.alignment = .center
        label.isEditable = false
        label.isBezeled = false
        label.drawsBackground = false
        label.maximumNumberOfLines = 1
        label.lineBreakMode = .byClipping
        addSubview(label)

        refreshTheme()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override var intrinsicContentSize: NSSize {
        let textWidth = ceil(label.attributedStringValue.size().width)
        return NSSize(width: textWidth + 12, height: 16)
    }

    override func layout() {
        super.layout()
        label.frame = NSRect(
            x: 0,
            y: floor((bounds.height - 14) / 2),
            width: bounds.width,
            height: 14
        )
    }

    func refreshTheme() {
        layer?.borderColor = Theme.chromeHairline.withAlphaComponent(0.7).cgColor
        layer?.backgroundColor = NSColor.clear.cgColor
        label.textColor = Theme.textTertiary
    }
}
