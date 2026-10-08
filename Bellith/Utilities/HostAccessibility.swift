import AppKit
import ApplicationServices

/// Accessibility trust that lets Bellith read and drive creative host apps.
enum HostAccessibility {
    static var isTrusted: Bool {
        #if DEBUG
        if ProcessInfo.processInfo.environment["BELLITH_QA_SIMULATE_UNTRUSTED"] == "1" { return false }
        #endif
        return AXIsProcessTrusted()
    }

    /// Prompting registers Bellith in the Accessibility list; the pane opens so the switch is in view.
    static func request() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
}
