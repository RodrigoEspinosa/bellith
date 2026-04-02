import AppKit
import GhosttyKit

/// NSView subclass that hosts a single ghostty terminal surface.
/// Handles Metal rendering internally via libghostty — we just forward events.
final class TerminalSurfaceView: NSView, NSTextInputClient {
    private(set) var surface: ghostty_surface_t?
    private weak var terminalApp: TerminalApp?
    private var markedText = NSMutableAttributedString()
    private var keyTextAccumulator: [String]?
    private var eventMonitor: Any?
    private var focused = false

    /// Called when the shell process exits or the surface requests close.
    var onClose: ((Bool) -> Void)?

    init(app: TerminalApp, baseConfig: ghostty_surface_config_s? = nil) {
        self.terminalApp = app
        super.init(frame: NSRect(x: 0, y: 0, width: 800, height: 600))

        wantsLayer = true
        layer?.isOpaque = true

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

        // Monitor for key-up events that don't reach the responder chain
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyUp]) { [weak self] event in
            self?.localKeyUp(event) ?? event
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    deinit {
        if let eventMonitor { NSEvent.removeMonitor(eventMonitor) }
        if let surface { ghostty_surface_free(surface) }
    }

    // MARK: - View Lifecycle

    override var acceptsFirstResponder: Bool { true }

    override func becomeFirstResponder() -> Bool {
        focused = true
        if let surface { ghostty_surface_set_focus(surface, true) }
        return super.becomeFirstResponder()
    }

    override func resignFirstResponder() -> Bool {
        focused = false
        if let surface { ghostty_surface_set_focus(surface, false) }
        return super.resignFirstResponder()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil {
            updateContentScale()
        }
    }

    override var wantsUpdateLayer: Bool { true }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        guard let surface else { return }
        // Ghostty expects backing pixel sizes (retina-scaled), not points
        let scaled = convertToBacking(newSize)
        ghostty_surface_set_size(surface, UInt32(scaled.width), UInt32(scaled.height))
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
    }

    private func updateContentScale() {
        guard let surface else { return }
        let scale = Double(window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2.0)
        ghostty_surface_set_content_scale(surface, scale, scale)
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

    // MARK: - Keyboard

    override func keyDown(with event: NSEvent) {
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
        keyAction(GHOSTTY_ACTION_RELEASE, event: event)
    }

    override func flagsChanged(with event: NSEvent) {
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
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard event.type == .keyDown, focused else { return false }
        guard let surface else { return false }

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
        guard event.modifierFlags.contains(.command), focused else { return event }
        keyUp(with: event)
        return nil
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
            return text.withCString { ptr in
                key_ev.text = ptr
                return ghostty_surface_key(surface, key_ev)
            }
        } else {
            return ghostty_surface_key(surface, key_ev)
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
        ghostty_surface_mouse_button(surface, GHOSTTY_MOUSE_PRESS, GHOSTTY_MOUSE_LEFT,
                                     InputHelpers.ghosttyMods(event.modifierFlags))
    }

    override func mouseUp(with event: NSEvent) {
        guard let surface else { return }
        ghostty_surface_mouse_button(surface, GHOSTTY_MOUSE_RELEASE, GHOSTTY_MOUSE_LEFT,
                                     InputHelpers.ghosttyMods(event.modifierFlags))
    }

    override func rightMouseDown(with event: NSEvent) {
        guard let surface else { return }
        ghostty_surface_mouse_button(surface, GHOSTTY_MOUSE_PRESS, GHOSTTY_MOUSE_RIGHT,
                                     InputHelpers.ghosttyMods(event.modifierFlags))
    }

    override func rightMouseUp(with event: NSEvent) {
        guard let surface else { return }
        ghostty_surface_mouse_button(surface, GHOSTTY_MOUSE_RELEASE, GHOSTTY_MOUSE_RIGHT,
                                     InputHelpers.ghosttyMods(event.modifierFlags))
    }

    override func mouseMoved(with event: NSEvent) { sendMousePos(event) }
    override func mouseDragged(with event: NSEvent) { sendMousePos(event) }
    override func rightMouseDragged(with event: NSEvent) { sendMousePos(event) }

    private func sendMousePos(_ event: NSEvent) {
        guard let surface else { return }
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
        } else {
            // Direct text input (outside keyDown flow)
            if let surface {
                chars.withCString { ptr in
                    ghostty_surface_text(surface, ptr, UInt(chars.utf8.count))
                }
            }
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
