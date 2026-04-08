import Foundation

struct ToolActivityEvent: Equatable {
    enum Kind: Equatable {
        case fileAdded
        case fileModified
        case fileRemoved
        case processStarted
        case networkOpened

        var iconName: String {
            switch self {
            case .fileAdded:
                return "plus.square"
            case .fileModified:
                return "doc.text"
            case .fileRemoved:
                return "trash"
            case .processStarted:
                return "terminal"
            case .networkOpened:
                return "network"
            }
        }

        var label: String {
            switch self {
            case .fileAdded:
                return "File Added"
            case .fileModified:
                return "File Modified"
            case .fileRemoved:
                return "File Removed"
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

enum ToolActivityPathFilter {
    private static let ignoredDirectoryNames: Set<String> = [
        ".git", ".build", "build", "dist", "DerivedData", "node_modules", ".next", ".turbo"
    ]

    private static let ignoredPathFragments: [String] = [
        "/tmp/",
        "/.cache/",
        "/Library/Caches/",
    ]

    static func shouldSkipDirectory(named name: String) -> Bool {
        ignoredDirectoryNames.contains(name)
    }

    static func shouldIncludeFile(at path: String) -> Bool {
        let lowered = path.lowercased()
        return !ignoredPathFragments.contains(where: { lowered.contains($0.lowercased()) })
    }
}

final class ToolActivityMonitor {
    private struct FileSnapshotEntry: Equatable {
        let modifiedAt: Date
    }

    private var previousFiles: [String: FileSnapshotEntry] = [:]
    private var previousProcessIDs: Set<pid_t> = []
    private var previousConnections: Set<String> = []
    private var recentEvents: [ToolActivityEvent] = []

    private let fileManager: FileManager
    private let maxTrackedFiles: Int
    private let maxEvents: Int

    init(fileManager: FileManager = .default, maxTrackedFiles: Int = 600, maxEvents: Int = 80) {
        self.fileManager = fileManager
        self.maxTrackedFiles = maxTrackedFiles
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

        if let cwd = ProcessMonitor.workingDirectory(for: shellPID) {
            let currentFiles = fileSnapshot(in: cwd)

            for (path, entry) in currentFiles where previousFiles[path] == nil {
                newEvents.append(
                    ToolActivityEvent(
                        kind: .fileAdded,
                        title: (path as NSString).lastPathComponent,
                        subtitle: relativePath(path, base: cwd),
                        timestamp: entry.modifiedAt
                    )
                )
            }

            for (path, entry) in currentFiles {
                if let previous = previousFiles[path], previous.modifiedAt != entry.modifiedAt {
                    newEvents.append(
                        ToolActivityEvent(
                            kind: .fileModified,
                            title: (path as NSString).lastPathComponent,
                            subtitle: relativePath(path, base: cwd),
                            timestamp: entry.modifiedAt
                        )
                    )
                }
            }

            for path in previousFiles.keys where currentFiles[path] == nil {
                newEvents.append(
                    ToolActivityEvent(
                        kind: .fileRemoved,
                        title: (path as NSString).lastPathComponent,
                        subtitle: relativePath(path, base: cwd),
                        timestamp: now
                    )
                )
            }

            previousFiles = currentFiles
        }

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

    private func fileSnapshot(in directory: String) -> [String: FileSnapshotEntry] {
        let rootURL = URL(fileURLWithPath: directory, isDirectory: true)
        guard let enumerator = fileManager.enumerator(
            at: rootURL,
            includingPropertiesForKeys: [.isRegularFileKey, .isDirectoryKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles],
            errorHandler: nil
        ) else {
            return [:]
        }

        var snapshot: [String: FileSnapshotEntry] = [:]

        for case let fileURL as URL in enumerator {
            if snapshot.count >= maxTrackedFiles { break }

            let values = try? fileURL.resourceValues(forKeys: [.isDirectoryKey, .isRegularFileKey, .contentModificationDateKey])

            if values?.isDirectory == true {
                if ToolActivityPathFilter.shouldSkipDirectory(named: fileURL.lastPathComponent) {
                    enumerator.skipDescendants()
                }
                continue
            }

            guard values?.isRegularFile == true else { continue }
            let path = fileURL.path
            guard ToolActivityPathFilter.shouldIncludeFile(at: path) else { continue }

            snapshot[path] = FileSnapshotEntry(modifiedAt: values?.contentModificationDate ?? .distantPast)
        }

        return snapshot
    }

    private func relativePath(_ path: String, base: String) -> String {
        let baseURL = URL(fileURLWithPath: base, isDirectory: true)
        let fileURL = URL(fileURLWithPath: path)
        let relative = fileURL.path.replacingOccurrences(of: baseURL.path + "/", with: "")
        return relative.isEmpty ? fileURL.lastPathComponent : relative
    }
}
