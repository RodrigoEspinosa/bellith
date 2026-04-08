import AppKit
import GhosttyKit
import os
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
    private var terminalApp: TerminalApp?
    private var windows: [WindowEntry] = []
    private var newWindowObserver: NSObjectProtocol?
    private var appearanceObserver: NSObjectProtocol?
    private var themeMenu = NSMenu(title: "Theme")

    private struct WindowEntry {
        let window: TerminalWindow
        let container: TerminalContainerView
    }

    /// The key (focused) window's container, or the most recent one.
    private var activeEntry: WindowEntry? {
        if let keyWindow = NSApp.keyWindow as? TerminalWindow {
            return windows.first { $0.window === keyWindow }
        }
        return windows.last
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let argc: UInt = 0
        let initResult = ghostty_init(argc, nil)
        guard initResult == GHOSTTY_SUCCESS else {
            Logger.app.error("Failed to initialize ghostty: \(String(describing: initResult))")
            NSApp.terminate(nil)
            return
        }

        let config = TerminalConfig()
        guard config.config != nil else {
            Logger.app.error("Failed to create ghostty config")
            NSApp.terminate(nil)
            return
        }

        let app = TerminalApp(config: config)
        guard app.app != nil else {
            Logger.app.error("Failed to create ghostty app")
            NSApp.terminate(nil)
            return
        }
        self.terminalApp = app

        app.onAction = { [weak self] target, action in
            self?.handleAction(target: target, action: action) ?? false
        }

        // Restore saved theme for current system appearance
        ThemeManager.shared.apply(BellithSettings.shared.resolvedTheme)

        let isDark = BellithSettings.shared.systemIsDark
        app.setColorScheme(isDark ? GHOSTTY_COLOR_SCHEME_DARK : GHOSTTY_COLOR_SCHEME_LIGHT)

        // Observe system appearance changes to switch themes
        appearanceObserver = DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name("AppleInterfaceThemeChangedNotification"),
            object: nil, queue: .main
        ) { [weak self] _ in
            self?.handleSystemAppearanceChanged()
        }

        // Request notification permission
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }

        // Listen for new window requests
        newWindowObserver = NotificationCenter.default.addObserver(forName: .bellithCreateNewWindow, object: nil, queue: .main) { [weak self] notification in
            let request = notification.object as? WindowLaunchRequest
            self?.createWindow(
                session: request?.session,
                initialWorkingDirectory: request?.initialWorkingDirectory
            )
        }

        // Setup quick terminal (visor)
        QuickTerminalController.shared.setup(terminalApp: app)

        // Try to restore previous session(s)
        if !restoreSavedWindows() {
            createWindow()
        }
        setupMenus()
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Save all window sessions if enabled
        if BellithSettings.shared.restoreSession {
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

        // Tear down all windows
        for entry in windows {
            entry.container.teardown()
        }

        // Clean up quick terminal
        QuickTerminalController.shared.cleanup()
    }

    @discardableResult
    private func createWindow(
        session: SessionState? = nil,
        initialWorkingDirectory: String? = nil,
        frameDescriptor: String? = nil
    ) -> WindowEntry? {
        guard let terminalApp else { return nil }

        let window = TerminalWindow(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 600),
            styleMask: [],
            backing: .buffered,
            defer: false
        )
        if let frameDescriptor {
            let restoredFrame = NSRectFromString(frameDescriptor)
            if restoredFrame.width > 0, restoredFrame.height > 0 {
                window.setFrame(restoredFrame, display: false)
            } else {
                window.center()
            }
        } else {
            window.center()
        }
        window.isReleasedWhenClosed = false
        window.delegate = self

        let container = TerminalContainerView(terminalApp: terminalApp)
        window.contentView = container

        let entry = WindowEntry(window: window, container: container)
        windows.append(entry)

        if let session, !session.tabs.isEmpty {
            container.restoreSession(session)
        } else if let initialWorkingDirectory, !initialWorkingDirectory.isEmpty {
            container.openWorkingDirectory(initialWorkingDirectory)
        }

        window.makeFirstResponder(container.activeSurface ?? container)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate()
        return entry
    }

    private func restoreSavedWindows() -> Bool {
        guard BellithSettings.shared.restoreSession else { return false }

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

    private func setupMenus() {
        let mainMenu = NSMenu()

        // App menu
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "About Bellith", action: #selector(handleAbout), keyEquivalent: "")
        appMenu.addItem(.separator())
        let prefsItem = NSMenuItem(title: "Settings…", action: #selector(handlePreferences), keyEquivalent: ",")
        appMenu.addItem(prefsItem)
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
        shellMenu.addItem(withTitle: "New Tab", action: #selector(handleNewTab), keyEquivalent: "t")
        shellMenu.addItem(withTitle: "New Window", action: #selector(handleNewWindow), keyEquivalent: "n")
        shellMenu.addItem(withTitle: "Connect Host…", action: #selector(handleConnectHost), keyEquivalent: "")
        shellMenu.addItem(.separator())
        let splitRightItem = NSMenuItem(title: "Split Right", action: #selector(handleSplitRight), keyEquivalent: "d")
        shellMenu.addItem(splitRightItem)
        let splitDownItem = NSMenuItem(title: "Split Down", action: #selector(handleSplitDown), keyEquivalent: "d")
        splitDownItem.keyEquivalentModifierMask = [.command, .shift]
        shellMenu.addItem(splitDownItem)
        shellMenu.addItem(.separator())
        shellMenu.addItem(withTitle: "Close Pane", action: #selector(handleClosePane), keyEquivalent: "")
        shellMenu.addItem(withTitle: "Close Tab", action: #selector(handleCloseTab), keyEquivalent: "w")
        shellMenu.addItem(withTitle: "Close Window", action: #selector(handleCloseWindow), keyEquivalent: "")
        let shellMenuItem = NSMenuItem()
        shellMenuItem.submenu = shellMenu
        mainMenu.addItem(shellMenuItem)

        // Edit menu
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Undo", action: #selector(UndoManager.undo), keyEquivalent: "z")
        editMenu.addItem(withTitle: "Redo", action: #selector(UndoManager.redo), keyEquivalent: "z").keyEquivalentModifierMask = [.command, .shift]
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "Copy", action: #selector(handleCopy), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(handlePaste), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(handleSelectAll), keyEquivalent: "a")
        editMenu.addItem(.separator())
        let findItem = NSMenuItem(title: "Find…", action: #selector(handleFind), keyEquivalent: "f")
        editMenu.addItem(findItem)
        editMenu.addItem(.separator())
        let clearItem = NSMenuItem(title: "Clear Buffer", action: #selector(handleClearBuffer), keyEquivalent: "k")
        clearItem.keyEquivalentModifierMask = [.command, .shift]
        editMenu.addItem(clearItem)
        let editMenuItem = NSMenuItem()
        editMenuItem.submenu = editMenu
        mainMenu.addItem(editMenuItem)

        // Tab menu
        let tabMenu = NSMenu(title: "Tab")
        let nextTab = NSMenuItem(title: "Next Tab", action: #selector(handleNextTab), keyEquivalent: "]")
        nextTab.keyEquivalentModifierMask = [.command, .shift]
        tabMenu.addItem(nextTab)
        let prevTab = NSMenuItem(title: "Previous Tab", action: #selector(handlePrevTab), keyEquivalent: "[")
        prevTab.keyEquivalentModifierMask = [.command, .shift]
        tabMenu.addItem(prevTab)
        tabMenu.addItem(.separator())
        let reopenItem = NSMenuItem(title: "Reopen Closed Tab", action: #selector(handleReopenTab), keyEquivalent: "t")
        reopenItem.keyEquivalentModifierMask = [.command, .shift]
        tabMenu.addItem(reopenItem)
        let tabMenuItem = NSMenuItem()
        tabMenuItem.submenu = tabMenu
        mainMenu.addItem(tabMenuItem)

        // View menu
        let viewMenu = NSMenu(title: "View")
        let sidebarItem = NSMenuItem(title: "Toggle Sidebar", action: #selector(handleToggleSidebar), keyEquivalent: "e")
        sidebarItem.keyEquivalentModifierMask = [.command, .shift]
        viewMenu.addItem(sidebarItem)
        let paletteItem = NSMenuItem(title: "Command Palette", action: #selector(handleTogglePalette), keyEquivalent: "k")
        paletteItem.keyEquivalentModifierMask = .command
        viewMenu.addItem(paletteItem)
        viewMenu.addItem(.separator())
        let fontBiggerItem = NSMenuItem(title: "Increase Font Size", action: #selector(handleFontBigger), keyEquivalent: "=")
        viewMenu.addItem(fontBiggerItem)
        let fontSmallerItem = NSMenuItem(title: "Decrease Font Size", action: #selector(handleFontSmaller), keyEquivalent: "-")
        viewMenu.addItem(fontSmallerItem)
        let fontResetItem = NSMenuItem(title: "Reset Font Size", action: #selector(handleFontReset), keyEquivalent: "0")
        viewMenu.addItem(fontResetItem)
        viewMenu.addItem(.separator())
        let fullscreenItem = NSMenuItem(title: "Toggle Full Screen", action: #selector(handleFullscreen), keyEquivalent: "")
        fullscreenItem.keyEquivalentModifierMask = [.command, .control]
        viewMenu.addItem(fullscreenItem)
        viewMenu.addItem(.separator())

        // Theme submenu
        themeMenu = NSMenu(title: "Theme")
        themeMenu.delegate = self
        rebuildThemeMenu()
        let themeItem = NSMenuItem(title: "Theme", action: nil, keyEquivalent: "")
        themeItem.submenu = themeMenu
        viewMenu.addItem(themeItem)

        let viewMenuItem = NSMenuItem()
        viewMenuItem.submenu = viewMenu
        mainMenu.addItem(viewMenuItem)

        // Tools menu — built-in smart panel plugins
        let toolsMenu = NSMenu(title: "Tools")
        for plugin in SmartPanelRegistry.shared.allPlugins {
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
        helpMenu.addItem(withTitle: "Bellith Help", action: #selector(handleHelp), keyEquivalent: "?")
        let helpMenuItem = NSMenuItem()
        helpMenuItem.submenu = helpMenu
        mainMenu.addItem(helpMenuItem)
        NSApp.helpMenu = helpMenu

        NSApp.mainMenu = mainMenu
    }

    // MARK: - Menu Actions

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
    @objc private func handleCloseTab() { activeEntry?.container.closeCurrentTab() }
    @objc private func handleCloseWindow() { NSApp.keyWindow?.close() }
    @objc private func handleClosePane() { activeEntry?.container.closePane() }
    @objc private func handleNewWindow() { createWindow() }
    @objc private func handleConnectHost() {
        let profiles = SSHProfileStore.shared.profiles
        if profiles.count == 1, let profile = profiles.first {
            activeEntry?.container.connectSSHProfile(id: profile.id)
        } else {
            PreferencesWindowController.shared.showWindow(selecting: "ssh")
        }
    }
    @objc private func handleSplitRight() { activeEntry?.container.splitPane(direction: .vertical) }
    @objc private func handleSplitDown() { activeEntry?.container.splitPane(direction: .horizontal) }
    @objc private func handleReopenTab() { activeEntry?.container.reopenClosedTab() }
    @objc private func handleNextTab() {
        guard let c = activeEntry?.container else { return }
        let count = c.sidebar.tabs.count
        c.selectTab(c.selectedTabIndex + 1 < count ? c.selectedTabIndex + 1 : 0)
    }
    @objc private func handlePrevTab() {
        guard let c = activeEntry?.container else { return }
        let count = c.sidebar.tabs.count
        c.selectTab(c.selectedTabIndex > 0 ? c.selectedTabIndex - 1 : count - 1)
    }
    @objc private func handleToggleSidebar() { activeEntry?.container.sidebar.toggle() }
    @objc private func handleTogglePalette() { activeEntry?.container.toggleCommandPalette() }

    @objc private func handleFontBigger() { activeEntry?.container.adjustFontSizePublic(delta: 1) }
    @objc private func handleFontSmaller() { activeEntry?.container.adjustFontSizePublic(delta: -1) }
    @objc private func handleFontReset() { activeEntry?.container.resetFontSizePublic() }
    @objc private func handleFullscreen() { NSApp.keyWindow?.toggleFullScreen(nil) }
    @objc private func handlePreferences() { PreferencesWindowController.shared.showWindow() }
    @objc private func handleAbout() {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        NSApp.orderFrontStandardAboutPanel(options: [
            .applicationName: "Bellith",
            .applicationVersion: version,
            .version: build,
            .credits: NSAttributedString(string: "A native macOS terminal powered by GhosttyKit.")
        ])
        NSApp.activate(ignoringOtherApps: true)
    }
    @objc private func handleHelp() {
        // Open help/documentation — for now open the custom themes folder as a basic help action
        if let url = URL(string: "https://github.com/RodrigoEspinosa/bellith") {
            NSWorkspace.shared.open(url)
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
            BellithSettings.shared.lightThemeName = theme.name
        } else {
            BellithSettings.shared.darkThemeName = theme.name
        }
        // Apply immediately if it matches the current system appearance
        let resolved = BellithSettings.shared.resolvedTheme
        ThemeManager.shared.apply(resolved)
        let appearance = resolved.isLight ? NSAppearance(named: .aqua) : NSAppearance(named: .darkAqua)
        for entry in windows { entry.window.appearance = appearance }
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        if menu === themeMenu { rebuildThemeMenu() }
    }

    private func rebuildThemeMenu() {
        themeMenu.removeAllItems()
        let settings = BellithSettings.shared
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

    private func handleSystemAppearanceChanged() {
        // Small delay to let NSApp.effectiveAppearance update
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            let theme = BellithSettings.shared.resolvedTheme
            ThemeManager.shared.apply(theme)
            let appearance = theme.isLight ? NSAppearance(named: .aqua) : NSAppearance(named: .darkAqua)
            if let self {
                for entry in self.windows { entry.window.appearance = appearance }
            }
        }
    }

    // MARK: - Ghostty Actions

    private func handleAction(target: ghostty_target_s, action: ghostty_action_s) -> Bool {
        switch action.tag {
        case GHOSTTY_ACTION_SET_TITLE:
            if let titlePtr = action.action.set_title.title {
                let title = String(cString: titlePtr)
                if target.tag == GHOSTTY_TARGET_SURFACE,
                   let surfaceUD = ghostty_surface_userdata(target.target.surface) {
                    let surfaceView = Unmanaged<TerminalSurfaceView>.fromOpaque(surfaceUD).takeUnretainedValue()
                    container(for: surfaceView)?.updateTabTitle(title, for: surfaceView)
                    // Update window title for Mission Control / Cmd+Tab
                    surfaceView.window?.title = title
                }
            }
            return true

        case GHOSTTY_ACTION_PWD:
            if let pwdPtr = action.action.pwd.pwd {
                let pwd = String(cString: pwdPtr)
                if target.tag == GHOSTTY_TARGET_SURFACE,
                   let surfaceUD = ghostty_surface_userdata(target.target.surface) {
                    let surfaceView = Unmanaged<TerminalSurfaceView>.fromOpaque(surfaceUD).takeUnretainedValue()
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
                if let url = URL(string: str) {
                    NSWorkspace.shared.open(url)
                }
            }
            return true

        case GHOSTTY_ACTION_RING_BELL:
            NSSound.beep()
            return true

        case GHOSTTY_ACTION_MOUSE_OVER_LINK:
            let link = action.action.mouse_over_link
            if link.len > 0, let url = link.url {
                let urlStr = String(cString: url)
                if target.tag == GHOSTTY_TARGET_SURFACE,
                   let surfaceUD = ghostty_surface_userdata(target.target.surface) {
                    let surfaceView = Unmanaged<TerminalSurfaceView>.fromOpaque(surfaceUD).takeUnretainedValue()
                    container(for: surfaceView)?.showLinkPreview(urlStr)
                }
            } else {
                activeEntry?.container.hideLinkPreview()
            }
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
            // Only notify for long-running commands when app is not focused
            if durationSec >= 10 && !NSApp.isActive {
                let content = UNMutableNotificationContent()
                content.title = "Command finished"
                if info.exit_code == 0 {
                    content.body = String(format: "Completed successfully (%.0fs)", durationSec)
                } else if info.exit_code > 0 {
                    content.body = String(format: "Exited with code %d (%.0fs)", info.exit_code, durationSec)
                } else {
                    content.body = String(format: "Completed (%.0fs)", durationSec)
                }
                content.sound = .default
                let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
                UNUserNotificationCenter.current().add(request)
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
            if target.tag == GHOSTTY_TARGET_SURFACE,
               let surfaceUD = ghostty_surface_userdata(target.target.surface) {
                let surfaceView = Unmanaged<TerminalSurfaceView>.fromOpaque(surfaceUD).takeUnretainedValue()
                container(for: surfaceView)?.updateScrollbar(
                    total: bar.total, offset: bar.offset, visible: bar.len
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
            return true

        case GHOSTTY_ACTION_SEARCH_TOTAL:
            let total = Int(action.action.search_total.total)
            activeEntry?.container.updateSearchTotal(total)
            return true

        case GHOSTTY_ACTION_SEARCH_SELECTED:
            let selected = Int(action.action.search_selected.selected)
            activeEntry?.container.updateSearchSelected(selected)
            return true

        default:
            return false
        }
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

// MARK: - NSWindowDelegate

extension AppDelegate: NSWindowDelegate {
    func windowDidBecomeKey(_ notification: Notification) {
        guard let window = notification.object as? TerminalWindow,
              let entry = windows.first(where: { $0.window === window }) else { return }
        terminalApp?.setFocus(true)
        window.makeFirstResponder(entry.container.activeSurface)
    }

    func windowDidResignKey(_ notification: Notification) {
        terminalApp?.setFocus(false)
    }

    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? TerminalWindow else { return }
        // Tear down the container's resources before dropping references
        if let entry = windows.first(where: { $0.window === window }) {
            entry.container.teardown()
        }
        windows.removeAll { $0.window === window }
    }
}
