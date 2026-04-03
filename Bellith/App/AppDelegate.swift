import AppKit
import GhosttyKit

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

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var terminalApp: TerminalApp?
    private var window: NSWindow?
    private var container: TerminalContainerView?

    func applicationDidFinishLaunching(_ notification: Notification) {
        var argc: UInt = 0
        let initResult = ghostty_init(argc, nil)
        guard initResult == GHOSTTY_SUCCESS else {
            NSLog("Failed to initialize ghostty: \(initResult)")
            NSApp.terminate(nil)
            return
        }

        let config = TerminalConfig()
        guard config.config != nil else {
            NSLog("Failed to create ghostty config")
            NSApp.terminate(nil)
            return
        }

        let app = TerminalApp(config: config)
        guard app.app != nil else {
            NSLog("Failed to create ghostty app")
            NSApp.terminate(nil)
            return
        }
        self.terminalApp = app

        app.onAction = { [weak self] target, action in
            self?.handleAction(target: target, action: action) ?? false
        }

        // Restore saved theme
        ThemeManager.shared.apply(BellithSettings.shared.resolvedTheme)

        let appearance = NSApp.effectiveAppearance
        let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        app.setColorScheme(isDark ? GHOSTTY_COLOR_SCHEME_DARK : GHOSTTY_COLOR_SCHEME_LIGHT)

        createWindow()
        setupMenus()
    }

    private func createWindow() {
        guard let terminalApp else { return }

        let window = TerminalWindow(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 600),
            styleMask: [],
            backing: .buffered,
            defer: false
        )
        window.center()
        window.isReleasedWhenClosed = false
        window.delegate = self

        let container = TerminalContainerView(terminalApp: terminalApp)
        window.contentView = container
        window.makeFirstResponder(container.activeSurface)

        self.window = window
        self.container = container

        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func setupMenus() {
        let mainMenu = NSMenu()

        // App menu
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "About Bellith", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        let prefsItem = NSMenuItem(title: "Preferences…", action: #selector(handlePreferences), keyEquivalent: ",")
        appMenu.addItem(prefsItem)
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit Bellith", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        let appMenuItem = NSMenuItem()
        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)

        // Edit menu
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Copy", action: #selector(handleCopy), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(handlePaste), keyEquivalent: "v")
        let editMenuItem = NSMenuItem()
        editMenuItem.submenu = editMenu
        mainMenu.addItem(editMenuItem)

        // Tab menu
        let tabMenu = NSMenu(title: "Tab")
        tabMenu.addItem(withTitle: "New Tab", action: #selector(handleNewTab), keyEquivalent: "t")
        tabMenu.addItem(withTitle: "Close Tab", action: #selector(handleCloseTab), keyEquivalent: "w")
        tabMenu.addItem(.separator())
        let nextTab = NSMenuItem(title: "Next Tab", action: #selector(handleNextTab), keyEquivalent: "]")
        nextTab.keyEquivalentModifierMask = [.command, .shift]
        tabMenu.addItem(nextTab)
        let prevTab = NSMenuItem(title: "Previous Tab", action: #selector(handlePrevTab), keyEquivalent: "[")
        prevTab.keyEquivalentModifierMask = [.command, .shift]
        tabMenu.addItem(prevTab)
        let tabMenuItem = NSMenuItem()
        tabMenuItem.submenu = tabMenu
        mainMenu.addItem(tabMenuItem)

        // View menu
        let viewMenu = NSMenu(title: "View")
        let sidebarItem = NSMenuItem(title: "Toggle Sidebar", action: #selector(handleToggleSidebar), keyEquivalent: "b")
        sidebarItem.keyEquivalentModifierMask = .command
        viewMenu.addItem(sidebarItem)
        let paletteItem = NSMenuItem(title: "Command Palette", action: #selector(handleTogglePalette), keyEquivalent: "k")
        paletteItem.keyEquivalentModifierMask = .command
        viewMenu.addItem(paletteItem)
        viewMenu.addItem(.separator())

        // Theme submenu
        let themeSubmenu = NSMenu(title: "Theme")
        for theme in ThemeColors.allThemes {
            let item = NSMenuItem(title: theme.name, action: #selector(handleThemeSelection(_:)), keyEquivalent: "")
            item.representedObject = theme
            themeSubmenu.addItem(item)
        }
        let themeItem = NSMenuItem(title: "Theme", action: nil, keyEquivalent: "")
        themeItem.submenu = themeSubmenu
        viewMenu.addItem(themeItem)

        let viewMenuItem = NSMenuItem()
        viewMenuItem.submenu = viewMenu
        mainMenu.addItem(viewMenuItem)

        NSApp.mainMenu = mainMenu
    }

    // MARK: - Menu Actions

    @objc private func handleCopy() { container?.copySelection() }
    @objc private func handlePaste() { container?.pasteClipboard() }
    @objc private func handleNewTab() { container?.createTab() }
    @objc private func handleCloseTab() { container?.closeCurrentTab() }
    @objc private func handleNextTab() {
        guard let c = container else { return }
        let count = c.sidebar.tabs.count
        c.selectTab(c.selectedTabIndex + 1 < count ? c.selectedTabIndex + 1 : 0)
    }
    @objc private func handlePrevTab() {
        guard let c = container else { return }
        let count = c.sidebar.tabs.count
        c.selectTab(c.selectedTabIndex > 0 ? c.selectedTabIndex - 1 : count - 1)
    }
    @objc private func handleToggleSidebar() { container?.sidebar.toggle() }
    @objc private func handleTogglePalette() { container?.toggleCommandPalette() }
    @objc private func handlePreferences() { PreferencesWindowController.shared.showWindow() }
    @objc private func handleThemeSelection(_ sender: NSMenuItem) {
        guard let theme = sender.representedObject as? ThemeColors else { return }
        BellithSettings.shared.themeName = theme.name
        ThemeManager.shared.apply(theme)
    }

    // MARK: - Ghostty Actions

    private func handleAction(target: ghostty_target_s, action: ghostty_action_s) -> Bool {
        switch action.tag {
        case GHOSTTY_ACTION_SET_TITLE:
            if let titlePtr = action.action.set_title.title {
                let title = String(cString: titlePtr)
                // Update the tab title for the target surface
                if target.tag == GHOSTTY_TARGET_SURFACE,
                   let surfaceUD = ghostty_surface_userdata(target.target.surface) {
                    let surfaceView = Unmanaged<TerminalSurfaceView>.fromOpaque(surfaceUD).takeUnretainedValue()
                    container?.updateTabTitle(title, for: surfaceView)
                }
            }
            return true

        case GHOSTTY_ACTION_PWD:
            if let pwdPtr = action.action.pwd.pwd {
                let pwd = String(cString: pwdPtr)
                if target.tag == GHOSTTY_TARGET_SURFACE,
                   let surfaceUD = ghostty_surface_userdata(target.target.surface) {
                    let surfaceView = Unmanaged<TerminalSurfaceView>.fromOpaque(surfaceUD).takeUnretainedValue()
                    container?.updateTabCwd(pwd, for: surfaceView)
                }
            }
            return true

        case GHOSTTY_ACTION_NEW_TAB:
            container?.createTab()
            return true

        case GHOSTTY_ACTION_NEW_WINDOW:
            createWindow()
            return true

        case GHOSTTY_ACTION_CLOSE_WINDOW:
            window?.close()
            return true

        case GHOSTTY_ACTION_RENDER:
            container?.activeSurface?.needsDisplay = true
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
                window?.minSize = NSSize(width: CGFloat(limits.min_width),
                                         height: CGFloat(limits.min_height))
            }
            return true

        case GHOSTTY_ACTION_INITIAL_SIZE:
            let size = action.action.initial_size
            window?.setContentSize(NSSize(width: CGFloat(size.width),
                                          height: CGFloat(size.height)))
            window?.center()
            return true

        case GHOSTTY_ACTION_CELL_SIZE:
            let size = action.action.cell_size
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

        default:
            return false
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}

// MARK: - NSWindowDelegate

extension AppDelegate: NSWindowDelegate {
    func windowDidBecomeKey(_ notification: Notification) {
        terminalApp?.setFocus(true)
        window?.makeFirstResponder(container?.activeSurface)
    }

    func windowDidResignKey(_ notification: Notification) {
        terminalApp?.setFocus(false)
    }

    func windowWillClose(_ notification: Notification) {
        // Surfaces are freed when their views are deallocated (container is released)
        container = nil
    }
}
