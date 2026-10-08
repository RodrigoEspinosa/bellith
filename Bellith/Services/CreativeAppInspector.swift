import AppKit
import ApplicationServices

/// Local, read-only discovery. Does not activate apps, dismiss dialogs, or infer host control.
@MainActor
enum CreativeAppInspector {
    static func inspect() async -> [CreativeAppConnection] {
        var result: [CreativeAppConnection] = []
        for (id, name) in [("com.blackmagic-design.DaVinciResolve", "DaVinci Resolve"), ("com.apple.logic10", "Logic Pro")] {
            let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id)
            let version = url.flatMap(Bundle.init(url:))?.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
            let running = NSRunningApplication.runningApplications(withBundleIdentifier: id).first
            var state: CreativeAppConnection.State = url == nil ? .notInstalled : .notRunning
            var title: String?
            if let running {
                state = .permissionRequired
                if AXIsProcessTrusted() {
                    let pid = running.processIdentifier
                    let observed = await Task.detached(priority: .userInitiated) { inspectWindows(pid: pid) }.value
                    state = observed.0
                    title = observed.1
                }
            }
            result.append(CreativeAppConnection(id: id, name: name, version: version, state: state,
                                                windowTitle: title, inspectedAt: Date()))
        }
        return result
    }

    nonisolated private static func inspectWindows(pid: pid_t) -> (CreativeAppConnection.State, String?) {
        let root = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(root, 0.5)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(root, kAXWindowsAttribute as CFString, &value) == .success,
              let windows = value as? [AXUIElement] else { return (.unavailable, nil) }
        // Bound the amount of UI read work; never recursively enumerate an entire DAW.
        guard windows.count <= 30 else { return (.unavailable, nil) }
        let dialog = windows.contains { window in
            let subrole = text(window, kAXSubroleAttribute)
            var sheets: CFTypeRef?
            AXUIElementCopyAttributeValue(window, kAXChildrenAttribute as CFString, &sheets)
            return subrole == kAXDialogSubrole || subrole == kAXSystemDialogSubrole
                || ((sheets as? [AXUIElement]) ?? []).contains { text($0, kAXRoleAttribute) == kAXSheetRole }
        }
        let main = windows.first { text($0, kAXSubroleAttribute) == kAXStandardWindowSubrole }
        let title = main.map { text($0, kAXTitleAttribute) }.flatMap { $0.isEmpty ? nil : $0 }
        return (dialog ? .dialogOpen : (main == nil ? .noWindow : .windowObserved), title)
    }

    nonisolated private static func text(_ element: AXUIElement, _ key: String) -> String {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, key as CFString, &value) == .success else { return "" }
        return value as? String ?? ""
    }
}
