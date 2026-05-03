import AppKit
import QuartzCore

/// Owns the decorative CALayers that paint the terminal window's chrome —
/// noise grain, content backdrop, strokes, top gloss, and sidebar transition
/// glow. Pulled out of `TerminalContainerView` so the host doesn't have to
/// micro-manage seven layers and their geometry.
final class TerminalChromeLayers {
    let noiseLayer = CALayer()
    let contentBackdropLayer = CALayer()
    let contentStrokeLayer = CALayer()
    let contentInnerStrokeLayer = CALayer()
    let contentTopGlossLayer = CAGradientLayer()
    let sidebarGlowLayer = CAGradientLayer()
    let sidebarBridgeLayer = CAGradientLayer()

    /// 256×256 monochrome noise tile, generated once and shared across all instances.
    private static let noiseImage: CGImage? = {
        let size = 256
        let totalBytes = size * size
        var pixels = [UInt8](repeating: 0, count: totalBytes)
        for i in 0..<totalBytes {
            pixels[i] = UInt8.random(in: 0...255)
        }
        guard let provider = CGDataProvider(data: Data(pixels) as CFData),
              let image = CGImage(
                  width: size, height: size,
                  bitsPerComponent: 8, bitsPerPixel: 8,
                  bytesPerRow: size,
                  space: CGColorSpaceCreateDeviceGray(),
                  bitmapInfo: CGBitmapInfo(rawValue: 0),
                  provider: provider,
                  decode: nil, shouldInterpolate: false,
                  intent: .defaultIntent
              ) else { return nil }
        return image
    }()

    /// Attach all layers to the host view's backing layer in the correct z-order.
    func install(on hostLayer: CALayer) {
        if let noiseImage = Self.noiseImage {
            let nsImage = NSImage(cgImage: noiseImage, size: NSSize(width: noiseImage.width, height: noiseImage.height))
            noiseLayer.backgroundColor = NSColor(patternImage: nsImage).cgColor
        }
        hostLayer.addSublayer(noiseLayer)

        contentBackdropLayer.cornerCurve = .continuous
        contentBackdropLayer.shadowOpacity = 1
        contentBackdropLayer.shadowOffset = CGSize(width: 0, height: -2)

        contentStrokeLayer.backgroundColor = NSColor.clear.cgColor
        contentStrokeLayer.cornerCurve = .continuous
        contentInnerStrokeLayer.backgroundColor = NSColor.clear.cgColor
        contentInnerStrokeLayer.cornerCurve = .continuous
        contentInnerStrokeLayer.borderWidth = 1

        contentTopGlossLayer.startPoint = CGPoint(x: 0.5, y: 1)
        contentTopGlossLayer.endPoint = CGPoint(x: 0.5, y: 0)
        contentTopGlossLayer.cornerCurve = .continuous

        sidebarGlowLayer.startPoint = CGPoint(x: 0, y: 0.5)
        sidebarGlowLayer.endPoint = CGPoint(x: 1, y: 0.5)

        sidebarBridgeLayer.startPoint = CGPoint(x: 0, y: 0.5)
        sidebarBridgeLayer.endPoint = CGPoint(x: 1, y: 0.5)
        sidebarBridgeLayer.cornerRadius = 12
        sidebarBridgeLayer.cornerCurve = .continuous

        hostLayer.addSublayer(contentBackdropLayer)
        hostLayer.addSublayer(contentTopGlossLayer)
        hostLayer.addSublayer(sidebarGlowLayer)
        hostLayer.addSublayer(sidebarBridgeLayer)
        hostLayer.addSublayer(contentStrokeLayer)
        hostLayer.addSublayer(contentInnerStrokeLayer)
    }

    /// Reset all visual properties — colors, borders, gradients — to their
    /// idle, fully-transparent baseline. Mirrors the previous inline
    /// `applyChromeTheme()` body.
    func applyTheme(translucent: Bool) {
        contentBackdropLayer.backgroundColor = translucent
            ? NSColor.clear.cgColor
            : Theme.surface.cgColor
        contentBackdropLayer.shadowColor = NSColor.clear.cgColor
        contentBackdropLayer.shadowOpacity = 0
        contentBackdropLayer.shadowRadius = 0

        contentStrokeLayer.borderWidth = 0
        contentStrokeLayer.borderColor = NSColor.clear.cgColor

        contentInnerStrokeLayer.borderColor = NSColor.clear.cgColor
        contentInnerStrokeLayer.borderWidth = 0

        contentTopGlossLayer.colors = [NSColor.clear.cgColor, NSColor.clear.cgColor]
        contentTopGlossLayer.locations = [0, 1]

        sidebarGlowLayer.colors = [NSColor.clear.cgColor, NSColor.clear.cgColor]
        sidebarGlowLayer.locations = [0, 1]

        sidebarBridgeLayer.colors = [NSColor.clear.cgColor, NSColor.clear.cgColor]
        sidebarBridgeLayer.locations = [0, 1]
    }

    struct FrameInputs {
        let rect: NSRect
        let contentRadius: CGFloat
        let contentPadding: CGFloat
        let sidebarGap: CGFloat
        let resolvedSidebarWidth: CGFloat
        let useSidebar: Bool
        let hasVisibleContent: Bool
    }

    /// Lay out all chrome layers for the given content rect. Caller is
    /// responsible for wrapping the call in its own CATransaction if it wants
    /// to control animation timing.
    func updateFrames(_ inputs: FrameInputs) {
        let cornerMask: CACornerMask = [
            .layerMinXMinYCorner,
            .layerMaxXMinYCorner,
            .layerMinXMaxYCorner,
            .layerMaxXMaxYCorner,
        ]
        let chromeRect = inputs.rect.insetBy(dx: -1, dy: -1)
        let hasVisibleContent = inputs.hasVisibleContent

        contentBackdropLayer.isHidden = !hasVisibleContent
        contentStrokeLayer.isHidden = !hasVisibleContent
        contentInnerStrokeLayer.isHidden = !hasVisibleContent
        contentTopGlossLayer.isHidden = !hasVisibleContent

        contentBackdropLayer.frame = chromeRect
        contentBackdropLayer.cornerRadius = inputs.contentRadius + 2
        contentBackdropLayer.maskedCorners = cornerMask

        contentStrokeLayer.frame = chromeRect
        contentStrokeLayer.cornerRadius = inputs.contentRadius + 2
        contentStrokeLayer.maskedCorners = cornerMask

        contentInnerStrokeLayer.frame = chromeRect.insetBy(dx: 1, dy: 1)
        contentInnerStrokeLayer.cornerRadius = inputs.contentRadius + 1
        contentInnerStrokeLayer.maskedCorners = cornerMask

        let glossHeight = min(72, max(40, chromeRect.height * 0.16))
        contentTopGlossLayer.frame = NSRect(
            x: chromeRect.minX,
            y: chromeRect.maxY - glossHeight,
            width: chromeRect.width,
            height: glossHeight
        )
        contentTopGlossLayer.cornerRadius = inputs.contentRadius + 2
        contentTopGlossLayer.maskedCorners = cornerMask

        let showsSidebarTransition = inputs.useSidebar && inputs.resolvedSidebarWidth > 0 && hasVisibleContent
        sidebarGlowLayer.isHidden = !showsSidebarTransition
        sidebarBridgeLayer.isHidden = !showsSidebarTransition

        if showsSidebarTransition {
            let glowRect = NSRect(
                x: inputs.contentPadding + inputs.resolvedSidebarWidth - 6,
                y: chromeRect.minY + 16,
                width: inputs.sidebarGap + 24,
                height: max(0, chromeRect.height - 32)
            )
            sidebarGlowLayer.frame = glowRect

            let bridgeHeight = min(168, max(112, chromeRect.height * 0.38))
            sidebarBridgeLayer.frame = NSRect(
                x: glowRect.minX,
                y: chromeRect.maxY - bridgeHeight - 6,
                width: glowRect.width - 2,
                height: bridgeHeight
            )
        }
    }

    /// Hide all chrome layers (used when the container is embedded inside the
    /// rebrand shell — the parent shell paints chrome instead).
    func setEmbeddedHidden(_ hidden: Bool) {
        contentBackdropLayer.isHidden = hidden
        contentStrokeLayer.isHidden = hidden
        contentInnerStrokeLayer.isHidden = hidden
        contentTopGlossLayer.isHidden = hidden
    }

    func setNoiseFrame(_ frame: NSRect) {
        noiseLayer.frame = frame
    }

    /// Settings slider 0–1 maps to 0–0.08 (dark) or 0–0.12 (light) actual opacity.
    func updateNoiseOpacity(intensity: Double, isLightTheme: Bool) {
        let maxOpacity: Double = isLightTheme ? 0.12 : 0.08
        noiseLayer.opacity = Float(intensity * maxOpacity)
    }
}
