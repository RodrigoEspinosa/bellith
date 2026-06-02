import AppKit
import GhosttyKit
import os

/// NSView subclass that hosts a single ghostty terminal surface.
/// Handles Metal rendering internally via libghostty — we just forward events.
final class TerminalSurfaceView: NSView, NSTextInputClient {
    override var mouseDownCanMoveWindow: Bool { false }
    private(set) var surface: ghostty_surface_t?
    /// Whether the surface was successfully created and is ready for use.
    var isReady: Bool { surface != nil }
    private weak var terminalApp: TerminalApp?
    private var markedText = NSMutableAttributedString()
    private var keyTextAccumulator: [String]?
    private var eventMonitor: Any?
    private var focused = false
    private var currentModifierFlags: NSEvent.ModifierFlags = []
    private let dropIndicatorLayer = CALayer()
    private let temporaryDropDirectoryURL = TerminalSurfaceView.temporaryDropDirectoryURL()
    private var minimapView: ScrollbackMinimapView?
    private var lastScrollbarTotal: Int = 0
    private var lastScrollbarOffset: Int = 0
    private var lastScrollbarLen: Int = 0
    private var settingsObserver: NSObjectProtocol?

    /// Called when the shell process exits or the surface requests close.
    var onClose: ((Bool) -> Void)?

    /// Current working directory of this surface, set via OSC 7.
    var currentCwd: String?
    var terminalContext: TerminalContext = .local
    var detectedContext: TerminalContext?
    var lastForegroundPresentation: ForegroundProcessPresentation?
    var displayContext: TerminalContext { detectedContext ?? terminalContext }

    /// Called after text is inserted, for broadcast mode.
    var onTextInserted: ((String, TerminalSurfaceView) -> Void)?
    var onSizeChanged: ((Int, Int) -> Void)?
    var onFocus: ((TerminalSurfaceView) -> Void)?
    var onKeyDownIntercept: ((NSEvent, TerminalSurfaceView) -> Bool)?
    var onTextIntercept: ((String, TerminalSurfaceView) -> Bool)?
    var shouldReportMousePosition: (() -> Bool)?

    init(app: TerminalApp, baseConfig: ghostty_surface_config_s? = nil) {
        self.terminalApp = app
        super.init(frame: NSRect(x: 0, y: 0, width: 800, height: 600))

        wantsLayer = true
        updateLayerOpacity()
        registerForDraggedTypes([.fileURL, .png, .tiff])

        dropIndicatorLayer.borderWidth = 2
        dropIndicatorLayer.cornerRadius = 10
        dropIndicatorLayer.borderColor = Theme.accent.withAlphaComponent(0.85).cgColor
        dropIndicatorLayer.backgroundColor = Theme.accent.withAlphaComponent(0.08).cgColor
        dropIndicatorLayer.isHidden = true
        layer?.addSublayer(dropIndicatorLayer)

        guard let ghosttyApp = app.app else { return }

        var config = baseConfig ?? ghostty_surface_config_new()
        config.userdata = Unmanaged.passUnretained(self).toOpaque()
        config.platform_tag = GHOSTTY_PLATFORM_MACOS
        config.platform = ghostty_platform_u(
            macos: ghostty_platform_macos_s(
                nsview: Unmanaged.passUnretained(self).toOpaque()
            )
        )
        config.scale_factor = Double(NSScreen.main?.backingScaleFactor ?? 2.0)

        surface = ghostty_surface_new(ghosttyApp, &config)
        if surface == nil {
            Logger.surface.error("Failed to create ghostty surface")
            return
        }

        applyMinimapPreference()
        settingsObserver = NotificationCenter.default.addObserver(
            forName: BellithSettings.didChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            self?.updateLayerOpacity()
            self?.applyMinimapPreference()
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    deinit {
        Self.cleanupTemporaryDropDirectory(at: temporaryDropDirectoryURL)
        if let eventMonitor { NSEvent.removeMonitor(eventMonitor) }
        if let settingsObserver { NotificationCenter.default.removeObserver(settingsObserver) }
        if let surface { ghostty_surface_free(surface) }
    }

    // MARK: - View Lifecycle

    /// Read all visible + scrollback text from this surface.
    func readScreenText() -> String? {
        guard let surface else { return nil }
        let size = ghostty_surface_size(surface)
        guard size.columns > 0, size.rows > 0 else { return nil }

        // Select from top of scrollback (screen row 0) to bottom-right of viewport
        let sel = ghostty_selection_s(
            top_left: ghostty_point_s(
                tag: GHOSTTY_POINT_SCREEN,
                coord: GHOSTTY_POINT_COORD_TOP_LEFT,
                x: 0,
                y: 0
            ),
            bottom_right: ghostty_point_s(
                tag: GHOSTTY_POINT_ACTIVE,
                coord: GHOSTTY_POINT_COORD_BOTTOM_RIGHT,
                x: UInt32(size.columns - 1),
                y: UInt32(size.rows - 1)
            ),
            rectangle: false
        )

        var text = ghostty_text_s()
        guard ghostty_surface_read_text(surface, sel, &text) else { return nil }
        defer { ghostty_surface_free_text(surface, &text) }
        guard text.text_len > 0 else { return nil }

        var result = String(cString: text.text)

        // Trim trailing empty lines
        while result.hasSuffix("\n\n") {
            result = String(result.dropLast())
        }
        guard !result.isEmpty else { return nil }

        // Cap at ~512KB per surface to keep UserDefaults reasonable
        let maxLen = 512 * 1024
        if result.utf8.count > maxLen {
            return String(result.suffix(maxLen))
        }
        return result
    }

    override var acceptsFirstResponder: Bool { true }

    override func becomeFirstResponder() -> Bool {
        let becameFirstResponder = super.becomeFirstResponder()
        guard becameFirstResponder else { return false }
        setTerminalFocused(true)
        installKeyUpMonitorIfNeeded()
        onFocus?(self)
        return true
    }

    override func resignFirstResponder() -> Bool {
        let resignedFirstResponder = super.resignFirstResponder()
        guard resignedFirstResponder else { return false }
        setTerminalFocused(false)
        removeKeyUpMonitor()
        return true
    }

    func setTerminalFocused(_ isFocused: Bool) {
        guard focused != isFocused else { return }
        focused = isFocused
        if let surface { ghostty_surface_set_focus(surface, isFocused) }
    }

    private func installKeyUpMonitorIfNeeded() {
        guard eventMonitor == nil else { return }
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyUp]) { [weak self] event in
            self?.localKeyUp(event) ?? event
        }
    }

    private func removeKeyUpMonitor() {
        guard let eventMonitor else { return }
        NSEvent.removeMonitor(eventMonitor)
        self.eventMonitor = nil
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil {
            updateContentScale()
        }
    }

    override var wantsUpdateLayer: Bool { true }

    private func updateLayerOpacity() {
        let opacity = min(max(BellithSettings.shared.backgroundOpacity, 0.0), 1.0)
        layer?.isOpaque = opacity >= 0.999
        layer?.backgroundColor = NSColor.clear.cgColor
    }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        dropIndicatorLayer.frame = bounds.insetBy(dx: 6, dy: 6)
        CATransaction.commit()
        layoutMinimap()
    }

    // MARK: - Scrollback Minimap

    private func applyMinimapPreference() {
        let enabled = BellithSettings.shared.scrollbackMinimapEnabled
        if enabled {
            if minimapView == nil {
                let minimap = ScrollbackMinimapView(frame: .zero)
                minimap.onScrollToRow = { [weak self] row in
                    self?.scrollToRow(row)
                }
                addSubview(minimap)
                minimapView = minimap
                minimap.updateScrollbar(
                    total: lastScrollbarTotal,
                    offset: lastScrollbarOffset,
                    len: lastScrollbarLen
                )
            }
        } else {
            minimapView?.removeFromSuperview()
            minimapView = nil
        }
        layoutMinimap()
    }

    private func layoutMinimap() {
        guard let minimap = minimapView else { return }
        let width = ScrollbackMinimapView.defaultWidth
        let topInset: CGFloat = 2
        let bottomInset: CGFloat = 2
        minimap.frame = NSRect(
            x: bounds.width - width,
            y: bottomInset,
            width: width,
            height: max(0, bounds.height - topInset - bottomInset)
        )
    }

    func updateScrollbarState(total: Int, offset: Int, len: Int) {
        lastScrollbarTotal = total
        lastScrollbarOffset = offset
        lastScrollbarLen = len
        minimapView?.updateScrollbar(total: total, offset: offset, len: len)
    }

    func recordCommandMark(exitCode: Int16) {
        guard let minimap = minimapView else { return }
        // Use the bottom-of-viewport row as the approximate prompt/command line.
        let markRow = lastScrollbarOffset + max(0, lastScrollbarLen - 1)
        minimap.appendMark(row: markRow, kind: exitCode == 0 ? .prompt : .error)
    }

    func resetMinimapMarks() {
        minimapView?.clearMarks()
    }

    func updateMinimapSearchSelection() {
        guard let minimap = minimapView else { return }
        // Search automatically scrolls the selected hit into view, so the
        // current viewport centre is a good proxy for the hit row.
        if lastScrollbarLen > 0 && lastScrollbarTotal > 0 {
            let row = lastScrollbarOffset + lastScrollbarLen / 2
            minimap.setSearchHit(row: row)
        } else {
            minimap.setSearchHit(row: nil)
        }
    }

    func clearMinimapSearchSelection() {
        minimapView?.setSearchHit(row: nil)
    }

    private func scrollToRow(_ row: Int) {
        guard let surface else { return }
        let action = "scroll_to_row:\(row)"
        action.withCString { ptr in
            _ = ghostty_surface_binding_action(surface, ptr, UInt(action.utf8.count))
        }
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        guard let surface else { return }
        // Ghostty expects backing pixel sizes (retina-scaled), not points
        let scaled = convertToBacking(newSize)
        ghostty_surface_set_size(surface, UInt32(scaled.width), UInt32(scaled.height))
        reportGridSize(for: newSize)
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        updateContentScale()

        // Update layer contentsScale to match the window
        if let window {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            layer?.contentsScale = window.backingScaleFactor
            CATransaction.commit()
        }

        // Re-send the size in backing pixels
        if let surface {
            let scaled = convertToBacking(frame.size)
            ghostty_surface_set_size(surface, UInt32(scaled.width), UInt32(scaled.height))
        }
        reportGridSize(for: frame.size)
    }

    private func updateContentScale() {
        guard let surface else { return }
        let scale = Double(window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2.0)
        ghostty_surface_set_content_scale(surface, scale, scale)
    }

    private func reportGridSize(for size: NSSize) {
        let cellWidth: CGFloat = 9.0
        let cellHeight: CGFloat = 19.0
        let cols = max(1, Int(floor(size.width / cellWidth)))
        let rows = max(1, Int(floor(size.height / cellHeight)))
        onSizeChanged?(cols, rows)
    }

    func refreshReportedSize() {
        reportGridSize(for: bounds.size)
    }

    override func updateLayer() {
        guard let surface else { return }
        ghostty_surface_draw(surface)
    }

    override func updateTrackingAreas() {
        trackingAreas.forEach { removeTrackingArea($0) }
        addTrackingArea(NSTrackingArea(
            rect: bounds,
            options: [
                .mouseEnteredAndExited,
                .mouseMoved,
                .inVisibleRect,
                .activeAlways,
            ],
            owner: self,
            userInfo: nil
        ))
    }

    // MARK: - Drag and Drop

    override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
        updateDropIndicator(isVisible: acceptsDraggedContent(from: sender.draggingPasteboard))
        return dropIndicatorLayer.isHidden ? [] : .copy
    }

    override func draggingUpdated(_ sender: any NSDraggingInfo) -> NSDragOperation {
        updateDropIndicator(isVisible: acceptsDraggedContent(from: sender.draggingPasteboard))
        return dropIndicatorLayer.isHidden ? [] : .copy
    }

    override func draggingExited(_ sender: (any NSDraggingInfo)?) {
        updateDropIndicator(isVisible: false)
    }

    override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        defer { updateDropIndicator(isVisible: false) }
        guard let text = droppedInsertText(from: sender.draggingPasteboard) else { return false }
        window?.makeFirstResponder(self)
        sendTextToSurface(text)
        return true
    }

    override func concludeDragOperation(_ sender: (any NSDraggingInfo)?) {
        updateDropIndicator(isVisible: false)
    }

    private func updateDropIndicator(isVisible: Bool) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        dropIndicatorLayer.isHidden = !isVisible
        CATransaction.commit()
    }

    private func acceptsDraggedContent(from pasteboard: NSPasteboard) -> Bool {
        !droppedFileURLs(from: pasteboard).isEmpty || pasteboard.data(forType: .png) != nil || pasteboard.data(forType: .tiff) != nil
    }

    private func droppedInsertText(from pasteboard: NSPasteboard) -> String? {
        let fileURLs = droppedFileURLs(from: pasteboard)
        if !fileURLs.isEmpty {
            return Self.shellInsertText(for: fileURLs)
        }

        if let imageURL = writeTemporaryImage(from: pasteboard) {
            return Self.shellInsertText(for: [imageURL])
        }

        return nil
    }

    private func droppedFileURLs(from pasteboard: NSPasteboard) -> [URL] {
        let options: [NSPasteboard.ReadingOptionKey: Any] = [
            .urlReadingFileURLsOnly: true,
        ]
        guard let items = pasteboard.readObjects(forClasses: [NSURL.self], options: options) as? [NSURL] else {
            return []
        }

        return items.compactMap { $0 as URL }
    }

    private func writeTemporaryImage(from pasteboard: NSPasteboard) -> URL? {
        if let pngData = pasteboard.data(forType: .png) {
            return writeTemporaryImageData(pngData, fileExtension: "png")
        }

        guard let tiffData = pasteboard.data(forType: .tiff),
              let rep = NSBitmapImageRep(data: tiffData),
              let pngData = rep.representation(using: .png, properties: [:]) else {
            return nil
        }

        return writeTemporaryImageData(pngData, fileExtension: "png")
    }

    private func writeTemporaryImageData(_ data: Data, fileExtension: String) -> URL? {
        do {
            try FileManager.default.createDirectory(
                at: temporaryDropDirectoryURL,
                withIntermediateDirectories: true,
                attributes: nil
            )
            let fileURL = Self.temporaryDropImageURL(in: temporaryDropDirectoryURL, fileExtension: fileExtension)
            try data.write(to: fileURL, options: .atomic)
            return fileURL
        } catch {
            Logger.surface.error("Failed to materialize dropped image: \(error.localizedDescription)")
            return nil
        }
    }

    func insertCommandText(_ text: String) {
        sendTextToSurface(text)
    }

    private func sendTextToSurface(_ text: String) {
        guard let surface else { return }
        if shouldOfferTextIntercept(text),
           onTextIntercept?(text, self) == true {
            return
        }
        text.withCString { ptr in
            ghostty_surface_text(surface, ptr, UInt(text.utf8.count))
        }
        onTextInserted?(text, self)
    }

    private static func shellInsertText(for urls: [URL]) -> String {
        urls.map { shellQuoted($0.path) }.joined(separator: " ") + " "
    }

    private static func shellQuoted(_ path: String) -> String {
        let escaped = path.replacingOccurrences(of: "'", with: "'\\''")
        return "'\(escaped)'"
    }

    static func temporaryDropDirectoryURL(baseDirectory: URL = FileManager.default.temporaryDirectory) -> URL {
        baseDirectory
            .appendingPathComponent("BellithDrops", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
    }

    static func temporaryDropImageURL(in directory: URL, fileExtension: String) -> URL {
        directory.appendingPathComponent("image-\(UUID().uuidString).\(fileExtension)")
    }

    static func cleanupTemporaryDropDirectory(at directory: URL, fileManager: FileManager = .default) {
        guard fileManager.fileExists(atPath: directory.path) else { return }
        try? fileManager.removeItem(at: directory)
    }

    // MARK: - Keyboard

    override func keyDown(with event: NSEvent) {
        currentModifierFlags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if onKeyDownIntercept?(event, self) == true {
            return
        }

        guard let surface else {
            interpretKeyEvents([event])
            return
        }

        // Translate mods for configs like option-as-alt
        let translationModsGhostty = InputHelpers.eventModifierFlags(
            mods: ghostty_surface_key_translation_mods(
                surface,
                InputHelpers.ghosttyMods(event.modifierFlags)
            )
        )

        // Rebuild modifier flags with translated values while preserving hidden bits
        var translationMods = event.modifierFlags
        for flag in [NSEvent.ModifierFlags.shift, .control, .option, .command] {
            if translationModsGhostty.contains(flag) {
                translationMods.insert(flag)
            } else {
                translationMods.remove(flag)
            }
        }

        // If mods changed, construct a new NSEvent. If equal, MUST reuse the original
        // (required for Korean input and other IME — AppKit uses object identity).
        let translationEvent: NSEvent
        if translationMods == event.modifierFlags {
            translationEvent = event
        } else {
            translationEvent = NSEvent.keyEvent(
                with: event.type,
                location: event.locationInWindow,
                modifierFlags: translationMods,
                timestamp: event.timestamp,
                windowNumber: event.windowNumber,
                context: nil,
                characters: event.characters(byApplyingModifiers: translationMods) ?? "",
                charactersIgnoringModifiers: event.charactersIgnoringModifiers ?? "",
                isARepeat: event.isARepeat,
                keyCode: event.keyCode
            ) ?? event
        }

        let action = event.isARepeat ? GHOSTTY_ACTION_REPEAT : GHOSTTY_ACTION_PRESS

        let markedTextBefore = markedText.length > 0

        keyTextAccumulator = []
        defer { keyTextAccumulator = nil }

        interpretKeyEvents([translationEvent])

        // Sync preedit state
        if markedText.length == 0 && markedTextBefore {
            // Preedit was cleared
            ghostty_surface_preedit(surface, nil, 0)
        }

        if let list = keyTextAccumulator, !list.isEmpty {
            for text in list {
                keyAction(action, event: event, translationEvent: translationEvent, text: text)
            }
        } else {
            keyAction(
                action,
                event: event,
                translationEvent: translationEvent,
                text: InputHelpers.ghosttyCharacters(from: translationEvent),
                composing: markedText.length > 0 || markedTextBefore
            )
        }
    }

    override func keyUp(with event: NSEvent) {
        currentModifierFlags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        keyAction(GHOSTTY_ACTION_RELEASE, event: event)
    }

    override func flagsChanged(with event: NSEvent) {
        currentModifierFlags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard let surface else { return }
        // Send modifier-only key events so ghostty can track modifier state
        var key_ev = ghostty_input_key_s()
        key_ev.action = GHOSTTY_ACTION_PRESS
        key_ev.keycode = UInt32(event.keyCode)
        key_ev.mods = InputHelpers.ghosttyMods(event.modifierFlags)
        key_ev.consumed_mods = GHOSTTY_MODS_NONE
        key_ev.text = nil
        key_ev.composing = false
        key_ev.unshifted_codepoint = 0
        ghostty_surface_key(surface, key_ev)

        // Hyperlink activation on macOS is modifier-sensitive, so hovering a
        // stationary pointer while pressing Command still needs a fresh update.
        sendMousePos(event)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard event.type == .keyDown, focused else { return false }
        if onKeyDownIntercept?(event, self) == true {
            return true
        }

        guard let surface else { return false }

        // Let Cmd+Q and Cmd+, pass through to the system menu
        let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let key = event.charactersIgnoringModifiers ?? ""
        if mods == .command && (key == "q" || key == ",") {
            return false
        }

        var keyEv = InputHelpers.ghosttyKeyEvent(from: event, action: GHOSTTY_ACTION_PRESS)
        var flags = ghostty_binding_flags_e(rawValue: 0)

        let isBound = (event.characters ?? "").withCString { ptr in
            keyEv.text = ptr
            return ghostty_surface_key_is_binding(surface, keyEv, &flags)
        }

        if isBound {
            keyDown(with: event)
            return true
        }

        return false
    }

    private func localKeyUp(_ event: NSEvent) -> NSEvent? {
        currentModifierFlags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard event.modifierFlags.contains(.command), focused else { return event }
        if isCommandShiftArrow(event) {
            return nil
        }
        keyUp(with: event)
        return nil
    }

    private func isCommandShiftArrow(_ event: NSEvent) -> Bool {
        let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard mods == [.command, .shift] else { return false }
        switch KeyShortcut.canonicalKey(from: event) {
        case "leftArrow", "rightArrow", "upArrow", "downArrow":
            return true
        default:
            return false
        }
    }

    @discardableResult
    private func keyAction(
        _ action: ghostty_input_action_e,
        event: NSEvent,
        translationEvent: NSEvent? = nil,
        text: String? = nil,
        composing: Bool = false
    ) -> Bool {
        guard let surface else { return false }

        var key_ev = InputHelpers.ghosttyKeyEvent(
            from: event,
            action: action,
            translationMods: translationEvent?.modifierFlags
        )
        key_ev.composing = composing

        // Only send text if it's not a control character (ghostty handles those)
        if let text, !text.isEmpty,
           let codepoint = text.utf8.first, codepoint >= 0x20 {
            if shouldOfferTextIntercept(text),
               onTextIntercept?(text, self) == true {
                return true
            }
            return text.withCString { ptr in
                key_ev.text = ptr
                return ghostty_surface_key(surface, key_ev)
            }
        } else {
            return ghostty_surface_key(surface, key_ev)
        }
    }

    private func shouldOfferTextIntercept(_ text: String) -> Bool {
        currentModifierFlags == [.command, .shift] && Self.isArrowPayloadText(text)
    }

    private static func isArrowPayloadText(_ text: String) -> Bool {
        let uppercased = text.uppercased()
        guard !uppercased.isEmpty,
              uppercased.count % 2 == 0,
              uppercased.allSatisfy({ $0.isHexDigit }) else {
            return false
        }

        return stride(from: 0, to: uppercased.count, by: 2).allSatisfy { offset in
            let start = uppercased.index(uppercased.startIndex, offsetBy: offset)
            let end = uppercased.index(start, offsetBy: 2)
            return ["0A", "0B", "0C", "0D"].contains(String(uppercased[start..<end]))
        }
    }

    // Swallow commands from interpretKeyEvents that we don't handle (ESC, etc.)
    // Without this, cancelOperation: propagates up the responder chain and crashes.
    override func doCommand(by selector: Selector) {
        // Intentionally empty — ghostty handles all key events directly.
    }

    // MARK: - Mouse

    override func mouseDown(with event: NSEvent) {
        guard let surface else { return }
        window?.makeFirstResponder(self)
        sendMousePos(event)
        ghostty_surface_mouse_button(surface, GHOSTTY_MOUSE_PRESS, GHOSTTY_MOUSE_LEFT,
                                     InputHelpers.ghosttyMods(event.modifierFlags))
    }

    override func mouseUp(with event: NSEvent) {
        guard let surface else { return }
        sendMousePos(event)
        ghostty_surface_mouse_button(surface, GHOSTTY_MOUSE_RELEASE, GHOSTTY_MOUSE_LEFT,
                                     InputHelpers.ghosttyMods(event.modifierFlags))
    }

    override func rightMouseDown(with event: NSEvent) {
        guard let surface else { return }
        sendMousePos(event)
        ghostty_surface_mouse_button(surface, GHOSTTY_MOUSE_PRESS, GHOSTTY_MOUSE_RIGHT,
                                     InputHelpers.ghosttyMods(event.modifierFlags))
    }

    override func rightMouseUp(with event: NSEvent) {
        guard let surface else { return }
        sendMousePos(event)
        ghostty_surface_mouse_button(surface, GHOSTTY_MOUSE_RELEASE, GHOSTTY_MOUSE_RIGHT,
                                     InputHelpers.ghosttyMods(event.modifierFlags))
    }

    override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        sendMousePos(event)
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        sendMousePos(event)
    }

    override func mouseMoved(with event: NSEvent) { sendMousePos(event) }
    override func mouseDragged(with event: NSEvent) { sendMousePos(event) }
    override func rightMouseDragged(with event: NSEvent) { sendMousePos(event) }

    private func sendMousePos(_ event: NSEvent) {
        guard let surface else { return }
        guard shouldReportMousePosition?() ?? true else { return }
        let pos = convert(event.locationInWindow, from: nil)
        ghostty_surface_mouse_pos(surface, pos.x, frame.height - pos.y,
                                  InputHelpers.ghosttyMods(event.modifierFlags))
    }

    override func scrollWheel(with event: NSEvent) {
        guard let surface else { return }
        ghostty_surface_mouse_scroll(surface,
                                     event.scrollingDeltaX,
                                     event.scrollingDeltaY,
                                     InputHelpers.scrollMods(from: event))
    }

    // MARK: - NSTextInputClient

    func hasMarkedText() -> Bool { markedText.length > 0 }

    func markedRange() -> NSRange {
        markedText.length > 0 ? NSRange(location: 0, length: markedText.length) : NSRange(location: NSNotFound, length: 0)
    }

    func selectedRange() -> NSRange {
        NSRange(location: NSNotFound, length: 0)
    }

    func setMarkedText(_ string: Any, selectedRange: NSRange, replacementRange: NSRange) {
        let attrStr: NSAttributedString
        if let s = string as? NSAttributedString {
            attrStr = s
        } else if let s = string as? String {
            attrStr = NSAttributedString(string: s)
        } else {
            return
        }
        markedText = NSMutableAttributedString(attributedString: attrStr)

        // Send preedit to libghostty
        if let surface {
            let text = markedText.string
            text.withCString { ptr in
                ghostty_surface_preedit(surface, ptr, UInt(text.utf8.count))
            }
        }
    }

    func unmarkText() {
        markedText = NSMutableAttributedString()
        if let surface {
            ghostty_surface_preedit(surface, nil, 0)
        }
    }

    func validAttributesForMarkedText() -> [NSAttributedString.Key] { [] }

    func attributedSubstring(forProposedRange range: NSRange, actualRange: NSRangePointer?) -> NSAttributedString? {
        nil
    }

    func insertText(_ string: Any, replacementRange: NSRange) {
        let chars: String
        if let s = string as? NSAttributedString {
            chars = s.string
        } else if let s = string as? String {
            chars = s
        } else {
            return
        }

        unmarkText()

        if var acc = keyTextAccumulator {
            acc.append(chars)
            keyTextAccumulator = acc
            onTextInserted?(chars, self)
        } else {
            // Direct text input (outside keyDown flow)
            sendTextToSurface(chars)
        }
    }

    func characterIndex(for point: NSPoint) -> Int { 0 }

    func firstRect(forCharacterRange range: NSRange, actualRange: NSRangePointer?) -> NSRect {
        guard let surface else { return .zero }
        var x: Double = 0, y: Double = 0, w: Double = 0, h: Double = 0
        ghostty_surface_ime_point(surface, &x, &y, &w, &h)

        // Ghostty uses top-left origin, AppKit uses bottom-left
        let viewRect = NSRect(x: x, y: frame.height - y - h, width: w, height: h)
        return window?.convertToScreen(convert(viewRect, to: nil)) ?? viewRect
    }
}
