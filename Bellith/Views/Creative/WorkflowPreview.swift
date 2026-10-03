#if DEBUG
import AppKit
import SwiftUI

/// Separate QA bundle only: real views, disposable data, no host or CLI execution.
@MainActor
enum WorkflowPreview {
    static var isEnabled: Bool {
        ["com.rec.bellith.qa", "com.rec.bellith.qa.review", "com.rec.bellith.qa.studio"].contains(Bundle.main.bundleIdentifier ?? "")
    }
    static func makeWindows() -> [NSWindowController] {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("Bellith-Studio-Preview-\(UUID().uuidString)")
        let controller = StudioWindowController(previewOnly: true, storage: root,
            openTerminal: {}, startCompanion: { _ in false })
        let menu = NSMenu()
        let appMenu = NSMenu(title: "Bellith QA")
        appMenu.addItem(withTitle: "Quit Bellith QA", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        let appItem = NSMenuItem()
        appItem.submenu = appMenu
        menu.addItem(appItem)
        NSApp.mainMenu = menu
        controller.show(.home)
        return [controller]
    }

}
#endif
