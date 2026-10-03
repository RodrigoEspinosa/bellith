import AppKit
import ApplicationServices

/// Targeted Accessibility control of Resolve's documented Lua Console.
/// Actions are addressed to Resolve's PID and an observed console input; no screen coordinates.
@MainActor
final class ResolveComputerAdapter {
    static let bundleID = "com.blackmagic-design.DaVinciResolve"
    struct Reply: Decodable {
        let requestID: String
        let ok: Bool
        let snapshot: ResolveSnapshot?
        let sourceUnchanged: Bool?
        let error: String?
    }

    var accessibilityAvailable: Bool { AXIsProcessTrusted() }
    var installedVersion: String {
        let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: Self.bundleID)
        return url.flatMap(Bundle.init(url:))?.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Not installed"
    }

    func openResolve() {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: Self.bundleID) else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }

    func requestAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    func invoke(operation: String, directory: URL, fields: [String: String] = [:], removeKeys: [String] = [], markerNotes: [ResolveMarkerNote] = []) async throws -> ResolveSnapshot {
        guard accessibilityAvailable else {
            throw HarnessError.message("Enable Bellith in System Settings → Privacy & Security → Accessibility, then inspect again.")
        }
        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: Self.bundleID).first else {
            throw HarnessError.message("Open DaVinci Resolve and select a project and timeline first.")
        }
        guard let script = Bundle.main.url(forResource: "resolve_bridge", withExtension: "lua") else {
            throw HarnessError.message("The Resolve adapter is missing from this build.")
        }
        let root = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(root, 0.8)
        app.activate(options: [.activateIgnoringOtherApps])
        for _ in 0..<20 {
            if NSWorkspace.shared.frontmostApplication?.processIdentifier == app.processIdentifier { break }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        if consoleInput(root) == nil {
            guard let rawMenuBar = attribute(root, kAXMenuBarAttribute), CFGetTypeID(rawMenuBar) == AXUIElementGetTypeID() else {
                throw HarnessError.message("Resolve’s menu bar is unavailable. Open its Lua Console and retry.")
            }
            let menuBar = rawMenuBar as! AXUIElement
            guard let workspace = children(menuBar).first(where: { text($0, kAXTitleAttribute) == "Workspace" }),
                  let menu = children(workspace).first,
                  let console = children(menu).first(where: { text($0, kAXTitleAttribute) == "Console" }),
                  (attribute(console, kAXEnabledAttribute) as? Bool) == true else {
                throw HarnessError.message("Resolve’s Workspace → Console command is unavailable. Open a project first. English menu labels are required in this preview.")
            }
            guard AXUIElementPerformAction(console, kAXPressAction as CFString) == .success else {
                throw HarnessError.message("Could not open Resolve’s Console. Open Workspace → Console manually and retry.")
            }
        }
        var input: AXUIElement?
        for _ in 0..<20 {
            input = consoleInput(root)
            if input != nil { break }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        guard let input else { throw HarnessError.message("Resolve’s Console input could not be identified. Open its Lua console and inspect again.") }
        guard text(input, kAXValueAttribute).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw HarnessError.message("Resolve’s Console contains unfinished input. Clear or finish it before Bellith continues.")
        }
        let requestID = UUID().uuidString
        let output = directory.appendingPathComponent("response-\(requestID).json")
        var request = fields
        request["requestID"] = requestID
        request["operation"] = operation
        let notes = markerNotes.map { marker in
            "{frame=\(String(format: "%.0f", marker.frame)),name=\(ResolveLuaLiteral.string(marker.name)),note=\(ResolveLuaLiteral.string(marker.note))}"
        }.joined(separator: ",")
        let base = ResolveLuaLiteral.object(request, arrays: ["removeKeys": removeKeys])
        let payload = String(base.dropLast()) + ",[\"markers\"]={" + notes + "}}"
        let command = "dofile(\(ResolveLuaLiteral.string(script.path)))(\(payload))"
        // Check again immediately before typing; never redirect input into another app.
        guard NSWorkspace.shared.frontmostApplication?.processIdentifier == app.processIdentifier else {
            throw HarnessError.message("Focus moved away from Resolve. No command was sent. Inspect again when ready.")
        }
        let alreadyFocused = attribute(input, kAXFocusedAttribute) as? Bool == true
        guard alreadyFocused || AXUIElementSetAttributeValue(input, kAXFocusedAttribute as CFString, kCFBooleanTrue) == .success else {
            throw HarnessError.message("Focus the empty Lua Console input in Resolve and inspect again.")
        }
        guard AXUIElementSetAttributeValue(input, kAXValueAttribute as CFString, command as CFString) == .success,
              text(input, kAXValueAttribute) == command else {
            throw HarnessError.message("Could not write the command into Resolve’s Console. No command was submitted.")
        }
        // Setting a value does not guarantee keyboard focus. A user action or dialog
        // can move focus while Accessibility calls are in flight.
        guard NSWorkspace.shared.frontmostApplication?.processIdentifier == app.processIdentifier,
              attribute(input, kAXFocusedAttribute) as? Bool == true,
              let focused = attribute(root, kAXFocusedUIElementAttribute),
              CFGetTypeID(focused) == AXUIElementGetTypeID(), CFEqual(focused, input),
              text(input, kAXValueAttribute) == command else {
            throw HarnessError.message("Resolve focus changed after the command was staged. It was not submitted. Clear the Lua Console input and inspect again.")
        }
        guard let down = CGEvent(keyboardEventSource: nil, virtualKey: 36, keyDown: true),
              let up = CGEvent(keyboardEventSource: nil, virtualKey: 36, keyDown: false) else {
            throw HarnessError.message("Could not prepare Console submission. Clear the staged input before retrying; no command was submitted.")
        }
        down.postToPid(app.processIdentifier)
        up.postToPid(app.processIdentifier)
        let deadline = ContinuousClock().now.advanced(by: .seconds(15))
        while ContinuousClock().now < deadline {
            if let data = responseData(root, requestID: requestID, deadline: deadline) {
                let reply = try JSONDecoder().decode(Reply.self, from: data)
                try data.write(to: output, options: .atomic)
                guard reply.ok, reply.sourceUnchanged == true, let snapshot = reply.snapshot else {
                    throw HarnessError.message(reply.error ?? "Resolve could not verify the action. Inspect before continuing.")
                }
                return snapshot
            }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        throw HarnessError.message("Resolve did not return a verified result within 15 seconds. The command may have run. Check the Lua console and inspect the timeline; do not retry an edit blindly.")
    }

    private func attribute(_ element: AXUIElement, _ key: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, key as CFString, &value) == .success else { return nil }
        return value
    }

    private func children(_ element: AXUIElement) -> [AXUIElement] {
        attribute(element, kAXChildrenAttribute) as? [AXUIElement] ?? []
    }

    private func text(_ element: AXUIElement, _ key: String) -> String { attribute(element, key) as? String ?? "" }

    private func consoleInput(_ root: AXUIElement) -> AXUIElement? {
        let windows = attribute(root, kAXWindowsAttribute) as? [AXUIElement] ?? []
        for window in windows where text(window, kAXSubroleAttribute) == kAXFloatingWindowSubrole {
            let areas = descendants(window, depth: 0).filter { text($0, kAXRoleAttribute) == kAXTextAreaRole }
            guard areas.count == 2 else { continue }
            for area in areas {
                var settable = DarwinBoolean(false)
                AXUIElementIsAttributeSettable(area, kAXValueAttribute as CFString, &settable)
                if settable.boolValue { return area }
            }
        }
        return nil
    }

    private func responseData(_ root: AXUIElement, requestID: String, deadline: ContinuousClock.Instant) -> Data? {
        let windows = attribute(root, kAXWindowsAttribute) as? [AXUIElement] ?? []
        for window in windows where ContinuousClock().now < deadline && text(window, kAXSubroleAttribute) == kAXFloatingWindowSubrole {
            for area in descendants(window, depth: 0, deadline: deadline) where ContinuousClock().now < deadline && text(area, kAXRoleAttribute) == kAXTextAreaRole {
                let output = text(area, kAXValueAttribute)
                for line in output.components(separatedBy: .newlines).reversed() where line.hasPrefix("BELLITH_RESULT:") {
                    let data = Data(line.dropFirst("BELLITH_RESULT:".count).utf8)
                    if let reply = try? JSONDecoder().decode(Reply.self, from: data), reply.requestID == requestID { return data }
                }
            }
        }
        return nil
    }

    private func descendants(_ element: AXUIElement, depth: Int, deadline: ContinuousClock.Instant? = nil) -> [AXUIElement] {
        guard depth < 5, deadline.map({ ContinuousClock().now < $0 }) ?? true else { return [] }
        let elements = children(element)
        return elements + elements.flatMap { descendants($0, depth: depth + 1, deadline: deadline) }
    }
}
