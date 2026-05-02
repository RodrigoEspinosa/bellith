import AppKit

/// Single source of truth for the rebrand chrome's tokens. These mirror the
/// PR Popover v2 design's CSS variables (`--bg`, `--surface`, `--line`, etc.)
/// so layout/color decisions can be expressed in the same language as the
/// design source. No legacy `Theme` lookups in the rebrand views — color
/// goes through here.
enum RebrandTokens {
    // MARK: Layout
    enum Layout {
        static let windowCornerRadius: CGFloat = 14
        static let titleBarHeight: CGFloat = 40
        static let statusBarHeight: CGFloat = 28
        static let railWidth: CGFloat = 64

        static let bodyPaddingTop: CGFloat = 10
        static let bodyPaddingHorizontal: CGFloat = 10
        static let bodyPaddingBottom: CGFloat = 0  // status bar joins flush

        static let paneCornerRadius: CGFloat = 8
        static let paneGap: CGFloat = 8
        static let paneHeaderHeight: CGFloat = 24

        static let railCardSize: CGFloat = 40
        static let railCardSpacing: CGFloat = 8
        static let railTopInset: CGFloat = 62     // traffic-lights gutter
        static let railBottomInset: CGFloat = 16
    }

    // MARK: Color
    /// Dark-theme palette derived from the design's oklch values. Light-theme
    /// values come from `light(_:)` which mirrors the chosen lightness onto a
    /// near-white base.
    enum Color {
        // Core surfaces
        static var windowBg: NSColor { adaptive(dark: oklch(0.118, 0.010, 260), light: oklch(0.97, 0.005, 260)) }
        static var paneBg: NSColor { adaptive(dark: oklch(0.108, 0.008, 260), light: oklch(0.99, 0.004, 260)) }
        static var paneHeaderBg: NSColor { adaptive(dark: oklch(0.148, 0.009, 260), light: oklch(0.96, 0.004, 260)) }
        static var paneHeaderBgFocused: NSColor { adaptive(dark: oklch(0.168, 0.012, 260), light: oklch(0.99, 0.004, 260)) }
        static var titleBarBg: NSColor { adaptive(dark: oklch(0.160, 0.010, 260), light: oklch(0.95, 0.004, 260)) }
        static var statusBarBg: NSColor { adaptive(dark: oklch(0.112, 0.008, 260), light: oklch(0.95, 0.004, 260)) }

        // Lines
        static var line: NSColor { adaptive(dark: oklch(0.255, 0.012, 260), light: oklch(0.86, 0.006, 260)) }
        static var lineSoft: NSColor { adaptive(dark: oklch(0.215, 0.012, 260), light: oklch(0.90, 0.006, 260)) }
        static var lineStrong: NSColor { adaptive(dark: oklch(0.34, 0.014, 260), light: oklch(0.78, 0.008, 260)) }

        // Text
        static var fg: NSColor { adaptive(dark: oklch(0.95, 0.005, 260), light: oklch(0.16, 0.008, 260)) }
        static var fg2: NSColor { adaptive(dark: oklch(0.78, 0.012, 260), light: oklch(0.30, 0.008, 260)) }
        static var fg3: NSColor { adaptive(dark: oklch(0.58, 0.015, 260), light: oklch(0.46, 0.010, 260)) }
        static var fg4: NSColor { adaptive(dark: oklch(0.42, 0.015, 260), light: oklch(0.62, 0.010, 260)) }

        // State
        static var ok: NSColor { oklch(0.78, 0.14, 150) }
        static var warn: NSColor { oklch(0.80, 0.14, 80) }
        static var err: NSColor { oklch(0.70, 0.18, 25) }

        // Hover/selection overlays
        static var hoverOverlay: NSColor { adaptive(dark: oklch(0.22, 0.010, 260), light: oklch(0.93, 0.006, 260)) }
        static var rowSelected: NSColor { adaptive(dark: oklch(0.27, 0.016, 260), light: oklch(0.91, 0.008, 260)) }

        // Convert oklch(L, C, H) → NSColor. The math is approximate (oklch via
        // sRGB→OKLAB inverse with a clip) but the perceptual feel matches the
        // design source closely enough for chrome use.
        static func oklch(_ l: CGFloat, _ c: CGFloat, _ h: CGFloat) -> NSColor {
            let hr = h * .pi / 180
            let a = c * cos(hr)
            let b = c * sin(hr)

            let l_ = l + 0.3963377774 * a + 0.2158037573 * b
            let m_ = l - 0.1055613458 * a - 0.0638541728 * b
            let s_ = l - 0.0894841775 * a - 1.2914855480 * b

            let lc = l_ * l_ * l_
            let mc = m_ * m_ * m_
            let sc = s_ * s_ * s_

            var r =  4.0767416621 * lc - 3.3077115913 * mc + 0.2309699292 * sc
            var g = -1.2684380046 * lc + 2.6097574011 * mc - 0.3413193965 * sc
            var bl = -0.0041960863 * lc - 0.7034186147 * mc + 1.7076147010 * sc

            r = max(0, min(1, r.linearToSRGB()))
            g = max(0, min(1, g.linearToSRGB()))
            bl = max(0, min(1, bl.linearToSRGB()))
            return NSColor(srgbRed: r, green: g, blue: bl, alpha: 1)
        }

        /// Returns the dark variant in dark appearance, light variant in light.
        /// Wraps in NSColor(name:dynamicProvider:) so it adapts live.
        static func adaptive(dark: NSColor, light: NSColor) -> NSColor {
            NSColor(name: nil) { appearance in
                let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
                return isDark ? dark : light
            }
        }
    }

    // MARK: Typography
    enum Typography {
        static func mono(_ size: CGFloat, weight: NSFont.Weight = .regular) -> NSFont {
            NSFont.monospacedSystemFont(ofSize: size, weight: weight)
        }
        static func ui(_ size: CGFloat, weight: NSFont.Weight = .regular) -> NSFont {
            NSFont.systemFont(ofSize: size, weight: weight)
        }
    }
}

private extension CGFloat {
    /// Linear-light → sRGB gamma encoding for the OKLab→sRGB step.
    func linearToSRGB() -> CGFloat {
        if self <= 0.0031308 { return self * 12.92 }
        return 1.055 * pow(self, 1.0 / 2.4) - 0.055
    }
}
