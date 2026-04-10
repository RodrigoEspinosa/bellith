import Foundation

struct ToolActivityEvent: Equatable {
    enum Kind: Equatable {
        case processStarted
        case networkOpened

        var iconName: String {
            switch self {
            case .processStarted:
                return "terminal"
            case .networkOpened:
                return "network"
            }
        }

        var label: String {
            switch self {
            case .processStarted:
                return "Process Started"
            case .networkOpened:
                return "Network Opened"
            }
        }
    }

    let kind: Kind
    let title: String
    let subtitle: String
    let timestamp: Date
}

struct ToolActivitySnapshot {
    let events: [ToolActivityEvent]
}

final class ToolActivityMonitor {
    private var previousProcessIDs: Set<pid_t> = []
    private var previousConnections: Set<String> = []
    private var recentEvents: [ToolActivityEvent] = []

    private let maxEvents: Int

    init(maxEvents: Int = 80) {
        self.maxEvents = maxEvents
    }

    func snapshot(for shellPID: pid_t, now: Date = .init()) -> ToolActivitySnapshot {
        var newEvents: [ToolActivityEvent] = []

        let descendantProcesses = ProcessMonitor.processTree(rootPID: shellPID)
            .map(flattenProcesses(from:))
            ?? []
        let processIDs = Set(descendantProcesses.map(\.pid))

        for process in descendantProcesses where process.pid != shellPID && !previousProcessIDs.contains(process.pid) {
            newEvents.append(
                ToolActivityEvent(
                    kind: .processStarted,
                    title: process.name,
                    subtitle: "pid \(process.pid)",
                    timestamp: process.startTime ?? now
                )
            )
        }
        previousProcessIDs = processIDs

        let connections = NetworkMonitor.connections(for: Array(processIDs))
            .filter { $0.state == "ESTABLISHED" || $0.state == "LISTEN" }
        let connectionKeys = Set(connections.map(connectionKey(for:)))

        for connection in connections where !previousConnections.contains(connectionKey(for: connection)) {
            newEvents.append(
                ToolActivityEvent(
                    kind: .networkOpened,
                    title: connection.processName,
                    subtitle: connection.displayRemote,
                    timestamp: now
                )
            )
        }
        previousConnections = connectionKeys

        if !newEvents.isEmpty {
            recentEvents.insert(contentsOf: newEvents.sorted { $0.timestamp > $1.timestamp }, at: 0)
            if recentEvents.count > maxEvents {
                recentEvents = Array(recentEvents.prefix(maxEvents))
            }
        }

        return ToolActivitySnapshot(events: recentEvents)
    }

    private func flattenProcesses(from root: TerminalProcessInfo) -> [TerminalProcessInfo] {
        var result: [TerminalProcessInfo] = []

        func walk(_ node: TerminalProcessInfo) {
            result.append(node)
            for child in node.children {
                walk(child)
            }
        }

        walk(root)
        return result
    }

    private func connectionKey(for connection: ConnectionInfo) -> String {
        [
            String(connection.pid),
            connection.protocolName,
            connection.localAddress,
            String(connection.localPort),
            connection.remoteAddress,
            String(connection.remotePort),
            connection.state,
        ].joined(separator: "|")
    }
}
