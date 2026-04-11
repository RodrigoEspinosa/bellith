import AppKit

/// Hosts a terminal surface plus any restored transcript content that should
/// read like scrollback sitting above the active shell.
final class TerminalSessionView: NSView, TerminalRestoredHistoryPresenting {
    private enum Metrics {
        static let minTranscriptHeight: CGFloat = 88
        static let maxTranscriptHeightRatio: CGFloat = 0.55
        static let minTerminalHeight: CGFloat = 120
        static let headerHeight: CGFloat = 20
        static let contentInset: CGFloat = 12
        static let bottomInset: CGFloat = 8
    }

    let surface: TerminalSurfaceView

    private let transcriptContainer = NSView()
    private let transcriptScrollView = NSScrollView()
    private let transcriptTextView = NSTextView()
    private let transcriptCaptionLabel = NSTextField(labelWithString: "previous session")
    private let transcriptDismissButton = NSButton()
    private let transcriptDivider = CALayer()

    init(surface: TerminalSurfaceView) {
        self.surface = surface
        super.init(frame: .zero)

        wantsLayer = true
        surface.restoredHistoryPresenter = self
        configureTranscriptView()

        addSubview(transcriptContainer)
        addSubview(surface)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()

        let transcriptHeight = currentTranscriptHeight()
        if transcriptHeight > 0 {
            transcriptContainer.isHidden = false
            transcriptContainer.frame = NSRect(
                x: 0,
                y: bounds.height - transcriptHeight,
                width: bounds.width,
                height: transcriptHeight
            )
            layoutTranscriptSubviews()
            surface.frame = NSRect(
                x: 0,
                y: 0,
                width: bounds.width,
                height: max(0, bounds.height - transcriptHeight)
            )
        } else {
            transcriptContainer.isHidden = true
            surface.frame = bounds
        }
    }

    func showRestoredHistory(text: String) {
        transcriptTextView.string = text
        needsLayout = true
        layoutSubtreeIfNeeded()
        scrollTranscriptToBottom()
    }

    func hideRestoredHistory() {
        transcriptTextView.string = ""
        transcriptContainer.isHidden = true
        needsLayout = true
    }

    private func configureTranscriptView() {
        transcriptContainer.wantsLayer = true
        transcriptContainer.layer?.backgroundColor = Theme.base.cgColor
        transcriptContainer.layer?.addSublayer(transcriptDivider)
        transcriptContainer.isHidden = true

        transcriptCaptionLabel.font = BellithFont.mono(10, weight: .regular)
        transcriptCaptionLabel.textColor = Theme.textMuted

        transcriptDismissButton.title = ""
        transcriptDismissButton.bezelStyle = .inline
        transcriptDismissButton.image = NSImage(
            systemSymbolName: "xmark",
            accessibilityDescription: "Hide restored transcript"
        )
        transcriptDismissButton.imagePosition = .imageOnly
        transcriptDismissButton.contentTintColor = Theme.textSecondary
        transcriptDismissButton.target = self
        transcriptDismissButton.action = #selector(handleTranscriptDismiss)

        transcriptScrollView.drawsBackground = false
        transcriptScrollView.borderType = .noBorder
        transcriptScrollView.hasVerticalScroller = true
        transcriptScrollView.autohidesScrollers = true

        transcriptTextView.isEditable = false
        transcriptTextView.isSelectable = true
        transcriptTextView.drawsBackground = false
        transcriptTextView.textContainerInset = NSSize(width: 0, height: 2)
        transcriptTextView.font = BellithFont.mono(12, weight: .regular)
        transcriptTextView.textColor = Theme.textPrimary
        transcriptTextView.isVerticallyResizable = true
        transcriptTextView.isHorizontallyResizable = false
        transcriptTextView.autoresizingMask = .width
        transcriptTextView.textContainer?.widthTracksTextView = true
        transcriptTextView.textContainer?.containerSize = NSSize(
            width: 0,
            height: CGFloat.greatestFiniteMagnitude
        )

        transcriptScrollView.documentView = transcriptTextView
        transcriptContainer.addSubview(transcriptCaptionLabel)
        transcriptContainer.addSubview(transcriptDismissButton)
        transcriptContainer.addSubview(transcriptScrollView)
        transcriptDivider.backgroundColor = Theme.borderSubtle.cgColor
    }

    private func currentTranscriptHeight() -> CGFloat {
        guard !transcriptTextView.string.isEmpty, bounds.height > Metrics.minTerminalHeight else {
            return 0
        }

        let maxHeight = max(
            Metrics.minTranscriptHeight,
            min(bounds.height - Metrics.minTerminalHeight, bounds.height * Metrics.maxTranscriptHeightRatio)
        )
        guard maxHeight > 0 else { return 0 }

        let textWidth = max(120, bounds.width - (Metrics.contentInset * 2))
        transcriptTextView.frame.size.width = textWidth
        transcriptTextView.textContainer?.containerSize = NSSize(
            width: textWidth,
            height: CGFloat.greatestFiniteMagnitude
        )

        if let textContainer = transcriptTextView.textContainer,
           let layoutManager = transcriptTextView.layoutManager {
            layoutManager.ensureLayout(for: textContainer)
            let textHeight = layoutManager.usedRect(for: textContainer).height
            return min(maxHeight, max(Metrics.minTranscriptHeight, textHeight + Metrics.headerHeight + 18))
        }

        return maxHeight
    }

    private func layoutTranscriptSubviews() {
        transcriptDivider.frame = NSRect(
            x: 0,
            y: 0,
            width: transcriptContainer.bounds.width,
            height: 1
        )

        let innerWidth = transcriptContainer.bounds.width - (Metrics.contentInset * 2)
        transcriptCaptionLabel.frame = NSRect(
            x: Metrics.contentInset,
            y: transcriptContainer.bounds.height - Metrics.headerHeight + 2,
            width: max(0, innerWidth - 24),
            height: 14
        )
        transcriptDismissButton.frame = NSRect(
            x: transcriptContainer.bounds.width - 22,
            y: transcriptContainer.bounds.height - Metrics.headerHeight,
            width: 16,
            height: 16
        )
        transcriptScrollView.frame = NSRect(
            x: Metrics.contentInset,
            y: Metrics.bottomInset,
            width: innerWidth,
            height: transcriptContainer.bounds.height - Metrics.headerHeight - Metrics.bottomInset - 2
        )
    }

    private func scrollTranscriptToBottom() {
        guard let documentView = transcriptScrollView.documentView else { return }
        transcriptScrollView.contentView.scroll(to: NSPoint(
            x: 0,
            y: max(0, documentView.bounds.height - transcriptScrollView.contentView.bounds.height)
        ))
        transcriptScrollView.reflectScrolledClipView(transcriptScrollView.contentView)
    }

    @objc private func handleTranscriptDismiss() {
        hideRestoredHistory()
    }
}
