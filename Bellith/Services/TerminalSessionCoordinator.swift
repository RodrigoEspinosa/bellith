import AppKit
import Foundation
import GhosttyKit
import os

protocol TerminalSessionCoordinatorHost: AnyObject {
    func makeSurface(tabId: UUID, context: TerminalContext) -> TerminalSurfaceView
    func addRestoredTabRootView(_ view: NSView)
    func refreshSmartPanelContexts()
}

final class TerminalSessionCoordinator {
    private static let maxSplitDepth = 8

    weak var host: TerminalSessionCoordinatorHost?

    init(host: TerminalSessionCoordinatorHost) {
        self.host = host
    }

    func saveSession(from tabs: [TerminalTabEntry], selectedTabIndex: Int) -> SessionState {
        let tabStates = tabs.compactMap { tab -> SessionState.TabState? in
            switch tab.content {
            case .terminal(let root, _, _):
                let tree = root.serialize { view in
                    (view as? TerminalSurfaceView)?.currentCwd
                }
                let context = tab.persistedContext
                return SessionState.TabState(
                    title: tab.title,
                    splitTree: tree,
                    terminalContext: context,
                    sshProfileID: context?.sshProfileID
                )
            case .smart(let panel):
                return SessionState.TabState(title: tab.title, smartPanelID: panel.pluginID)
            }
        }

        return SessionState(
            tabs: tabStates,
            selectedTabIndex: min(selectedTabIndex, max(tabStates.count - 1, 0))
        )
    }

    func sessionState(forTabAt index: Int, in tabs: [TerminalTabEntry]) -> SessionState? {
        guard index >= 0, index < tabs.count else { return nil }
        let tab = tabs[index]

        let tabState: SessionState.TabState
        switch tab.content {
        case .terminal(let root, _, _):
            let tree = root.serialize { view in
                (view as? TerminalSurfaceView)?.currentCwd
            }
            let context = tab.persistedContext
            tabState = SessionState.TabState(
                title: tab.title,
                splitTree: tree,
                terminalContext: context,
                sshProfileID: context?.sshProfileID
            )
        case .smart(let panel):
            tabState = SessionState.TabState(title: tab.title, smartPanelID: panel.pluginID)
        }

        return SessionState(tabs: [tabState], selectedTabIndex: 0)
    }

    func restoreSession(_ state: SessionState) -> [TerminalTabEntry] {
        guard let host else { return [] }

        var restoredTabs: [TerminalTabEntry] = []

        for tabState in state.tabs {
            let id = UUID()

            switch tabState.kind {
            case .terminal:
                guard let splitTree = tabState.splitTree else { continue }
                let sshProfile = tabState.sshProfileID.flatMap { SSHProfileStore.shared.profile(id: $0) }
                let restoredContext: TerminalContext
                if let sshProfile {
                    restoredContext = sshProfile.launchContext
                } else if tabState.sshProfileID != nil {
                    restoredContext = .local
                } else {
                    restoredContext = tabState.terminalContext ?? .local
                }

                var surfaces: [TerminalSurfaceView] = []
                let splitRoot = buildSplitTree(
                    splitTree,
                    tabId: id,
                    surfaces: &surfaces,
                    depth: 0,
                    context: restoredContext,
                    restoringSSHProfile: sshProfile,
                    host: host
                )

                let validSurfaces = surfaces.filter(\.isReady)
                guard !validSurfaces.isEmpty else {
                    Logger.app.warning("Session restore: skipping tab '\(tabState.title)' - no valid surfaces")
                    splitRoot.removeFromSuperview()
                    continue
                }

                var entry = TerminalTabEntry(
                    id: id,
                    title: tabState.title,
                    cwd: nil,
                    content: .terminal(splitRoot: splitRoot, surfaces: validSurfaces, focusedSurface: validSurfaces.first)
                )
                entry.cwd = validSurfaces.first?.currentCwd
                restoredTabs.append(entry)
                host.addRestoredTabRootView(splitRoot)
                splitRoot.isHidden = true

                if let sshProfile {
                    for surface in validSurfaces {
                        surface.terminalContext = sshProfile.launchContext
                        send(command: SSHLaunchBuilder.command(for: sshProfile), to: surface)
                    }
                }

            case .smart:
                guard let pluginID = tabState.smartPanelID,
                      let panel = SmartPanelView.create(pluginID: pluginID) else { continue }

                let entry = TerminalTabEntry(
                    id: id,
                    title: tabState.title,
                    cwd: nil,
                    content: .smart(panel: panel)
                )
                restoredTabs.append(entry)
                host.addRestoredTabRootView(panel)
                panel.isHidden = true
            }
        }

        return restoredTabs
    }

    func restoreWorkingDirectory(_ cwd: String, on surface: TerminalSurfaceView) {
        sendCdWhenReady(surface: surface, cwd: cwd)
    }

    func send(command: String, to surface: TerminalSurfaceView) {
        sendCommandWhenReady(surface: surface, command: command)
    }

    private func buildSplitTree(
        _ node: SplitNodeState,
        tabId: UUID,
        surfaces: inout [TerminalSurfaceView],
        depth: Int,
        context: TerminalContext,
        restoringSSHProfile: SSHProfile?,
        host: TerminalSessionCoordinatorHost
    ) -> SplitPaneView {
        switch node {
        case .leaf(let cwd):
            let surface = host.makeSurface(tabId: tabId, context: context)
            surface.currentCwd = cwd
            surfaces.append(surface)

            if restoringSSHProfile == nil, let cwd, !cwd.isEmpty {
                sendCdWhenReady(surface: surface, cwd: cwd)
            }

            return SplitPaneView(content: surface)

        case .branch(let orientation, let ratio, let firstNode, let secondNode):
            guard depth < Self.maxSplitDepth else {
                Logger.app.warning("Session restore: split depth limit reached, collapsing to leaf")
                let surface = host.makeSurface(tabId: tabId, context: context)
                surfaces.append(surface)
                return SplitPaneView(content: surface)
            }

            let resolvedOrientation: SplitPaneView.Orientation = orientation == "horizontal" ? .horizontal : .vertical
            let firstChild = buildSplitTree(
                firstNode,
                tabId: tabId,
                surfaces: &surfaces,
                depth: depth + 1,
                context: context,
                restoringSSHProfile: restoringSSHProfile,
                host: host
            )
            let secondChild = buildSplitTree(
                secondNode,
                tabId: tabId,
                surfaces: &surfaces,
                depth: depth + 1,
                context: context,
                restoringSSHProfile: restoringSSHProfile,
                host: host
            )

            return SplitPaneView.makeBranch(
                orientation: resolvedOrientation,
                ratio: CGFloat(ratio),
                first: firstChild,
                second: secondChild
            )
        }
    }

    private func sendCdWhenReady(surface: TerminalSurfaceView, cwd: String, attempt: Int = 0) {
        let maxAttempts = 5
        let delay = 0.05 * pow(2.0, Double(attempt))

        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self, weak surface] in
            guard let surface, let surf = surface.surface else { return }

            if let currentCwd = surface.currentCwd {
                guard currentCwd != cwd else { return }
                let escaped = cwd.replacingOccurrences(of: "'", with: "'\\''")
                let command = " cd '\(escaped)'\n"
                command.withCString { ptr in
                    ghostty_surface_text(surf, ptr, UInt(command.utf8.count))
                }
                return
            }

            if attempt >= maxAttempts {
                let escaped = cwd.replacingOccurrences(of: "'", with: "'\\''")
                let command = " cd '\(escaped)'\n"
                command.withCString { ptr in
                    ghostty_surface_text(surf, ptr, UInt(command.utf8.count))
                }
            } else {
                self?.sendCdWhenReady(surface: surface, cwd: cwd, attempt: attempt + 1)
            }
        }
    }

    private func sendCommandWhenReady(surface: TerminalSurfaceView, command: String, attempt: Int = 0) {
        let maxAttempts = 5
        let delay = 0.06 * pow(2.0, Double(attempt))

        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self, weak surface] in
            guard let surface, let surf = surface.surface else { return }
            let input = command + "\n"
            input.withCString { ptr in
                ghostty_surface_text(surf, ptr, UInt(input.utf8.count))
            }

            if attempt < maxAttempts && surface.currentCwd == nil && surface.terminalContext.isRemote {
                self?.host?.refreshSmartPanelContexts()
            }
        }
    }
}
