# Bellith

A native macOS terminal emulator built with Swift and [Ghostty](https://ghostty.org)'s rendering engine.

![macOS 14+](https://img.shields.io/badge/macOS-14.0%2B-blue)
![Swift 5.10](https://img.shields.io/badge/Swift-5.10-orange)
![Version 0.1.0](https://img.shields.io/badge/version-0.1.0-green)

## Features

- **GPU-accelerated rendering** — Powered by GhosttyKit (Metal-based terminal rendering)
- **Tabs** — Create, close, and switch between multiple terminal tabs
- **Sidebar** — Collapsible sidebar for tab navigation
- **Split panes** — Split your terminal view
- **Command palette** — Quick access to actions via `⌘K`
- **Themes** — Built-in themes including Tokyo Night, Catppuccin Mocha, Gruvbox Dark, Rosé Pine, Nord, and Solarized Dark
- **Preferences** — Configurable settings with persistent storage
- **Frameless window** — Clean, minimal window chrome with custom title bar

## Requirements

- macOS 14.0 (Sonoma) or later
- Xcode 16.0+
- [XcodeGen](https://github.com/yonaskolb/XcodeGen)

## Getting Started

### 1. Clone the repository

```bash
git clone git@github.com:RodrigoEspinosa/bellith.git
cd bellith
```

### 2. Generate the Xcode project

```bash
xcodegen generate
```

### 3. Download the GhosttyKit framework

The GhosttyKit XCFramework is distributed as a binary dependency. It will be fetched automatically via Swift Package Manager, or you can place it manually in the `Frameworks/` directory.

### 4. Build & Run

Open `Bellith.xcodeproj` in Xcode and run the **Bellith** target, or use the Makefile:

```bash
make build    # Build the app
make run      # Build and open the app
make clean    # Clean build artifacts
make generate # Regenerate Xcode project from project.yml
```

## Keyboard Shortcuts

| Shortcut | Action |
|---|---|
| `⌘T` | New tab |
| `⌘W` | Close tab |
| `⌘⇧]` | Next tab |
| `⌘⇧[` | Previous tab |
| `⌘C` | Copy |
| `⌘V` | Paste |
| `⌘B` | Toggle sidebar |
| `⌘K` | Command palette |
| `⌘,` | Preferences |

## Project Structure

```
Bellith/
├── App/
│   └── AppDelegate.swift        # App entry point & Ghostty lifecycle
├── Bridge/
│   ├── TerminalApp.swift        # GhosttyKit app wrapper
│   ├── TerminalConfig.swift     # GhosttyKit configuration
│   └── InputHelpers.swift       # Keyboard/mouse input translation
├── Views/
│   ├── TerminalSurfaceView.swift    # Metal-backed terminal surface
│   ├── TerminalContainerView.swift  # Tab & surface management
│   ├── TerminalWindow.swift         # Custom frameless window
│   ├── TabBarView.swift             # Tab bar UI
│   ├── SidebarView.swift            # Sidebar navigation
│   ├── SplitPaneView.swift          # Split pane layout
│   ├── CommandPaletteView.swift     # Command palette overlay
│   ├── PreferencesView.swift        # Preferences window
│   ├── HUDView.swift               # Heads-up display overlay
│   ├── BlurView.swift              # NSVisualEffectView wrapper
│   └── Theme.swift                  # Theme definitions & manager
└── Bellith.entitlements
```

## License

This project uses [GhosttyKit](https://ghostty.org) for terminal rendering. See Ghostty's license for details on framework usage.
