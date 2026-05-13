import AppKit

/// Bellith's native design system.
///
/// This is intentionally small and boring: it gives AppKit views one place to
/// pull spacing, radii, control sizes, colors, typography, and settings-row
/// geometry from. The goal is consistency, not a Tailwind clone.
enum BellithDesignSystem {
    enum Space {
        static let xxs: CGFloat = 2
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 12
        static let lg: CGFloat = 16
        static let xl: CGFloat = 24
        static let xxl: CGFloat = 32
    }

    enum Radius {
        static let control: CGFloat = 6
        static let controlLarge: CGFloat = 8
        static let card: CGFloat = 8
        static let panel: CGFloat = 10
        static let window: CGFloat = 14
    }

    enum Size {
        static let rowHeight: CGFloat = 40
        static let textFieldHeight: CGFloat = 28
        static let toggleWidth: CGFloat = 44
        static let toggleHeight: CGFloat = 24
        static let stepButton: CGFloat = 28
    }

    enum Typography {
        static func sectionTitle() -> NSFont { BellithFont.mono(11, weight: .regular) }
        static func caption() -> NSFont { BellithFont.ui(11, weight: .regular) }
        static func rowLabel() -> NSFont { BellithFont.mono(11, weight: .regular) }
        static func field() -> NSFont { BellithFont.mono(12.5, weight: .regular) }
        static func numericField() -> NSFont { BellithFont.mono(12, weight: .regular) }
        static func value() -> NSFont { BellithFont.mono(14, weight: .medium) }
    }

    enum Color {
        static var windowBackground: NSColor { Theme.frame }
        static var cardBackground: NSColor { Theme.chrome }
        static var controlBackground: NSColor { Theme.frame }
        static var controlBackgroundHover: NSColor { Theme.chromeElevated }
        static var stroke: NSColor { Theme.border }
        static var strokeStrong: NSColor { Theme.chromeHairline }
        static var text: NSColor { Theme.textPrimary }
        static var textSecondary: NSColor { Theme.textSecondary }
        static var textMuted: NSColor { Theme.textMuted }
        static var accent: NSColor { Theme.accent }
        static var toggleOn: NSColor { Theme.colors.isLight ? Theme.textPrimary : Theme.textDisplay }
        static var toggleOff: NSColor { Theme.colors.isLight ? Theme.surface : Theme.chromeElevated }
    }

    enum Settings {
        static let horizontalPadding: CGFloat = Space.xxl
        static let sectionGap: CGFloat = Space.xxl
        static let rowGap: CGFloat = Space.xs
        static let cardPadding: CGFloat = 18
        static let controlGap: CGFloat = 14

        static func trailingControlX(cardWidth: CGFloat, controlWidth: CGFloat) -> CGFloat {
            cardWidth - cardPadding - controlWidth
        }

        static func trailingControlFrame(
            cardWidth: CGFloat,
            rowY: CGFloat,
            controlWidth: CGFloat,
            controlHeight: CGFloat
        ) -> NSRect {
            NSRect(
                x: trailingControlX(cardWidth: cardWidth, controlWidth: controlWidth),
                y: rowY + (Size.rowHeight - controlHeight) / 2,
                width: controlWidth,
                height: controlHeight
            )
        }

        static func labelWidth(
            cardWidth: CGFloat,
            from x: CGFloat = cardPadding,
            trailingControlWidth: CGFloat = Size.toggleWidth,
            gap: CGFloat = controlGap
        ) -> CGFloat {
            trailingControlX(cardWidth: cardWidth, controlWidth: trailingControlWidth) - x - gap
        }

        static func leadingLabelFrame(rowY: CGFloat, width: CGFloat) -> NSRect {
            NSRect(x: cardPadding, y: rowY, width: width, height: Size.rowHeight)
        }

        static func fieldFrame(x: CGFloat, rowY: CGFloat, width: CGFloat) -> NSRect {
            NSRect(x: x, y: rowY + 6, width: width, height: Size.textFieldHeight)
        }

        static func trailingToggleFrame(cardWidth: CGFloat, rowY: CGFloat) -> NSRect {
            trailingControlFrame(
                cardWidth: cardWidth,
                rowY: rowY,
                controlWidth: Size.toggleWidth,
                controlHeight: Size.toggleHeight
            )
        }
    }
}
