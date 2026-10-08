import AppKit
import ApplicationServices

/// Named AX controls only. No keyboard shortcuts, recording, region edits, or plug-in writes.
/// Playback is exposed; track controls remain internal pending receipt/UI and live qualification.
enum LogicTransportAdapter {
    /// Not exposed in UI/MCP until durable attempt handling and live qualification are complete.
    @MainActor static func performTrack(_ request: LogicTrackControlRequest, expected: LogicTransportSnapshot) async throws -> LogicTransportSnapshot {
        let pid = try runningProcess()
        guard pid == expected.processID else { throw LogicTransportError.message("Logic restarted. Inspect again.") }
        return try await runOperation {
            try Task.checkCancellation()
            let before = try context(pid: pid, captureTracks: true)
            try request.validate(expected: expected, observed: before.snapshot)
            let fresh = try context(pid: pid, captureTracks: true)
            try request.validate(expected: expected, observed: fresh.snapshot)
            let headers = try trackHeaders(fresh.window)
            let matches = headers.filter { $0.0.number == request.trackNumber && $0.0.name == request.trackName }
            guard matches.count == 1 else { throw failure() }
            let label = request.control == .mute ? "Mute" : "Solo"
            let controls = matches[0].1.filter {
                text($0, kAXRoleAttribute) == kAXCheckBoxRole &&
                    (text($0, kAXTitleAttribute) == label || text($0, kAXDescriptionAttribute) == label)
            }
            guard controls.count == 1, let target = controls.first, let value = bool(target, kAXValueAttribute) else { throw failure() }
            // Recheck the project, recording, transport and every exposed track after discovery.
            let final = try context(pid: pid, captureTracks: true)
            try request.validate(expected: expected, observed: final.snapshot)
            guard final.snapshot.exposedTracks == headers.map({ $0.0 }),
                  bool(target, kAXValueAttribute) == value else { throw failure() }
            if value == request.enabled {
                try request.validateAcknowledgement(expected: expected, observed: final.snapshot)
                return final.snapshot
            }
            guard !Task.isCancelled, bool(target, kAXEnabledAttribute) == true,
                  AXUIElementPerformAction(target, kAXPressAction as CFString) == .success else {
                throw LogicTransportError.message("Logic did not accept the named track control. Inspect before retrying.")
            }
            let deadline = ContinuousClock.now.advanced(by: .seconds(3))
            while ContinuousClock.now < deadline {
                try Task.checkCancellation()
                let after = try context(pid: pid, captureTracks: true).snapshot
                guard after.processID == expected.processID, after.documentURL == expected.documentURL,
                      !after.recording, after.playing == expected.playing else {
                    throw LogicTransportError.message("Logic changed project or transport during the track action. The result is unverified; check Logic.")
                }
                if (try? request.validateAcknowledgement(expected: expected, observed: after)) != nil { return after }
                try await Task.sleep(for: .milliseconds(100))
            }
            throw LogicTransportError.message("Logic did not confirm the isolated track change. Check Logic before retrying.")
        }
    }
    @MainActor static func inspect() async throws -> LogicTransportSnapshot {
        let pid = try runningProcess()
        return try await runOperation { try context(pid: pid, captureTracks: true).snapshot }
    }

    @MainActor static func perform(_ action: LogicTransportAction, expected: LogicTransportSnapshot) async throws -> LogicTransportSnapshot {
        let pid = try runningProcess()
        guard pid == expected.processID else {
            throw LogicTransportError.message("Logic restarted. Inspect its project again.")
        }
        return try await runOperation {
            try Task.checkCancellation()
            let before = try context(pid: pid)
            try action.validate(expected: expected, observed: before.snapshot)
            if before.snapshot.playing == action.requestedPlaying { return before.snapshot }
            // Re-read immediately before pressing: a different project/dialog/recording fails closed.
            let fresh = try context(pid: pid)
            try action.validate(expected: expected, observed: fresh.snapshot)
            let target = action == .play ? fresh.play : fresh.stop
            try Task.checkCancellation()
            guard bool(target, kAXEnabledAttribute) == true,
                  AXUIElementPerformAction(target, kAXPressAction as CFString) == .success else {
                throw LogicTransportError.message("Logic did not accept the named transport control. Inspect again.")
            }
            // AX feedback, not a successful press, determines the reported result.
            let deadline = ContinuousClock.now.advanced(by: .seconds(3))
            while ContinuousClock.now < deadline {
                try Task.checkCancellation()
                let after = try context(pid: pid)
                guard after.snapshot.documentURL == expected.documentURL, !after.snapshot.recording else {
                    throw LogicTransportError.message("Logic changed project or entered recording during the action. The result is unverified; check Logic.")
                }
                if after.snapshot.playing == action.requestedPlaying { return after.snapshot }
                try await Task.sleep(for: .milliseconds(100))
            }
            throw LogicTransportError.message("Logic did not confirm the requested playback state. Check Logic before retrying.")
        }
    }

    /// AX work stays off the main actor, but must share its caller's cancellation.
    static func runOperation<Value: Sendable>(_ operation: @escaping @Sendable () async throws -> Value) async throws -> Value {
        let worker = Task.detached(priority: .userInitiated) {
            try Task.checkCancellation()
            return try await operation()
        }
        return try await withTaskCancellationHandler {
            if Task.isCancelled { worker.cancel() }
            return try await worker.value
        } onCancel: {
            worker.cancel()
        }
    }

    @MainActor private static func runningProcess() throws -> pid_t {
        guard AXIsProcessTrusted() else {
            throw LogicTransportError.message("Bellith needs Accessibility access to inspect Logic. Enable it in System Settings if you want to use these controls.")
        }
        let running = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.logic10")
        guard running.count == 1, let app = running.first else {
            throw LogicTransportError.message("Open one Logic Pro instance and its Tracks window, then inspect again.")
        }
        return app.processIdentifier
    }

    private struct Context {
        let window: AXUIElement
        let snapshot: LogicTransportSnapshot
        let play: AXUIElement
        let stop: AXUIElement
    }

    private static func context(pid: pid_t, captureTracks: Bool = false) throws -> Context {
        let root = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(root, 0.25)
        let windows = try elements(root, kAXWindowsAttribute)
        guard windows.count <= 30 else { throw failure() }
        for window in windows {
            let subrole = text(window, kAXSubroleAttribute)
            guard subrole != kAXDialogSubrole, subrole != kAXSystemDialogSubrole,
                  bool(window, kAXModalAttribute) != true,
                  !(try elements(window, kAXChildrenAttribute, optional: true)).contains(where: {
                      text($0, kAXRoleAttribute) == kAXSheetRole
                  }) else {
                throw LogicTransportError.message("Resolve Logic’s open dialog first, then inspect again.")
            }
        }
        // Multiple project windows are ambiguous; never choose the first one.
        let projects = windows.filter {
            text($0, kAXSubroleAttribute) == kAXStandardWindowSubrole && document($0) != nil
        }
        guard projects.count == 1, let window = projects.first, let url = document(window) else {
            throw LogicTransportError.message("Open a single Logic project Tracks window. Project choosers and plug-in windows are not transport targets.")
        }
        let deadline = ContinuousClock.now.advanced(by: .seconds(4))
        let bars = try elements(window, kAXChildrenAttribute).filter { text($0, kAXDescriptionAttribute) == "Control Bar" }
        guard bars.count == 1, let bar = bars.first else { throw failure() }
        let controls = try descendants(bar, deadline: deadline)
        func control(_ name: String, role: String) throws -> AXUIElement {
            let matches = controls.filter {
                text($0, kAXRoleAttribute) == role && text($0, kAXTitleAttribute) == name
            }
            guard matches.count == 1, let match = matches.first else { throw failure() }
            return match
        }
        let play = try control("Play", role: kAXCheckBoxRole)
        let record = try control("Record", role: kAXCheckBoxRole)
        guard let playing = bool(play, kAXValueAttribute), let recording = bool(record, kAXValueAttribute) else { throw failure() }
        // Logic changes this title when stopped. Never press Go to Beginning for a stop request.
        let stops = controls.filter {
            text($0, kAXRoleAttribute) == kAXButtonRole && LogicTransportAction.recognizesStopControl(title: text($0, kAXTitleAttribute), playing: playing)
        }
        guard stops.count == 1, let stop = stops.first,
              document(window) == url,
              bool(play, kAXValueAttribute) == playing, bool(record, kAXValueAttribute) == recording else { throw failure() }
        var snapshot = LogicTransportSnapshot(processID: pid, documentURL: url, windowTitle: text(window, kAXTitleAttribute),
            playing: playing, recording: recording, inspectedAt: Date())
        if captureTracks {
            snapshot.exposedTracks = try? trackHeaders(window).map { $0.0 }
            guard document(window) == url, bool(play, kAXValueAttribute) == playing,
                  bool(record, kAXValueAttribute) == recording else { throw failure() }
        }
        return Context(window: window, snapshot: snapshot, play: play, stop: stop)
    }

    private static func trackHeaders(_ window: AXUIElement) throws -> [(LogicTrackObservation, [AXUIElement])] {
        let deadline = ContinuousClock.now.advanced(by: .seconds(1))
        var queue = try elements(window, kAXChildrenAttribute)
        var index = 0
        var headers: [AXUIElement] = []
        while index < queue.count {
            guard queue.count <= 500, ContinuousClock.now < deadline else { throw failure() }
            let node = queue[index]
            index += 1
            let title = text(node, kAXTitleAttribute)
            if title == "Tracks header" { headers.append(node); continue }
            // Do not enumerate regions, plug-ins, channel strips, or the transport for track discovery.
            if ["Tracks contents", "Inspector"].contains(title) || text(node, kAXDescriptionAttribute) == "Control Bar" { continue }
            queue += try elements(node, kAXChildrenAttribute, optional: true)
        }
        guard headers.count == 1, let header = headers.first else { throw failure() }
        let groups = try elements(header, kAXChildrenAttribute)
        guard groups.count <= 100 else { throw failure() }
        var result: [(LogicTrackObservation, [AXUIElement])] = []
        for group in groups where text(group, kAXRoleAttribute) == kAXGroupRole {
            guard ContinuousClock.now < deadline else { throw failure() }
            guard let (number, name) = LogicTrackObservation.identity(description: text(group, kAXDescriptionAttribute)) else { throw failure() }
            let controls = try elements(group, kAXChildrenAttribute)
            func state(_ label: String) -> Bool? {
                let matches = controls.filter {
                    text($0, kAXRoleAttribute) == kAXCheckBoxRole &&
                        (text($0, kAXDescriptionAttribute) == label || text($0, kAXTitleAttribute) == label)
                }
                return matches.count == 1 ? bool(matches[0], kAXValueAttribute) : nil
            }
            result.append((.init(number: number, name: name, selected: bool(group, kAXSelectedAttribute), muted: state("Mute"), soloed: state("Solo")), controls))
        }
        guard Set(result.map { $0.0.number }).count == result.count else { throw failure() }
        return result
    }

    private static func descendants(_ root: AXUIElement, deadline: ContinuousClock.Instant) throws -> [AXUIElement] {
        var queue = [root]
        var result: [AXUIElement] = []
        var index = 0
        while index < queue.count {
            guard queue.count <= 1500, ContinuousClock.now < deadline else { throw failure() }
            let element = queue[index]
            index += 1
            result.append(element)
            queue += try elements(element, kAXChildrenAttribute, optional: true)
        }
        return result
    }

    private static func elements(_ element: AXUIElement, _ key: String, optional: Bool = false) throws -> [AXUIElement] {
        var value: CFTypeRef?
        let status = AXUIElementCopyAttributeValue(element, key as CFString, &value)
        if optional && (status == .attributeUnsupported || status == .noValue) { return [] }
        guard status == .success, let values = value as? [AXUIElement] else { throw failure() }
        return values
    }

    private static func text(_ element: AXUIElement, _ key: String) -> String {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, key as CFString, &value) == .success else { return "" }
        return value as? String ?? ""
    }

    private static func bool(_ element: AXUIElement, _ key: String) -> Bool? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, key as CFString, &value) == .success,
              let number = value as? NSNumber, number == 0 || number == 1 else { return nil }
        return number.boolValue
    }

    private static func document(_ window: AXUIElement) -> URL? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window, kAXDocumentAttribute as CFString, &value) == .success else { return nil }
        let url = (value as? URL) ?? (value as? String).flatMap(URL.init(string:))
        guard let url, url.isFileURL, url.pathExtension == "logicx" else { return nil }
        return url.standardizedFileURL
    }

    private static func failure() -> LogicTransportError {
        .message("Logic’s named transport controls could not be read reliably. Show its Tracks window with Play, Stop, and Record visible, then inspect again. English controls are currently required.")
    }
}
