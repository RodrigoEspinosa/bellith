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
    /// Whether this is a light theme (affects window appearance)
    var isLight: Bool {
        let rgb = base.usingColorSpace(.sRGB) ?? base
        let luminance = 0.299 * rgb.redComponent + 0.587 * rgb.greenComponent + 0.114 * rgb.blueComponent
        return luminance > 0.5
    }

    var accentSubtle: NSColor { accent.withAlphaComponent(isLight ? 0.12 : 0.14) }
    var accentGlow: NSColor { accent.withAlphaComponent(isLight ? 0.05 : 0.04) }

    /// Keep dark chrome close to the reference: cool slate, not heavily accent-tinted.
    var frame: NSColor {
        isLight
            ? base.mixing(with: .white, baseFraction: 0.78)
            : NSColor(red: 0.118, green: 0.122, blue: 0.161, alpha: 1.0)
    }

    var chrome: NSColor {
        isLight
            ? surface.mixing(with: .white, baseFraction: 0.82)
            : NSColor(red: 0.154, green: 0.158, blue: 0.205, alpha: 1.0)
    }

    var chromeElevated: NSColor {
        isLight
            ? overlay.mixing(with: .white, baseFraction: 0.74)
            : NSColor(red: 0.180, green: 0.184, blue: 0.235, alpha: 1.0)
    }

    var chromePanel: NSColor {
        isLight
            ? surface.mixing(with: .white, baseFraction: 0.86)
            : NSColor(red: 0.176, green: 0.180, blue: 0.231, alpha: 1.0)
    }

    var selectionFill: NSColor {
        isLight
            ? accent.withAlphaComponent(0.08)
            : NSColor(white: 1.0, alpha: 0.045)
    }

    var selectionStroke: NSColor {
        isLight
            ? accent.withAlphaComponent(0.16)
            : NSColor(white: 1.0, alpha: 0.08)
    }

    var chromeStroke: NSColor {
        border.scaledAlpha(isLight ? 1.1 : 1.35)
    }

    var chromeHairline: NSColor {
        border.scaledAlpha(isLight ? 1.35 : 1.75)
    }
}

// MARK: - Built-in Themes

extension ThemeColors {
    static let tokyonight = ThemeColors(
        name: "Tokyo Night",
        base: NSColor(red: 0.118, green: 0.122, blue: 0.161, alpha: 1.0),
        surface: NSColor(red: 0.145, green: 0.149, blue: 0.192, alpha: 1.0),
        overlay: NSColor(red: 0.188, green: 0.192, blue: 0.243, alpha: 1.0),
        accent: NSColor(red: 0.722, green: 0.639, blue: 0.988, alpha: 1.0),
        textPrimary: NSColor(red: 0.938, green: 0.940, blue: 0.966, alpha: 1.0),
        textSecondary: NSColor(red: 0.447, green: 0.486, blue: 0.706, alpha: 1.0),
        textMuted: NSColor(red: 0.314, green: 0.345, blue: 0.522, alpha: 1.0),
        border: NSColor(white: 1.0, alpha: 0.08),
        borderSubtle: NSColor(white: 1.0, alpha: 0.045),
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

    static let dracula = ThemeColors(
        name: "Dracula",
        base: NSColor(red: 0.157, green: 0.165, blue: 0.212, alpha: 1.0),
        surface: NSColor(red: 0.176, green: 0.184, blue: 0.239, alpha: 1.0),
        overlay: NSColor(red: 0.204, green: 0.216, blue: 0.275, alpha: 1.0),
        accent: NSColor(red: 0.741, green: 0.576, blue: 0.976, alpha: 1.0),
        textPrimary: NSColor(red: 0.973, green: 0.973, blue: 0.949, alpha: 1.0),
        textSecondary: NSColor(red: 0.384, green: 0.447, blue: 0.643, alpha: 1.0),
        textMuted: NSColor(red: 0.267, green: 0.278, blue: 0.353, alpha: 1.0),
        border: NSColor(white: 1.0, alpha: 0.06),
        borderSubtle: NSColor(white: 1.0, alpha: 0.03),
        ghosttyTheme: "Dracula"
    )

    static let kanagawaWave = ThemeColors(
        name: "Kanagawa Wave",
        base: NSColor(red: 0.122, green: 0.122, blue: 0.157, alpha: 1.0),
        surface: NSColor(red: 0.165, green: 0.165, blue: 0.216, alpha: 1.0),
        overlay: NSColor(red: 0.212, green: 0.212, blue: 0.275, alpha: 1.0),
        accent: NSColor(red: 0.494, green: 0.612, blue: 0.847, alpha: 1.0),
        textPrimary: NSColor(red: 0.863, green: 0.843, blue: 0.729, alpha: 1.0),
        textSecondary: NSColor(red: 0.447, green: 0.443, blue: 0.412, alpha: 1.0),
        textMuted: NSColor(red: 0.329, green: 0.329, blue: 0.427, alpha: 1.0),
        border: NSColor(white: 1.0, alpha: 0.06),
        borderSubtle: NSColor(white: 1.0, alpha: 0.03),
        ghosttyTheme: "kanagawa-wave"
    )

    // MARK: - Light Themes

    static let tokyonightLight = ThemeColors(
        name: "Tokyo Night Light",
        base: NSColor(red: 0.965, green: 0.969, blue: 0.976, alpha: 1.0),
        surface: NSColor(red: 0.941, green: 0.945, blue: 0.957, alpha: 1.0),
        overlay: NSColor(red: 0.910, green: 0.914, blue: 0.933, alpha: 1.0),
        accent: NSColor(red: 0.204, green: 0.369, blue: 0.839, alpha: 1.0),
        textPrimary: NSColor(red: 0.208, green: 0.220, blue: 0.282, alpha: 1.0),
        textSecondary: NSColor(red: 0.384, green: 0.400, blue: 0.482, alpha: 1.0),
        textMuted: NSColor(red: 0.596, green: 0.608, blue: 0.667, alpha: 1.0),
        border: NSColor(white: 0.0, alpha: 0.08),
        borderSubtle: NSColor(white: 0.0, alpha: 0.04),
        ghosttyTheme: "tokyonight_day"
    )

    static let catppuccinLatte = ThemeColors(
        name: "Catppuccin Latte",
        base: NSColor(red: 0.937, green: 0.925, blue: 0.957, alpha: 1.0),
        surface: NSColor(red: 0.906, green: 0.894, blue: 0.933, alpha: 1.0),
        overlay: NSColor(red: 0.875, green: 0.863, blue: 0.910, alpha: 1.0),
        accent: NSColor(red: 0.455, green: 0.322, blue: 0.839, alpha: 1.0),
        textPrimary: NSColor(red: 0.298, green: 0.282, blue: 0.376, alpha: 1.0),
        textSecondary: NSColor(red: 0.435, green: 0.412, blue: 0.529, alpha: 1.0),
        textMuted: NSColor(red: 0.604, green: 0.580, blue: 0.682, alpha: 1.0),
        border: NSColor(white: 0.0, alpha: 0.08),
        borderSubtle: NSColor(white: 0.0, alpha: 0.04),
        ghosttyTheme: "catppuccin-latte"
    )

    static let solarizedLight = ThemeColors(
        name: "Solarized Light",
        base: NSColor(red: 0.992, green: 0.965, blue: 0.890, alpha: 1.0),
        surface: NSColor(red: 0.933, green: 0.910, blue: 0.835, alpha: 1.0),
        overlay: NSColor(red: 0.882, green: 0.859, blue: 0.784, alpha: 1.0),
        accent: NSColor(red: 0.149, green: 0.545, blue: 0.824, alpha: 1.0),
        textPrimary: NSColor(red: 0.396, green: 0.482, blue: 0.514, alpha: 1.0),
        textSecondary: NSColor(red: 0.514, green: 0.580, blue: 0.588, alpha: 1.0),
        textMuted: NSColor(red: 0.659, green: 0.706, blue: 0.718, alpha: 1.0),
        border: NSColor(white: 0.0, alpha: 0.08),
        borderSubtle: NSColor(white: 0.0, alpha: 0.04),
        ghosttyTheme: "Solarized Light"
    )

    static let oneLight = ThemeColors(
        name: "One Light",
        base: NSColor(red: 0.980, green: 0.980, blue: 0.980, alpha: 1.0),
        surface: NSColor(red: 0.945, green: 0.949, blue: 0.957, alpha: 1.0),
        overlay: NSColor(red: 0.906, green: 0.910, blue: 0.918, alpha: 1.0),
        accent: NSColor(red: 0.251, green: 0.400, blue: 0.878, alpha: 1.0),
        textPrimary: NSColor(red: 0.220, green: 0.231, blue: 0.259, alpha: 1.0),
        textSecondary: NSColor(red: 0.392, green: 0.408, blue: 0.455, alpha: 1.0),
        textMuted: NSColor(red: 0.616, green: 0.631, blue: 0.667, alpha: 1.0),
        border: NSColor(white: 0.0, alpha: 0.08),
        borderSubtle: NSColor(white: 0.0, alpha: 0.04),
        ghosttyTheme: "One Light"
    )

    static let builtInThemes: [ThemeColors] = [
        .tokyonight, .catppuccinMocha, .gruvboxDark, .rosePine, .nord, .solarizedDark, .dracula, .kanagawaWave,
        .tokyonightLight, .catppuccinLatte, .solarizedLight, .oneLight,
    ]

    static var allThemes: [ThemeColors] {
        builtInThemes + CustomThemeLoader.shared.themes
    }
}

// MARK: - Custom Theme Loading

/// Loads user-defined themes from JSON files in ~/Library/Application Support/com.rec.bellith/themes/
final class CustomThemeLoader {
    static let shared = CustomThemeLoader()

    private(set) var themes: [ThemeColors] = []

    private init() { reload() }

    func reload() {
        themes = []
        guard let dir = themesDirectory else { return }

        // Create directory if it doesn't exist
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        guard let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else { return }

        for file in files where file.pathExtension == "json" {
            if let data = try? Data(contentsOf: file),
               let custom = try? JSONDecoder().decode(CustomThemeDef.self, from: data) {
                themes.append(custom.toThemeColors())
            }
        }
    }

    var themesDirectory: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("com.rec.bellith/themes", isDirectory: true)
    }
}

/// JSON-serializable theme definition.
/// Example file:
/// ```json
/// {
///   "name": "My Theme",
///   "ghosttyTheme": "custom-theme-name",
///   "base": "#1a1b26",
///   "surface": "#1e1f2b",
///   "overlay": "#24253a",
///   "accent": "#7aa2f7",
///   "textPrimary": "#c0caf5",
///   "textSecondary": "#565f89",
///   "textMuted": "#3b4261"
/// }
/// ```
struct CustomThemeDef: Codable {
    let name: String
    let ghosttyTheme: String
    let base: String
    let surface: String
    let overlay: String
    let accent: String
    let textPrimary: String
    let textSecondary: String
    let textMuted: String
    var border: String?
    var borderSubtle: String?

    func toThemeColors() -> ThemeColors {
        ThemeColors(
            name: name,
            base: NSColor(hex: base),
            surface: NSColor(hex: surface),
            overlay: NSColor(hex: overlay),
            accent: NSColor(hex: accent),
            textPrimary: NSColor(hex: textPrimary),
            textSecondary: NSColor(hex: textSecondary),
            textMuted: NSColor(hex: textMuted),
            border: border.map { NSColor(hex: $0) } ?? NSColor(white: 1.0, alpha: 0.06),
            borderSubtle: borderSubtle.map { NSColor(hex: $0) } ?? NSColor(white: 1.0, alpha: 0.03),
            ghosttyTheme: ghosttyTheme
        )
    }
}

private extension NSColor {
    convenience init(hex: String) {
        var h = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if h.hasPrefix("#") { h.removeFirst() }
        guard h.count == 6, let val = UInt64(h, radix: 16) else {
            self.init(white: 0.5, alpha: 1.0)
            return
        }
        self.init(
            red: CGFloat((val >> 16) & 0xFF) / 255.0,
            green: CGFloat((val >> 8) & 0xFF) / 255.0,
            blue: CGFloat(val & 0xFF) / 255.0,
            alpha: 1.0
        )
    }

    func mixing(with color: NSColor, baseFraction: CGFloat) -> NSColor {
        let fraction = max(0, min(1, 1 - baseFraction))
        return blended(withFraction: fraction, of: color) ?? self
    }

    func scaledAlpha(_ multiplier: CGFloat) -> NSColor {
        let converted = usingColorSpace(.sRGB) ?? self
        return converted.withAlphaComponent(max(0, min(1, converted.alphaComponent * multiplier)))
    }
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
    static var chrome: NSColor { colors.chrome }
    static var chromeElevated: NSColor { colors.chromeElevated }
    static var chromePanel: NSColor { colors.chromePanel }
    static var selectionFill: NSColor { colors.selectionFill }
    static var selectionStroke: NSColor { colors.selectionStroke }
    static var chromeStroke: NSColor { colors.chromeStroke }
    static var chromeHairline: NSColor { colors.chromeHairline }

    // Accent
    static var accent: NSColor { colors.accent }
    static var accentSubtle: NSColor { colors.accentSubtle }
    static var accentGlow: NSColor { colors.accentGlow }

    // Text
    static var textDisplay: NSColor {
        colors.isLight
            ? colors.textPrimary.mixing(with: .black, baseFraction: 0.78)
            : colors.textPrimary.mixing(with: .white, baseFraction: 0.86)
    }
    static var textPrimary: NSColor { colors.textPrimary }
    static var textSecondary: NSColor { colors.textSecondary }
    static var textMuted: NSColor { colors.textMuted }
    static var textTertiary: NSColor {
        colors.textMuted.mixing(with: colors.textSecondary, baseFraction: 0.55)
    }

    // Border
    static var border: NSColor { colors.chromeStroke }
    static var borderSubtle: NSColor { colors.borderSubtle }

    // Hover
    static var hoverOverlay: NSColor {
        colors.isLight
            ? colors.textPrimary.withAlphaComponent(0.035)
            : NSColor(white: 1.0, alpha: 0.028)
    }

    // Focus
    static var focusRing: NSColor { accent.withAlphaComponent(0.4) }

    // Appearance
    static var overlayAppearance: NSAppearance? {
        NSAppearance(named: colors.isLight ? .aqua : .darkAqua)
    }

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

    /// Whether the user prefers reduced motion. Check this before running non-essential animations.
    static var prefersReducedMotion: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    /// Run an animation block, or apply changes instantly if the user prefers reduced motion.
    static func animate(
        duration: TimeInterval = animFast,
        timing: CAMediaTimingFunction = CAMediaTimingFunction(name: .easeOut),
        _ body: (NSAnimationContext) -> Void,
        completion: (() -> Void)? = nil
    ) {
        if prefersReducedMotion {
            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = 0
                ctx.allowsImplicitAnimation = true
                body(ctx)
            }, completionHandler: completion)
        } else {
            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = duration
                ctx.timingFunction = timing
                body(ctx)
            }, completionHandler: completion)
        }
    }

    // Semantic colors
    static var success: NSColor {
        NSColor(red: 0.290, green: 0.620, blue: 0.361, alpha: 1.0) // #4A9E5C
    }
    static var warning: NSColor {
        NSColor(red: 0.831, green: 0.659, blue: 0.263, alpha: 1.0) // #D4A843
    }
    static var destructive: NSColor { accent }

    // Divider
    static var divider: NSColor { colors.border }
    static var dividerHover: NSColor { accent.withAlphaComponent(0.4) }
    static var dividerActive: NSColor { accent.withAlphaComponent(0.7) }
}
