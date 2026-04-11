import AppKit
import Foundation
import GhosttyKit
import os

protocol TerminalSessionCoordinatorHost: AnyObject {
    func makeSurface(tabId: UUID, context: TerminalContext) -> TerminalSurfaceView
    func makePaneContent(for surface: TerminalSurfaceView) -> NSView
    func makeSmartPanel(pluginID: String) -> SmartPanelView?
    func addRestoredTabRootView(_ view: NSView)
    func refreshSmartPanelContexts()
}

final class TerminalSessionCoordinator {
    weak var host: TerminalSessionCoordinatorHost?

    init(host: TerminalSessionCoordinatorHost) {
        self.host = host
    }

    func saveSession(from tabs: [TerminalTabEntry], selectedTabIndex: Int, sidebarExpanded: Bool) -> SessionState {
        let tabStates = tabs.compactMap { tab -> SessionState.TabState? in
            switch tab.content {
            case .terminal:
                guard let snapshot = terminalSnapshot(for: tab) else { return nil }
                let context = tab.persistedContext
                return SessionState.TabState(
                    title: tab.title,
                    terminalSnapshot: snapshot,
                    terminalContext: context,
                    sshProfileID: context?.sshProfileID
                )
            case .smart(let panel):
                return SessionState.TabState(title: tab.title, smartPanelID: panel.pluginID)
            }
        }

        return SessionState(
            tabs: tabStates,
            selectedTabIndex: min(selectedTabIndex, max(tabStates.count - 1, 0)),
            sidebarExpanded: sidebarExpanded
        )
    }

    func sessionState(forTabAt index: Int, in tabs: [TerminalTabEntry]) -> SessionState? {
        guard index >= 0, index < tabs.count else { return nil }
        let tab = tabs[index]

        let tabState: SessionState.TabState
        switch tab.content {
        case .terminal:
            guard let snapshot = terminalSnapshot(for: tab) else { return nil }
            let context = tab.persistedContext
            tabState = SessionState.TabState(
                title: tab.title,
                terminalSnapshot: snapshot,
                terminalContext: context,
                sshProfileID: context?.sshProfileID
            )
        case .smart(let panel):
            tabState = SessionState.TabState(title: tab.title, smartPanelID: panel.pluginID)
        }

        return SessionState(tabs: [tabState], selectedTabIndex: 0, sidebarExpanded: nil)
    }

    func restoreSession(_ state: SessionState) -> [TerminalTabEntry] {
        guard let host else { return [] }

        var restoredTabs: [TerminalTabEntry] = []

        for tabState in state.tabs {
            let id = UUID()

            switch tabState.kind {
            case .terminal:
                guard let terminalSnapshot = tabState.terminalSnapshot else { continue }
                let sshProfile = tabState.sshProfileID.flatMap { SSHProfileStore.shared.profile(id: $0) }
                let restoredContext: TerminalContext
                if let sshProfile {
                    restoredContext = sshProfile.launchContext
                } else if tabState.sshProfileID != nil {
                    restoredContext = .local
                } else {
                    restoredContext = tabState.terminalContext ?? .local
                }

                let surface = host.makeSurface(tabId: id, context: restoredContext)
                guard surface.isReady else {
                    Logger.app.warning("Session restore: skipping tab '\(tabState.title)' - no valid surfaces")
                    continue
                }
                surface.currentCwd = terminalSnapshot.cwd
                let splitRoot = SplitPaneView(content: host.makePaneContent(for: surface))

                var entry = TerminalTabEntry(
                    id: id,
                    title: tabState.title,
                    cwd: nil,
                    localSessionBootstrap: terminalSnapshot.localSessionBootstrap,
                    localSessionName: terminalSnapshot.localSessionName,
                    content: .terminal(splitRoot: splitRoot, surfaces: [surface], focusedSurface: surface)
                )
                entry.cwd = surface.currentCwd
                restoredTabs.append(entry)
                host.addRestoredTabRootView(splitRoot)
                splitRoot.isHidden = true

                if let sshProfile {
                    surface.terminalContext = sshProfile.launchContext
                    send(command: SSHLaunchBuilder.command(for: sshProfile), to: surface)
                } else if let localBootstrap = terminalSnapshot.localSessionBootstrap,
                          let command = LocalSessionLaunchBuilder.command(
                              bootstrap: localBootstrap,
                              sessionName: terminalSnapshot.localSessionName,
                              workingDirectory: terminalSnapshot.cwd
                          ) {
                    send(command: command, to: surface)
                } else if let cwd = terminalSnapshot.cwd, !cwd.isEmpty {
                    sendCdWhenReady(surface: surface, cwd: cwd)
                }

                if shouldShowRestoredHistory(
                    snapshot: terminalSnapshot,
                    sshProfile: sshProfile
                ), let scrollbackText = terminalSnapshot.scrollbackText {
                    surface.showRestoredHistory(text: scrollbackText)
                }

            case .smart:
                guard let pluginID = tabState.smartPanelID,
                      let panel = host.makeSmartPanel(pluginID: pluginID) else { continue }

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

    private func terminalSnapshot(for tab: TerminalTabEntry) -> SessionState.TerminalSnapshot? {
        guard let surface = tab.focusedSurface ?? tab.surfaces.first else { return nil }
        let scrollback = surface.readScreenText()
        return SessionState.TerminalSnapshot(
            cwd: surface.currentCwd,
            hadScrollback: !(scrollback?.isEmpty ?? true),
            localSessionBootstrap: tab.localSessionBootstrap,
            localSessionName: tab.localSessionName,
            scrollbackText: shouldPersistScrollback(for: tab) ? scrollback : nil
        )
    }

    private func shouldPersistScrollback(for tab: TerminalTabEntry) -> Bool {
        guard tab.localSessionBootstrap == nil else { return false }
        guard let context = tab.persistedContext else { return true }
        return context.source == .local
    }

    private func shouldShowRestoredHistory(
        snapshot: SessionState.TerminalSnapshot,
        sshProfile: SSHProfile?
    ) -> Bool {
        guard snapshot.scrollbackText?.isEmpty == false else { return false }
        guard snapshot.localSessionBootstrap == nil else { return false }
        return sshProfile?.sessionBootstrap != .tmux && sshProfile?.sessionBootstrap != .zellij
    }
}
