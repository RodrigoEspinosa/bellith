import AppKit

// MARK: - Theme Definition

struct ThemeColors {
    let name: String
    let base: NSColor
    let surface: NSColor
    let overlay: NSColor
    let accent: NSColor
    let textPrimary: NSColor
    let textSecondary: NSColor
    let textMuted: NSColor
    let border: NSColor
    let borderSubtle: NSColor
    /// Ghostty theme name (from ghostty's built-in themes)
    let ghosttyTheme: String

    var accentSubtle: NSColor { accent.withAlphaComponent(0.08) }
    var accentGlow: NSColor { accent.withAlphaComponent(0.03) }
    /// Window frame / gap color — slightly darker than base
    var frame: NSColor {
        NSColor(red: base.redComponent * 0.7,
                green: base.greenComponent * 0.7,
                blue: base.blueComponent * 0.7,
                alpha: 1.0)
    }
}

// MARK: - Built-in Themes

extension ThemeColors {
    static let tokyonight = ThemeColors(
        name: "Tokyo Night",
        base: NSColor(red: 0.102, green: 0.102, blue: 0.110, alpha: 1.0),
        surface: NSColor(red: 0.118, green: 0.118, blue: 0.129, alpha: 1.0),
        overlay: NSColor(red: 0.145, green: 0.145, blue: 0.161, alpha: 1.0),
        accent: NSColor(red: 0.416, green: 0.557, blue: 1.0, alpha: 1.0),
        textPrimary: NSColor(white: 0.92, alpha: 1.0),
        textSecondary: NSColor(white: 0.52, alpha: 1.0),
        textMuted: NSColor(white: 0.32, alpha: 1.0),
        border: NSColor(white: 1.0, alpha: 0.06),
        borderSubtle: NSColor(white: 1.0, alpha: 0.03),
        ghosttyTheme: "tokyonight"
    )

    static let catppuccinMocha = ThemeColors(
        name: "Catppuccin Mocha",
        base: NSColor(red: 0.118, green: 0.118, blue: 0.180, alpha: 1.0),
        surface: NSColor(red: 0.129, green: 0.133, blue: 0.200, alpha: 1.0),
        overlay: NSColor(red: 0.176, green: 0.176, blue: 0.255, alpha: 1.0),
        accent: NSColor(red: 0.533, green: 0.659, blue: 0.996, alpha: 1.0),
        textPrimary: NSColor(red: 0.804, green: 0.843, blue: 0.957, alpha: 1.0),
        textSecondary: NSColor(red: 0.533, green: 0.561, blue: 0.678, alpha: 1.0),
        textMuted: NSColor(red: 0.369, green: 0.392, blue: 0.482, alpha: 1.0),
        border: NSColor(white: 1.0, alpha: 0.06),
        borderSubtle: NSColor(white: 1.0, alpha: 0.03),
        ghosttyTheme: "catppuccin-mocha"
    )

    static let gruvboxDark = ThemeColors(
        name: "Gruvbox Dark",
        base: NSColor(red: 0.157, green: 0.157, blue: 0.129, alpha: 1.0),
        surface: NSColor(red: 0.180, green: 0.176, blue: 0.145, alpha: 1.0),
        overlay: NSColor(red: 0.220, green: 0.216, blue: 0.176, alpha: 1.0),
        accent: NSColor(red: 0.984, green: 0.737, blue: 0.020, alpha: 1.0),
        textPrimary: NSColor(red: 0.922, green: 0.859, blue: 0.698, alpha: 1.0),
        textSecondary: NSColor(red: 0.659, green: 0.600, blue: 0.518, alpha: 1.0),
        textMuted: NSColor(red: 0.451, green: 0.420, blue: 0.373, alpha: 1.0),
        border: NSColor(white: 1.0, alpha: 0.06),
        borderSubtle: NSColor(white: 1.0, alpha: 0.03),
        ghosttyTheme: "GruvboxDark"
    )

    static let rosePine = ThemeColors(
        name: "Rosé Pine",
        base: NSColor(red: 0.137, green: 0.122, blue: 0.173, alpha: 1.0),
        surface: NSColor(red: 0.153, green: 0.141, blue: 0.192, alpha: 1.0),
        overlay: NSColor(red: 0.208, green: 0.188, blue: 0.259, alpha: 1.0),
        accent: NSColor(red: 0.682, green: 0.533, blue: 0.757, alpha: 1.0),
        textPrimary: NSColor(red: 0.878, green: 0.855, blue: 0.914, alpha: 1.0),
        textSecondary: NSColor(red: 0.620, green: 0.588, blue: 0.675, alpha: 1.0),
        textMuted: NSColor(red: 0.420, green: 0.400, blue: 0.471, alpha: 1.0),
        border: NSColor(white: 1.0, alpha: 0.06),
        borderSubtle: NSColor(white: 1.0, alpha: 0.03),
        ghosttyTheme: "rose-pine"
    )

    static let nord = ThemeColors(
        name: "Nord",
        base: NSColor(red: 0.180, green: 0.204, blue: 0.251, alpha: 1.0),
        surface: NSColor(red: 0.208, green: 0.235, blue: 0.282, alpha: 1.0),
        overlay: NSColor(red: 0.263, green: 0.298, blue: 0.353, alpha: 1.0),
        accent: NSColor(red: 0.533, green: 0.753, blue: 0.816, alpha: 1.0),
        textPrimary: NSColor(red: 0.925, green: 0.937, blue: 0.957, alpha: 1.0),
        textSecondary: NSColor(red: 0.616, green: 0.639, blue: 0.682, alpha: 1.0),
        textMuted: NSColor(red: 0.400, green: 0.424, blue: 0.463, alpha: 1.0),
        border: NSColor(white: 1.0, alpha: 0.06),
        borderSubtle: NSColor(white: 1.0, alpha: 0.03),
        ghosttyTheme: "nord"
    )

    static let solarizedDark = ThemeColors(
        name: "Solarized Dark",
        base: NSColor(red: 0.000, green: 0.169, blue: 0.212, alpha: 1.0),
        surface: NSColor(red: 0.027, green: 0.212, blue: 0.259, alpha: 1.0),
        overlay: NSColor(red: 0.051, green: 0.259, blue: 0.322, alpha: 1.0),
        accent: NSColor(red: 0.149, green: 0.545, blue: 0.824, alpha: 1.0),
        textPrimary: NSColor(red: 0.514, green: 0.580, blue: 0.588, alpha: 1.0),
        textSecondary: NSColor(red: 0.396, green: 0.482, blue: 0.514, alpha: 1.0),
        textMuted: NSColor(red: 0.345, green: 0.431, blue: 0.459, alpha: 1.0),
        border: NSColor(white: 1.0, alpha: 0.06),
        borderSubtle: NSColor(white: 1.0, alpha: 0.03),
        ghosttyTheme: "Solarized Dark"
    )

    static let allThemes: [ThemeColors] = [
        .tokyonight, .catppuccinMocha, .gruvboxDark, .rosePine, .nord, .solarizedDark,
    ]
}

// MARK: - Theme Manager (Observable)

final class ThemeManager {
    static let shared = ThemeManager()

    static let didChangeNotification = Notification.Name("BellithThemeDidChange")

    private(set) var current: ThemeColors = .tokyonight {
        didSet {
            NotificationCenter.default.post(name: Self.didChangeNotification, object: self)
        }
    }

    func apply(_ theme: ThemeColors) {
        current = theme
    }
}

// MARK: - Convenience Accessors (drop-in replacement for old static Theme)

enum Theme {
    static var colors: ThemeColors { ThemeManager.shared.current }

    // Base palette
    static var base: NSColor { colors.base }
    static var surface: NSColor { colors.surface }
    static var overlay: NSColor { colors.overlay }

    // Accent
    static var accent: NSColor { colors.accent }
    static var accentSubtle: NSColor { colors.accentSubtle }
    static var accentGlow: NSColor { colors.accentGlow }

    // Text
    static var textPrimary: NSColor { colors.textPrimary }
    static var textSecondary: NSColor { colors.textSecondary }
    static var textMuted: NSColor { colors.textMuted }

    // Border
    static var border: NSColor { colors.border }
    static var borderSubtle: NSColor { colors.borderSubtle }

    // Radii
    static let radiusWindow: CGFloat = 12
    static let radiusPanel: CGFloat = 10
    static let radiusElement: CGFloat = 6

    // Spacing
    static let spacingXS: CGFloat = 4
    static let spacingSM: CGFloat = 8
    static let spacingMD: CGFloat = 12
    static let spacingLG: CGFloat = 16

    // Animation
    static let animFast: TimeInterval = 0.15
    static let animMedium: TimeInterval = 0.25
    static let animSlow: TimeInterval = 0.4
}
