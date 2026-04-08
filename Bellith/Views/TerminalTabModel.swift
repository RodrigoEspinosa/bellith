import AppKit

struct GitRepositoryInfo: Equatable {
    let branch: String?
    let worktreeName: String?
    let isWorktree: Bool
}

enum TerminalTabContent {
    case terminal(splitRoot: SplitPaneView, surfaces: [TerminalSurfaceView], focusedSurface: TerminalSurfaceView?)
    case smart(panel: SmartPanelView)
}

enum TerminalTabKind: Equatable {
    case terminal
    case smart(String)
}

struct TerminalTabEntry {
    let id: UUID
    var title: String
    var cwd: String?
    var content: TerminalTabContent

    var kind: TerminalTabKind {
        switch content {
        case .terminal:
            return .terminal
        case .smart(let panel):
            return .smart(panel.pluginID)
        }
    }

    var splitRoot: SplitPaneView? {
        if case .terminal(let root, _, _) = content { return root }
        return nil
    }

    var surfaces: [TerminalSurfaceView] {
        if case .terminal(_, let surfaces, _) = content { return surfaces }
        return []
    }

    var focusedSurface: TerminalSurfaceView? {
        get {
            if case .terminal(_, _, let focused) = content { return focused }
            return nil
        }
        set {
            if case .terminal(let root, let surfaces, _) = content {
                content = .terminal(splitRoot: root, surfaces: surfaces, focusedSurface: newValue)
            }
        }
    }

    var rootView: NSView {
        switch content {
        case .terminal(let root, _, _):
            return root
        case .smart(let panel):
            return panel
        }
    }

    var isTerminal: Bool {
        if case .terminal = content { return true }
        return false
    }

    var persistedContext: TerminalContext? {
        switch content {
        case .terminal(_, let surfaces, let focusedSurface):
            return focusedSurface?.terminalContext ?? surfaces.first?.terminalContext ?? .local
        case .smart:
            return nil
        }
    }

    var visibleContext: TerminalContext? {
        switch content {
        case .terminal(_, let surfaces, let focusedSurface):
            return focusedSurface?.displayContext ?? surfaces.first?.displayContext ?? .local
        case .smart:
            return nil
        }
    }

    mutating func addSurface(_ surface: TerminalSurfaceView) {
        if case .terminal(let root, var surfaces, _) = content {
            surfaces.append(surface)
            content = .terminal(splitRoot: root, surfaces: surfaces, focusedSurface: surface)
        }
    }

    mutating func removeSurface(_ surface: TerminalSurfaceView) {
        if case .terminal(let root, var surfaces, let focused) = content {
            surfaces.removeAll { $0 === surface }
            let newFocus = (focused === surface) ? surfaces.last : focused
            content = .terminal(splitRoot: root, surfaces: surfaces, focusedSurface: newFocus)
        }
    }
}
