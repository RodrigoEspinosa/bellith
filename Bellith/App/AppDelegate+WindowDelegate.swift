import AppKit

extension AppDelegate: NSWindowDelegate {
    func windowDidBecomeKey(_ notification: Notification) {
        guard let window = notification.object as? TerminalWindow,
              let entry = windows.first(where: { $0.window === window }) else { return }
        terminalApp?.setFocus(true)
        window.makeFirstResponder(entry.container.activeSurface)
    }

    func windowDidResignKey(_ notification: Notification) {
        terminalApp?.setFocus(false)
    }

    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? TerminalWindow else { return }
        windows.removeAll { $0.window === window }
    }
}
