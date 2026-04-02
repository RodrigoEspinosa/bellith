import AppKit

enum Theme {
    // Base palette — near-black, never pure black
    static let base = NSColor(red: 0.102, green: 0.102, blue: 0.110, alpha: 1.0)     // #1a1a1c
    static let surface = NSColor(red: 0.118, green: 0.118, blue: 0.129, alpha: 1.0)   // #1e1e21
    static let overlay = NSColor(red: 0.145, green: 0.145, blue: 0.161, alpha: 1.0)   // #252529

    // Accent — subtle cool blue, user-configurable later
    static let accent = NSColor(red: 0.416, green: 0.557, blue: 1.0, alpha: 1.0)      // #6a8eff
    static let accentSubtle = accent.withAlphaComponent(0.08)
    static let accentGlow = accent.withAlphaComponent(0.03)

    // Text
    static let textPrimary = NSColor(white: 0.92, alpha: 1.0)
    static let textSecondary = NSColor(white: 0.52, alpha: 1.0)
    static let textMuted = NSColor(white: 0.32, alpha: 1.0)

    // Border
    static let border = NSColor(white: 1.0, alpha: 0.06)
    static let borderSubtle = NSColor(white: 1.0, alpha: 0.03)

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
