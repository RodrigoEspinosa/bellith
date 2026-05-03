import AppKit
import GhosttyKit
import os
import UniformTypeIdentifiers
import UserNotifications

@main
struct BellithApp {
    static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.regular)
        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    let dependencies: BellithDependencies
    private let updater = UpdaterController()
    var terminalApp: TerminalApp?
    var windows: [WindowEntry] = []
    private var newWindowObserver: NSObjectProtocol?
    private var appearanceObserver: NSObjectProtocol?
    private var terminalConfigFailureObserver: NSObjectProtocol?
    private var settingsObserver: NSObjectProtocol?
    private var themeMenu = NSMenu(title: "Theme")
    private var workspacesMenu = NSMenu(title: "Workspaces")
    private var workspaceStoreObserver: NSObjectProtocol?

    struct WindowEntry {
        let window: TerminalWindow
        let container: TerminalContainerView
    }

    private func entry(forWindowID id: UUID) -> WindowEntry? {
        windows.first { $0.window.tabDragIdentifier == id }
    }

    /// The key (focused) window's container, or the most recent one.
    private var activeEntry: WindowEntry? {
        if let keyWindow = NSApp.keyWindow as? TerminalWindow {
            return windows.first { $0.window === keyWindow }
        }
        return windows.last
    }

    override init() {
        self.dependencies = .live
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let argc: UInt = 0
        let initResult = ghostty_init(argc, nil)
        guard initResult == GHOSTTY_SUCCESS else {
            presentStartupFailure(
                title: "Bellith Could Not Start",
                message: "Ghostty failed to initialize.",
                informativeText: "Bellith could not start its terminal runtime."
            )
            return
        }

        terminalConfigFailureObserver = NotificationCenter.default.addObserver(
            forName: .terminalConfigDidFail, object: nil, queue: .main
        ) { [weak self] notification in
            guard let error = notification.object as? TerminalConfigError else { return }
            self?.presentTerminalConfigError(error)
        }

        let config = TerminalConfig()
        guard config.config != nil else {
            NSApp.terminate(nil)
            return
        }

        let app = TerminalApp(config: config)
        guard app.app != nil else {
            presentStartupFailure(
                title: "Bellith Could Not Start",
                message: "Ghostty failed to create the terminal app.",
                informativeText: "Bellith could not create its terminal runtime."
            )
            return
        }
        self.terminalApp = app

        app.onAction = { [weak self] target, action in
            self?.handleAction(target: target, action: action) ?? false
        }

        applyResolvedAppearanceAndTheme()

        // Observe system appearance changes to switch themes
        appearanceObserver = DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name("AppleInterfaceThemeChangedNotification"),
            object: nil, queue: .main
        ) { [weak self] _ in
            self?.handleSystemAppearanceChanged()
        }

        // Observe "Increase Contrast" accessibility toggle so we can promote
        // to/from the high-contrast theme variant at runtime.
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(handleAccessibilityDisplayOptionsChanged),
            name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
            object: nil
        )

        // Request notification permission
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }

        settingsObserver = NotificationCenter.default.addObserver(
            forName: BellithSettings.didChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.setupMenus()
            self?.applyResolvedAppearanceAndTheme()
        }

        // Listen for new window requests
        newWindowObserver = NotificationCenter.default.addObserver(forName: .bellithCreateNewWindow, object: nil, queue: .main) { [weak self] notification in
            let request = notification.object as? WindowLaunchRequest
            self?.createWindow(
                session: request?.session,
                initialWorkingDirectory: request?.initialWorkingDirectory
            )
        }

        // Setup quick terminal (visor)
        QuickTerminalController.shared.setup(terminalApp: app, dependencies: dependencies)

        // Try to restore previous session(s)
        if !restoreSavedWindows() {
            createWindow()
        }
        setupMenus()

        workspaceStoreObserver = NotificationCenter.default.addObserver(
            forName: WorkspaceStore.didChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.rebuildWorkspacesMenu()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Save all window sessions if enabled
        if dependencies.settings.restoreSession {
            let savedWindows = windows.map {
                WindowSessionState(
                    session: $0.container.saveSession(),
                    frameDescriptor: NSStringFromRect($0.window.frame)
                )
            }

            if let data = try? JSONEncoder().encode(savedWindows) {
                UserDefaults.standard.set(data, forKey: "savedWindowSessions")
            }

            let allSessions = savedWindows.compactMap { try? JSONEncoder().encode($0.session) }
            if let firstData = allSessions.first {
                // Primary session for backward compat
                UserDefaults.standard.set(firstData, forKey: "savedSession")
            }
            if let allData = try? JSONEncoder().encode(allSessions.map { $0.base64EncodedString() }) {
                UserDefaults.standard.set(allData, forKey: "savedAllSessions")
            }
        }

        // Clean up observers
        if let obs = appearanceObserver {
            DistributedNotificationCenter.default().removeObserver(obs)
            appearanceObserver = nil
        }
        if let obs = newWindowObserver {
            NotificationCenter.default.removeObserver(obs)
            newWindowObserver = nil
        }
        if let obs = terminalConfigFailureObserver {
            NotificationCenter.default.removeObserver(obs)
            terminalConfigFailureObserver = nil
        }
        if let obs = settingsObserver {
            NotificationCenter.default.removeObserver(obs)
            settingsObserver = nil
        }
        if let obs = workspaceStoreObserver {
            NotificationCenter.default.removeObserver(obs)
            workspaceStoreObserver = nil
        }

        // Tear down all windows
        // Clean up quick terminal
        QuickTerminalController.shared.cleanup()
    }

    @discardableResult
    private func createWindow(
        session: SessionState? = nil,
        initialWorkingDirectory: String? = nil,
        frameDescriptor: String? = nil,
        createInitialTab: Bool = true,
        orderFront: Bool = true,
        dropScreenPoint: NSPoint? = nil
    ) -> WindowEntry? {
        guard let terminalApp else { return nil }

        let window = TerminalWindow(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 600),
            styleMask: [],
            backing: .buffered,
            defer: false,
            settings: dependencies.settings
        )
        if let frameDescriptor {
            let restoredFrame = NSRectFromString(frameDescriptor)
            if restoredFrame.width > 0, restoredFrame.height > 0 {
                window.setFrame(restoredFrame, display: false)
            } else {
                window.center()
            }
        } else if let dropScreenPoint {
            position(window, around: dropScreenPoint)
        } else {
            window.center()
        }
        window.isReleasedWhenClosed = false
        window.delegate = self

        let container = TerminalContainerView(
            terminalApp: terminalApp,
            createInitialTab: createInitialTab,
            dependencies: dependencies
        )
        if dependencies.settings.useRebrandShell {
            // Rebrand path: hand off chrome to `RebrandShellView`, which hosts
            // the legacy container with its own title bar / rail / status bar
            // suppressed. Set as the window's content view directly — no
            // BackdropView in the rebrand path because the shell paints its
            // own background.
            let shell = RebrandShellView(container: container)
            window.contentView = shell
        } else {
            let backdrop = BackdropView(container: container)
            window.contentView = backdrop
        }

        let entry = WindowEntry(window: window, container: container)
        windows.append(entry)

        if let session, !session.tabs.isEmpty {
            container.restoreSession(session)
        } else if let initialWorkingDirectory, !initialWorkingDirectory.isEmpty {
            container.openWorkingDirectory(initialWorkingDirectory)
            container.openReferencePaneLayoutIfNeeded()
        } else if createInitialTab {
            container.openReferencePaneLayoutIfNeeded()
        }

        window.makeFirstResponder(container.activeSurface ?? container)
        if orderFront {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate()
        }
        return entry
    }

    private func position(_ window: NSWindow, around screenPoint: NSPoint) {
        let frame = window.frame
        let visibleFrame = window.screen?.visibleFrame
            ?? NSScreen.screens.first(where: { NSMouseInRect(screenPoint, $0.frame, false) })?.visibleFrame
            ?? NSScreen.main?.visibleFrame
            ?? NSRect(x: 0, y: 0, width: 1440, height: 900)

        let targetOrigin = NSPoint(
            x: screenPoint.x - frame.width / 2,
            y: screenPoint.y - frame.height + 28
        )
        let clampedOrigin = NSPoint(
            x: min(max(targetOrigin.x, visibleFrame.minX), visibleFrame.maxX - frame.width),
            y: min(max(targetOrigin.y, visibleFrame.minY), visibleFrame.maxY - frame.height)
        )
        window.setFrameOrigin(clampedOrigin)
    }

    func moveTab(
        _ tabID: UUID,
        fromWindowWithID sourceWindowID: UUID,
        toWindowWithID destinationWindowID: UUID,
        insertionIndex: Int
    ) -> Bool {
        guard sourceWindowID != destinationWindowID,
              let sourceEntry = entry(forWindowID: sourceWindowID),
              let destinationEntry = entry(forWindowID: destinationWindowID),
              let entry = sourceEntry.container.detachTab(withID: tabID) else {
            return false
        }

        destinationEntry.container.insertTransferredTab(entry, at: insertionIndex)
        destinationEntry.window.makeFirstResponder(destinationEntry.container.activeSurface ?? destinationEntry.container)
        destinationEntry.window.makeKeyAndOrderFront(nil)
        NSApp.activate()
        return true
    }

    func tearOffTab(
        _ tabID: UUID,
        fromWindowWithID sourceWindowID: UUID,
        dropScreenPoint: NSPoint
    ) -> Bool {
        guard entry(forWindowID: sourceWindowID) != nil,
              let destinationEntry = createWindow(
                  createInitialTab: false,
                  orderFront: false,
                  dropScreenPoint: dropScreenPoint
              ) else {
            return false
        }

        guard let sourceEntry = entry(forWindowID: sourceWindowID),
              let entry = sourceEntry.container.detachTab(withID: tabID) else {
            destinationEntry.window.close()
            return false
        }

        destinationEntry.container.insertTransferredTab(entry, at: 0)
        position(destinationEntry.window, around: dropScreenPoint)
        destinationEntry.window.makeFirstResponder(destinationEntry.container.activeSurface ?? destinationEntry.container)
        destinationEntry.window.makeKeyAndOrderFront(nil)
        NSApp.activate()
        return true
    }

    private func restoreSavedWindows() -> Bool {
        guard dependencies.settings.restoreSession else { return false }

        if let data = UserDefaults.standard.data(forKey: "savedWindowSessions"),
           let savedWindows = try? JSONDecoder().decode([WindowSessionState].self, from: data),
           !savedWindows.isEmpty {
            for savedWindow in savedWindows where !savedWindow.session.tabs.isEmpty {
                createWindow(session: savedWindow.session, frameDescriptor: savedWindow.frameDescriptor)
            }
            return !windows.isEmpty
        }

        if let data = UserDefaults.standard.data(forKey: "savedAllSessions"),
           let encodedSessions = try? JSONDecoder().decode([String].self, from: data) {
            var restoredAny = false
            for encoded in encodedSessions {
                guard let sessionData = Data(base64Encoded: encoded),
                      let session = try? JSONDecoder().decode(SessionState.self, from: sessionData),
                      !session.tabs.isEmpty else { continue }
                createWindow(session: session)
                restoredAny = true
            }
            if restoredAny { return true }
        }

        if let data = UserDefaults.standard.data(forKey: "savedSession"),
           let state = try? JSONDecoder().decode(SessionState.self, from: data),
           !state.tabs.isEmpty {
            createWindow(session: state)
            return true
        }

        return false
    }

    /// Find the container that owns a given surface view.
    private func container(for surfaceView: TerminalSurfaceView) -> TerminalContainerView? {
        // Check the surface's window first for O(1) lookup
        if let window = surfaceView.window as? TerminalWindow,
           let entry = windows.first(where: { $0.window === window }) {
            return entry.container
        }
        return activeEntry?.container
    }

    private func surfaceView(for target: ghostty_target_s) -> TerminalSurfaceView? {
        guard target.tag == GHOSTTY_TARGET_SURFACE,
              let surfaceUD = ghostty_surface_userdata(target.target.surface) else {
            return nil
        }

        return Unmanaged<TerminalSurfaceView>.fromOpaque(surfaceUD).takeUnretainedValue()
    }

    private func handleRingBell(target: ghostty_target_s) {
        switch dependencies.settings.bellMode {
        case "none":
            return
        case "visual":
            let surface = surfaceView(for: target)
            let window = surface?.window ?? activeEntry?.window
            window?.flashForVisualBell()
        case "bounce":
            NSApp.requestUserAttention(.criticalRequest)
        default:
            NSSound.beep()
        }
    }

    private func shouldNotifyForCompletedCommand(
        on surfaceView: TerminalSurfaceView?,
        durationSeconds: Double
    ) -> Bool {
        guard dependencies.settings.commandCompletionNotificationsEnabled else { return false }
        guard dependencies.settings.shellIntegrationEnabled else { return false }
        guard durationSeconds >= Double(dependencies.settings.commandCompletionNotificationThreshold) else { return false }

        guard let surfaceView,
              let container = container(for: surfaceView) else {
            return !NSApp.isActive
        }

        let appIsFocused = NSApp.isActive
        let surfaceIsVisible = container.isSurfaceVisible(surfaceView)
        let windowIsKey = surfaceView.window?.isKeyWindow ?? false
        return !appIsFocused || !windowIsKey || !surfaceIsVisible
    }

    private func notifyCompletedCommand(on surfaceView: TerminalSurfaceView?, durationSeconds: Double, exitCode: Int16) {
        let content = UNMutableNotificationContent()
        let tabTitle = surfaceView.flatMap { container(for: $0)?.tabTitle(for: $0) }
        let processText = surfaceView?.lastForegroundPresentation?.text
        let titleParts = [processText, tabTitle].compactMap { $0 }.filter { !$0.isEmpty }
        content.title = titleParts.first.map { "\($0) finished" } ?? "Command finished"

        if exitCode == 0 {
            content.body = String(format: "Completed successfully in %.0fs", durationSeconds)
        } else if exitCode > 0 {
            content.body = String(format: "Exited with code %d after %.0fs", exitCode, durationSeconds)
        } else {
            content.body = String(format: "Completed in %.0fs", durationSeconds)
        }

        if let tabTitle, !tabTitle.isEmpty, titleParts.count <= 1 {
            content.subtitle = tabTitle
        }

        content.sound = .default
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    private func setupMenus() {
        // `workspacesMenu` is a stored property, so it still claims a
        // supermenu reference from the previous main-menu tree after the
        // first pass. `setSubmenu:` throws `NSInternalInconsistencyException`
        // if we attach it to a new item while it already has a parent — give
        // it a fresh instance each rebuild. `themeMenu` is reassigned below
        // for the same reason.
        workspacesMenu = NSMenu(title: "Workspaces")

        let mainMenu = NSMenu()

        // App menu
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "About Bellith", action: #selector(handleAbout), keyEquivalent: "")
        if updater.isAvailable {
            let checkForUpdatesItem = NSMenuItem(title: "Check for Updates…", action: updater.menuAction, keyEquivalent: "")
            checkForUpdatesItem.target = updater.menuTarget
            appMenu.addItem(checkForUpdatesItem)
        }
        appMenu.addItem(.separator())
        appMenu.addItem(configuredMenuItem(title: "Settings…", action: #selector(handlePreferences), shortcutID: "preferences"))
        appMenu.addItem(configuredMenuItem(title: "Open settings.json", action: #selector(handleOpenSettingsFile)))
        appMenu.addItem(.separator())
        let servicesItem = NSMenuItem(title: "Services", action: nil, keyEquivalent: "")
        let servicesMenu = NSMenu(title: "Services")
        NSApp.servicesMenu = servicesMenu
        servicesItem.submenu = servicesMenu
        appMenu.addItem(servicesItem)
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Hide Bellith", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        let hideOthers = NSMenuItem(title: "Hide Others", action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h")
        hideOthers.keyEquivalentModifierMask = [.command, .option]
        appMenu.addItem(hideOthers)
        appMenu.addItem(withTitle: "Show All", action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit Bellith", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        let appMenuItem = NSMenuItem()
        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)

        // File menu
        let shellMenu = NSMenu(title: "File")
        shellMenu.addItem(configuredMenuItem(title: "New Tab", action: #selector(handleNewTab), shortcutID: "newTab"))
        shellMenu.addItem(configuredMenuItem(title: "New Window", action: #selector(handleNewWindow), shortcutID: "newWindow"))
        shellMenu.addItem(configuredMenuItem(title: "Connect Host…", action: #selector(handleConnectHost)))
        if dependencies.settings.legacyPaneSupport || dependencies.settings.useRebrandShell {
            shellMenu.addItem(.separator())
            shellMenu.addItem(configuredMenuItem(title: "Split Right", action: #selector(handleSplitRight), shortcutID: "splitRight"))
            shellMenu.addItem(configuredMenuItem(title: "Split Down", action: #selector(handleSplitDown), shortcutID: "splitDown"))
            shellMenu.addItem(.separator())
            shellMenu.addItem(configuredMenuItem(title: "Close Pane", action: #selector(handleClosePane), shortcutID: "closePane"))
        }
        shellMenu.addItem(.separator())
        rebuildWorkspacesMenu()
        let workspacesItem = NSMenuItem(title: "Workspaces", action: nil, keyEquivalent: "")
        workspacesItem.submenu = workspacesMenu
        shellMenu.addItem(workspacesItem)
        shellMenu.addItem(.separator())
        shellMenu.addItem(configuredMenuItem(title: "Close Tab", action: #selector(handleCloseTab), shortcutID: "closeTab"))
        shellMenu.addItem(configuredMenuItem(title: "Close Window", action: #selector(handleCloseWindow)))
        let shellMenuItem = NSMenuItem()
        shellMenuItem.submenu = shellMenu
        mainMenu.addItem(shellMenuItem)

        // Edit menu
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(configuredMenuItem(title: "Copy", action: #selector(handleCopy), shortcutID: "copy"))
        editMenu.addItem(configuredMenuItem(title: "Paste", action: #selector(handlePaste), shortcutID: "paste"))
        editMenu.addItem(configuredMenuItem(title: "Select All", action: #selector(handleSelectAll), shortcutID: "selectAll"))
        editMenu.addItem(.separator())
        editMenu.addItem(configuredMenuItem(title: "Find…", action: #selector(handleFind), shortcutID: "search"))
        editMenu.addItem(.separator())
        editMenu.addItem(configuredMenuItem(title: "Clear Buffer", action: #selector(handleClearBuffer), shortcutID: "clearBuffer"))
        let editMenuItem = NSMenuItem()
        editMenuItem.submenu = editMenu
        mainMenu.addItem(editMenuItem)

        // Tab menu
        let tabMenu = NSMenu(title: "Tab")
        tabMenu.addItem(configuredMenuItem(title: "Next Tab", action: #selector(handleNextTab), shortcutID: "nextTab"))
        tabMenu.addItem(configuredMenuItem(title: "Previous Tab", action: #selector(handlePrevTab), shortcutID: "prevTab"))
        tabMenu.addItem(.separator())
        tabMenu.addItem(configuredMenuItem(title: "Rename Tab…", action: #selector(handleRenameTab), shortcutID: "renameTab"))
        tabMenu.addItem(configuredMenuItem(title: "Reopen Closed Tab", action: #selector(handleReopenTab), shortcutID: "reopenTab"))
        let tabMenuItem = NSMenuItem()
        tabMenuItem.submenu = tabMenu
        mainMenu.addItem(tabMenuItem)

        // View menu
        let viewMenu = NSMenu(title: "View")
        viewMenu.addItem(configuredMenuItem(title: "Toggle Sidebar", action: #selector(handleToggleSidebar), shortcutID: "toggleSidebar"))
        viewMenu.addItem(configuredMenuItem(title: "Command Palette", action: #selector(handleTogglePalette), shortcutID: "commandPalette"))
        let statusBarItem = NSMenuItem(title: "Show Status Bar", action: #selector(handleToggleStatusBar), keyEquivalent: "")
        statusBarItem.target = self
        viewMenu.addItem(statusBarItem)
        viewMenu.addItem(.separator())
        viewMenu.addItem(configuredMenuItem(title: "Increase Font Size", action: #selector(handleFontBigger), shortcutID: "fontSizeUp"))
        viewMenu.addItem(configuredMenuItem(title: "Decrease Font Size", action: #selector(handleFontSmaller), shortcutID: "fontSizeDown"))
        viewMenu.addItem(configuredMenuItem(title: "Reset Font Size", action: #selector(handleFontReset), shortcutID: "fontSizeReset"))
        viewMenu.addItem(.separator())
        viewMenu.addItem(configuredMenuItem(title: "Toggle Full Screen", action: #selector(handleFullscreen), shortcutID: "toggleFullscreen"))
        viewMenu.addItem(configuredMenuItem(title: "Reload Config", action: #selector(handleReloadConfig), shortcutID: "reloadConfig"))
        viewMenu.addItem(.separator())

        // Theme submenu
        themeMenu = NSMenu(title: "Theme")
        themeMenu.delegate = self
        rebuildThemeMenu()
        let themeItem = NSMenuItem(title: "Theme", action: nil, keyEquivalent: "")
        themeItem.submenu = themeMenu
        viewMenu.addItem(themeItem)
        viewMenu.addItem(configuredMenuItem(title: "Import iTerm2 Theme…", action: #selector(handleImportITermColors)))

        let viewMenuItem = NSMenuItem()
        viewMenuItem.submenu = viewMenu
        mainMenu.addItem(viewMenuItem)

        // Tools menu — built-in smart panel plugins
        let toolsMenu = NSMenu(title: "Tools")
        for plugin in dependencies.smartPanelRegistry.allPlugins {
            let item = NSMenuItem(title: plugin.title, action: #selector(handleSmartToolMenuItem(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = plugin.id
            toolsMenu.addItem(item)
        }
        let toolsMenuItem = NSMenuItem()
        toolsMenuItem.submenu = toolsMenu
        mainMenu.addItem(toolsMenuItem)

        // Window menu
        let windowMenu = NSMenu(title: "Window")
        windowMenu.addItem(withTitle: "Minimize", action: #selector(NSWindow.miniaturize(_:)), keyEquivalent: "m")
        windowMenu.addItem(withTitle: "Zoom", action: #selector(NSWindow.zoom(_:)), keyEquivalent: "")
        windowMenu.addItem(.separator())
        windowMenu.addItem(withTitle: "Bring All to Front", action: #selector(NSApplication.arrangeInFront(_:)), keyEquivalent: "")
        let windowMenuItem = NSMenuItem()
        windowMenuItem.submenu = windowMenu
        mainMenu.addItem(windowMenuItem)
        NSApp.windowsMenu = windowMenu

        // Help menu
        let helpMenu = NSMenu(title: "Help")
        helpMenu.addItem(configuredMenuItem(title: "Keyboard Shortcuts", action: #selector(handleShowKeyboardShortcuts), shortcutID: "showKeyboardShortcuts"))
        helpMenu.addItem(configuredMenuItem(title: "Install CLI Helper…", action: #selector(handleInstallCLI)))
        helpMenu.addItem(configuredMenuItem(title: "Bellith Help", action: #selector(handleHelp)))
        let helpMenuItem = NSMenuItem()
        helpMenuItem.submenu = helpMenu
        mainMenu.addItem(helpMenuItem)
        NSApp.helpMenu = helpMenu

        NSApp.mainMenu = mainMenu
    }

    private func configuredMenuItem(
        title: String,
        action: Selector,
        shortcutID: String? = nil
    ) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        if let shortcutID {
            applyShortcut(shortcutID, to: item)
        }
        return item
    }

    private func applyShortcut(_ shortcutID: String, to item: NSMenuItem) {
        guard let shortcut = dependencies.settings.shortcut(for: shortcutID) else {
            item.keyEquivalent = ""
            item.keyEquivalentModifierMask = []
            return
        }
        item.keyEquivalent = shortcut.menuKeyEquivalent
        item.keyEquivalentModifierMask = shortcut.modifierFlags
    }

    private func rebuildWorkspacesMenu() {
        workspacesMenu.removeAllItems()
        let workspaces = WorkspaceStore.shared.workspaces
        if workspaces.isEmpty {
            let empty = NSMenuItem(title: "No Saved Workspaces", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            workspacesMenu.addItem(empty)
        } else {
            for workspace in workspaces {
                let item = NSMenuItem(
                    title: workspace.name,
                    action: #selector(handleOpenWorkspace(_:)),
                    keyEquivalent: ""
                )
                item.target = self
                item.representedObject = workspace.id
                workspacesMenu.addItem(item)
            }
        }
        workspacesMenu.addItem(.separator())
        let saveItem = NSMenuItem(
            title: "Save Current as Workspace…",
            action: #selector(handleSaveWorkspace),
            keyEquivalent: ""
        )
        saveItem.target = self
        workspacesMenu.addItem(saveItem)
    }

    // MARK: - Menu Actions

    @objc private func handleOpenWorkspace(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? UUID,
              let workspace = WorkspaceStore.shared.workspace(id: id) else { return }
        if let container = activeEntry?.container {
            container.restoreSession(workspace.session)
        } else {
            createWindow(session: workspace.session)
        }
    }

    @objc private func handleSaveWorkspace() {
        activeEntry?.container.promptSaveWorkspace()
    }

    @objc private func handleCopy() { activeEntry?.container.copySelection() }
    @objc private func handlePaste() { activeEntry?.container.pasteClipboard() }
    @objc private func handleSelectAll() {
        guard let surface = activeEntry?.container.activeSurface?.surface else { return }
        let action = "select_all"
        action.withCString { ptr in
            _ = ghostty_surface_binding_action(surface, ptr, UInt(action.utf8.count))
        }
    }
    @objc private func handleFind() { activeEntry?.container.showSearch() }
    @objc private func handleClearBuffer() { activeEntry?.container.clearBuffer() }
    @objc private func handleNewTab() { activeEntry?.container.createTab() }
    @objc private func handleCloseTab() { activeEntry?.container.closeFocusedPaneOrTab() }
    @objc private func handleCloseWindow() { NSApp.keyWindow?.close() }
    @objc private func handleClosePane() { activeEntry?.container.closePane() }
    @objc private func handleNewWindow() { createWindow() }
    @objc private func handleConnectHost() {
        let profiles = SSHProfileStore.shared.profiles
        if profiles.count == 1, let profile = profiles.first {
            activeEntry?.container.connectSSHProfile(id: profile.id)
        } else {
            SettingsNavigation.open(
                selecting: "ssh",
                in: activeEntry?.container,
                settings: dependencies.settings,
                preferencesWindowController: dependencies.preferencesWindowController,
                createContainer: { [weak self] in self?.createWindow()?.container }
            )
        }
    }
    @objc private func handleSplitRight() { activeEntry?.container.splitPane(direction: .vertical) }
    @objc private func handleSplitDown() { activeEntry?.container.splitPane(direction: .horizontal) }
    @objc private func handleReopenTab() { activeEntry?.container.reopenClosedTab() }
    @objc private func handleRenameTab() { activeEntry?.container.promptRenameTab() }
    @objc private func handleNextTab() { activeEntry?.container.advanceToNextTerminalTab() }
    @objc private func handlePrevTab() { activeEntry?.container.advanceToPreviousTerminalTab() }
    @objc private func handleToggleSidebar() { activeEntry?.container.sidebar.toggle() }
    @objc private func handleTogglePalette() { activeEntry?.container.toggleCommandPalette() }
    @objc private func handleShowKeyboardShortcuts() { activeEntry?.container.toggleShortcutCheatSheet() }
    @objc func handleToggleStatusBar() { dependencies.settings.showStatusBar.toggle() }

    @objc private func handleFontBigger() { activeEntry?.container.adjustFontSizePublic(delta: 1) }
    @objc private func handleFontSmaller() { activeEntry?.container.adjustFontSizePublic(delta: -1) }
    @objc private func handleFontReset() { activeEntry?.container.resetFontSizePublic() }
    @objc private func handleFullscreen() { NSApp.keyWindow?.toggleFullScreen(nil) }
    @objc private func handleReloadConfig() { activeEntry?.container.reloadConfig() }
    @objc private func handlePreferences() {
        SettingsNavigation.open(
            in: activeEntry?.container,
            settings: dependencies.settings,
            preferencesWindowController: dependencies.preferencesWindowController,
            createContainer: { [weak self] in self?.createWindow()?.container }
        )
    }
    @objc private func handleOpenSettingsFile() {
        SettingsNavigation.openSettingsFile(
            in: activeEntry?.container,
            settings: dependencies.settings,
            preferencesWindowController: dependencies.preferencesWindowController,
            createContainer: { [weak self] in self?.createWindow()?.container }
        )
    }
    @objc private func handleAbout() {
        NSApp.orderFrontStandardAboutPanel(options: BellithBranding.aboutPanelOptions())
        NSApp.activate(ignoringOtherApps: true)
    }
    @objc private func handleImportITermColors() {
        let panel = NSOpenPanel()
        panel.title = "Import iTerm2 Theme"
        panel.prompt = "Import"
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        if let type = UTType(filenameExtension: "itermcolors") {
            panel.allowedContentTypes = [type]
        }
        guard panel.runModal() == .OK else { return }

        var imported: [String] = []
        var failures: [(URL, Error)] = []
        for url in panel.urls {
            do {
                let def = try ITermColorsImporter.importFile(url: url)
                imported.append(def.name)
            } catch {
                failures.append((url, error))
            }
        }

        let alert = NSAlert()
        if !imported.isEmpty && failures.isEmpty {
            alert.messageText = "Imported \(imported.count) theme\(imported.count == 1 ? "" : "s")"
            alert.informativeText = imported.joined(separator: ", ") + "\n\nOpen the Theme menu to apply."
            alert.alertStyle = .informational
        } else if imported.isEmpty {
            alert.messageText = "Import failed"
            alert.informativeText = failures.map { "\($0.0.lastPathComponent): \($0.1.localizedDescription)" }.joined(separator: "\n")
            alert.alertStyle = .warning
        } else {
            alert.messageText = "Imported \(imported.count), \(failures.count) failed"
            alert.informativeText = "Imported: \(imported.joined(separator: ", "))\n\nFailed:\n" +
                failures.map { "\($0.0.lastPathComponent): \($0.1.localizedDescription)" }.joined(separator: "\n")
            alert.alertStyle = .warning
        }
        alert.runModal()

        // Rebuild theme menu so newly-imported themes appear immediately.
        rebuildThemeMenu()
    }

    @objc private func handleHelp() {
        // Open help/documentation — for now open the custom themes folder as a basic help action
        guard let url = BellithBranding.repoURL else { return }
        NSWorkspace.shared.open(url)
    }

    // MARK: - CLI Helper

    @objc private func handleInstallCLI() {
        guard let source = Bundle.main.resourceURL?.appendingPathComponent("bellith") else {
            presentCLIAlert(style: .warning, title: "CLI Helper Not Found",
                            text: "The bellith executable was not embedded in this build.")
            return
        }
        guard FileManager.default.fileExists(atPath: source.path) else {
            presentCLIAlert(style: .warning, title: "CLI Helper Not Found",
                            text: "Expected CLI at \(source.path).")
            return
        }

        let targetDir = "/usr/local/bin"
        let targetPath = targetDir + "/bellith"

        let confirm = NSAlert()
        confirm.messageText = "Install bellith CLI?"
        confirm.informativeText = "A symlink will be created at \(targetPath) pointing to the CLI inside Bellith.app. You may be prompted for your administrator password if \(targetDir) is not writable."
        confirm.alertStyle = .informational
        confirm.addButton(withTitle: "Install")
        confirm.addButton(withTitle: "Cancel")
        guard confirm.runModal() == .alertFirstButtonReturn else { return }

        let fm = FileManager.default
        var isDir: ObjCBool = false
        let dirExists = fm.fileExists(atPath: targetDir, isDirectory: &isDir) && isDir.boolValue

        if dirExists && fm.isWritableFile(atPath: targetDir) {
            do {
                if fm.fileExists(atPath: targetPath) {
                    try fm.removeItem(atPath: targetPath)
                }
                try fm.createSymbolicLink(atPath: targetPath, withDestinationPath: source.path)
                presentCLIAlert(style: .informational, title: "CLI Installed",
                                text: "You can now run `bellith` from any shell. Try `bellith --help`.")
                return
            } catch {
                presentCLIAlert(style: .warning, title: "Install Failed",
                                text: "Could not symlink into \(targetDir): \(error.localizedDescription)\n\nYou can run this command manually:\n\n  sudo ln -sf \(shellEscape(source.path)) \(targetPath)")
                return
            }
        }

        // Fall back to instructing the user to run a shell command manually.
        presentCLIAlert(
            style: .informational,
            title: "Manual Install",
            text: "\(targetDir) is not writable by Bellith. Run this in a terminal to finish installing:\n\n  sudo mkdir -p \(targetDir) && sudo ln -sf \(shellEscape(source.path)) \(targetPath)"
        )
    }

    private func presentCLIAlert(style: NSAlert.Style, title: String, text: String) {
        let alert = NSAlert()
        alert.alertStyle = style
        alert.messageText = title
        alert.informativeText = text
        alert.runModal()
    }

    private func shellEscape(_ path: String) -> String {
        "'" + path.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    // MARK: - URL Scheme

    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            handleBellithURL(url)
        }
    }

    private func handleBellithURL(_ url: URL) {
        guard url.scheme == "bellith" else { return }
        let host = url.host ?? ""
        let params: [String: String] = {
            let comps = URLComponents(url: url, resolvingAgainstBaseURL: false)
            var dict: [String: String] = [:]
            for item in comps?.queryItems ?? [] {
                if let value = item.value { dict[item.name] = value }
            }
            return dict
        }()

        // Ensure a window exists before we try to route commands to one.
        if windows.isEmpty { createWindow() }
        guard let container = activeEntry?.container else { return }
        activeEntry?.window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        switch host {
        case "open":
            let path = params["path"].flatMap { $0.isEmpty ? nil : $0 }
            container.createTab(initialWorkingDirectory: path)

        case "split":
            let direction: SplitPaneView.Orientation = (params["direction"] == "down") ? .horizontal : .vertical
            container.splitPane(direction: direction)
            if let cmd = params["cmd"], !cmd.isEmpty {
                container.runInActiveSurface(cmd)
            }

        case "ssh":
            guard let name = params["profile"], !name.isEmpty else { return }
            let lowered = name.lowercased()
            let match = SSHProfileStore.shared.profiles.first { profile in
                profile.displayName.lowercased() == lowered || profile.name.lowercased() == lowered
            }
            if let match {
                container.connectSSHProfile(id: match.id)
            } else {
                presentCLIAlert(style: .warning, title: "SSH Profile Not Found",
                                text: "No saved SSH profile matches '\(name)'.")
            }

        default:
            break
        }
    }

    // Smart panel plugin actions
    @objc private func handleSmartToolMenuItem(_ sender: NSMenuItem) {
        guard let pluginID = sender.representedObject as? String else { return }
        activeEntry?.container.createSmartTab(pluginID: pluginID)
    }
    @objc private func handleThemeSelection(_ sender: NSMenuItem) {
        guard let theme = sender.representedObject as? ThemeColors else { return }
        if theme.isLight {
            dependencies.settings.lightThemeName = theme.name
        } else {
            dependencies.settings.darkThemeName = theme.name
        }
        applyResolvedAppearanceAndTheme()
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        if menu === themeMenu { rebuildThemeMenu() }
    }

    private func rebuildThemeMenu() {
        themeMenu.removeAllItems()
        let settings = dependencies.settings
        let darkHeader = NSMenuItem(title: "Dark", action: nil, keyEquivalent: "")
        darkHeader.isEnabled = false
        themeMenu.addItem(darkHeader)
        for theme in ThemeColors.allThemes where !theme.isLight {
            let item = NSMenuItem(title: "  " + theme.name, action: #selector(handleThemeSelection(_:)), keyEquivalent: "")
            item.representedObject = theme
            item.state = theme.name == settings.darkThemeName ? .on : .off
            themeMenu.addItem(item)
        }
        themeMenu.addItem(.separator())
        let lightHeader = NSMenuItem(title: "Light", action: nil, keyEquivalent: "")
        lightHeader.isEnabled = false
        themeMenu.addItem(lightHeader)
        for theme in ThemeColors.allThemes where theme.isLight {
            let item = NSMenuItem(title: "  " + theme.name, action: #selector(handleThemeSelection(_:)), keyEquivalent: "")
            item.representedObject = theme
            item.state = theme.name == settings.lightThemeName ? .on : .off
            themeMenu.addItem(item)
        }
    }

    @objc private func handleAccessibilityDisplayOptionsChanged() {
        DispatchQueue.main.async { [weak self] in
            self?.applyResolvedAppearanceAndTheme()
        }
    }

    private func handleSystemAppearanceChanged() {
        guard dependencies.settings.appearanceMode == .system else { return }
        // Small delay to let system appearance notifications settle.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            self?.applyResolvedAppearanceAndTheme()
        }
    }

    private func applyResolvedAppearanceAndTheme() {
        let resolvedTheme = dependencies.settings.resolvedTheme
        dependencies.themeManager.apply(resolvedTheme)

        switch dependencies.settings.appearanceMode {
        case .system:
            NSApp.appearance = nil
        case .dark:
            NSApp.appearance = NSAppearance(named: .darkAqua)
        case .light:
            NSApp.appearance = NSAppearance(named: .aqua)
        }

        terminalApp?.setColorScheme(dependencies.settings.resolvedIsDark ? GHOSTTY_COLOR_SCHEME_DARK : GHOSTTY_COLOR_SCHEME_LIGHT)

        let appearance = resolvedTheme.isLight ? NSAppearance(named: .aqua) : NSAppearance(named: .darkAqua)
        for entry in windows {
            entry.window.appearance = appearance
        }
    }

    private func presentTerminalConfigError(_ error: TerminalConfigError) {
        presentAlert(
            title: "Bellith Configuration Error",
            message: error.errorDescription ?? "Bellith could not load its configuration.",
            informativeText: error.failureReason
        )
    }

    private func presentStartupFailure(title: String, message: String, informativeText: String) {
        presentAlert(title: title, message: message, informativeText: informativeText, terminateAfterDismissal: true)
    }

    private func presentAlert(
        title: String,
        message: String,
        informativeText: String? = nil,
        terminateAfterDismissal: Bool = false
    ) {
        let alert = NSAlert()
        alert.alertStyle = .critical
        alert.messageText = title
        alert.informativeText = [message, informativeText].compactMap { $0 }.joined(separator: "\n\n")

        NSApp.activate(ignoringOtherApps: true)
        if let window = activeEntry?.window ?? NSApp.keyWindow {
            alert.beginSheetModal(for: window) { _ in
                if terminateAfterDismissal {
                    NSApp.terminate(nil)
                }
            }
        } else {
            _ = alert.runModal()
            if terminateAfterDismissal {
                NSApp.terminate(nil)
            }
        }
    }

    // MARK: - Ghostty Actions

    private func handleAction(target: ghostty_target_s, action: ghostty_action_s) -> Bool {
        switch action.tag {
        case GHOSTTY_ACTION_SET_TITLE:
            if let titlePtr = action.action.set_title.title {
                let title = String(cString: titlePtr)
                if let surfaceView = surfaceView(for: target) {
                    container(for: surfaceView)?.updateTabTitle(title, for: surfaceView)
                    // Update window title for Mission Control / Cmd+Tab
                    surfaceView.window?.title = title
                }
            }
            return true

        case GHOSTTY_ACTION_PWD:
            if let pwdPtr = action.action.pwd.pwd {
                let pwd = String(cString: pwdPtr)
                if let surfaceView = surfaceView(for: target) {
                    container(for: surfaceView)?.updateTabCwd(pwd, for: surfaceView)
                }
            }
            return true

        case GHOSTTY_ACTION_NEW_TAB:
            activeEntry?.container.createTab()
            return true

        case GHOSTTY_ACTION_NEW_WINDOW:
            createWindow()
            return true

        case GHOSTTY_ACTION_CLOSE_WINDOW:
            (NSApp.keyWindow as? TerminalWindow)?.close()
            return true

        case GHOSTTY_ACTION_RENDER:
            activeEntry?.container.activeSurface?.needsDisplay = true
            return true

        case GHOSTTY_ACTION_MOUSE_SHAPE:
            guard mouseActionCanAffectCursor(target: target) else { return true }
            let shape = action.action.mouse_shape
            switch shape {
            case GHOSTTY_MOUSE_SHAPE_DEFAULT: NSCursor.arrow.set()
            case GHOSTTY_MOUSE_SHAPE_TEXT: NSCursor.iBeam.set()
            case GHOSTTY_MOUSE_SHAPE_POINTER: NSCursor.pointingHand.set()
            case GHOSTTY_MOUSE_SHAPE_CROSSHAIR: NSCursor.crosshair.set()
            default: NSCursor.arrow.set()
            }
            return true

        case GHOSTTY_ACTION_MOUSE_VISIBILITY:
            guard mouseActionCanAffectCursor(target: target) else { return true }
            if action.action.mouse_visibility == GHOSTTY_MOUSE_HIDDEN {
                NSCursor.hide()
            } else {
                NSCursor.unhide()
            }
            return true

        case GHOSTTY_ACTION_SIZE_LIMIT:
            let limits = action.action.size_limit
            if limits.min_width > 0 && limits.min_height > 0 {
                let window = (NSApp.keyWindow as? TerminalWindow) ?? windows.last?.window
                window?.minSize = NSSize(width: CGFloat(limits.min_width),
                                         height: CGFloat(limits.min_height))
            }
            return true

        case GHOSTTY_ACTION_INITIAL_SIZE:
            let size = action.action.initial_size
            let window = (NSApp.keyWindow as? TerminalWindow) ?? windows.last?.window
            window?.setContentSize(NSSize(width: CGFloat(size.width),
                                          height: CGFloat(size.height)))
            window?.center()
            return true

        case GHOSTTY_ACTION_CELL_SIZE:
            let size = action.action.cell_size
            let window = (NSApp.keyWindow as? TerminalWindow) ?? windows.last?.window
            window?.contentResizeIncrements = NSSize(width: CGFloat(size.width),
                                                      height: CGFloat(size.height))
            return true

        case GHOSTTY_ACTION_OPEN_URL:
            if let urlPtr = action.action.open_url.url {
                let str = String(cString: urlPtr)
                _ = HyperlinkRouter.open(str)
            }
            return true

        case GHOSTTY_ACTION_RING_BELL:
            handleRingBell(target: target)
            return true

        case GHOSTTY_ACTION_MOUSE_OVER_LINK:
            return true

        case GHOSTTY_ACTION_TOGGLE_QUICK_TERMINAL:
            QuickTerminalController.shared.toggle()
            return true

        case GHOSTTY_ACTION_TOGGLE_FULLSCREEN:
            NSApp.keyWindow?.toggleFullScreen(nil)
            return true

        case GHOSTTY_ACTION_RELOAD_CONFIG:
            activeEntry?.container.reloadConfig()
            return true

        case GHOSTTY_ACTION_COMMAND_FINISHED:
            let info = action.action.command_finished
            let durationSec = Double(info.duration) / 1_000_000_000
            let surfaceView = surfaceView(for: target)
            if shouldNotifyForCompletedCommand(on: surfaceView, durationSeconds: durationSec) {
                notifyCompletedCommand(on: surfaceView, durationSeconds: durationSec, exitCode: info.exit_code)
            }
            if let surfaceView {
                surfaceView.recordCommandMark(exitCode: info.exit_code)
                if let container = container(for: surfaceView) {
                    container.handleCompletedCommand(on: surfaceView, exitCode: info.exit_code)
                }
            }
            return true

        case GHOSTTY_ACTION_DESKTOP_NOTIFICATION:
            let notif = action.action.desktop_notification
            let content = UNMutableNotificationContent()
            content.title = notif.title.map { String(cString: $0) } ?? "Bellith"
            content.body = notif.body.map { String(cString: $0) } ?? ""
            content.sound = .default
            let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
            UNUserNotificationCenter.current().add(request)
            return true

        case GHOSTTY_ACTION_SCROLLBAR:
            let bar = action.action.scrollbar
            if let surfaceView = surfaceView(for: target) {
                surfaceView.updateScrollbarState(
                    total: Int(bar.total),
                    offset: Int(bar.offset),
                    len: Int(bar.len)
                )
            }
            return true

        case GHOSTTY_ACTION_START_SEARCH:
            let needle: String?
            if let ptr = action.action.start_search.needle {
                needle = String(cString: ptr)
            } else {
                needle = nil
            }
            activeEntry?.container.showSearch(initialNeedle: needle)
            return true

        case GHOSTTY_ACTION_END_SEARCH:
            activeEntry?.container.hideSearch()
            if let surfaceView = surfaceView(for: target) {
                surfaceView.clearMinimapSearchSelection()
            }
            return true

        case GHOSTTY_ACTION_SEARCH_TOTAL:
            let total = Int(action.action.search_total.total)
            activeEntry?.container.updateSearchTotal(total)
            return true

        case GHOSTTY_ACTION_SEARCH_SELECTED:
            let selected = Int(action.action.search_selected.selected)
            activeEntry?.container.updateSearchSelected(selected)
            if let surfaceView = surfaceView(for: target) {
                surfaceView.updateMinimapSearchSelection()
            }
            return true

        default:
            return false
        }
    }

    private func mouseActionCanAffectCursor(target: ghostty_target_s) -> Bool {
        guard let surfaceView = surfaceView(for: target),
              let container = container(for: surfaceView) else {
            return false
        }
        return container.isSurfaceVisible(surfaceView)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    func applicationDockMenu(_ sender: NSApplication) -> NSMenu? {
        let menu = NSMenu()
        menu.addItem(withTitle: "New Window", action: #selector(handleNewWindow), keyEquivalent: "")
        menu.addItem(withTitle: "New Tab", action: #selector(handleNewTab), keyEquivalent: "")
        return menu
    }
}

