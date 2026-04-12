import AppKit

/// Samples the desktop wallpaper on each screen and exposes a muted accent
/// color suitable for tinting translucent window backgrounds. The sample is
/// cached until the wallpaper changes or a space switch occurs.
final class WallpaperTint {
    static let shared = WallpaperTint()
    static let didChangeNotification = Notification.Name("WallpaperTintDidChange")

    private var cache: [ObjectIdentifier: NSColor] = [:]
    private var observers: [NSObjectProtocol] = []

    private init() {
        let center = NSWorkspace.shared.notificationCenter
        let spaceObserver = center.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.invalidate()
        }
        observers.append(spaceObserver)
    }

    deinit {
        let center = NSWorkspace.shared.notificationCenter
        for observer in observers {
            center.removeObserver(observer)
        }
    }

    /// Returns a cached muted accent for the given screen's wallpaper, or the
    /// app's accent color as a fallback if sampling fails.
    func accent(for screen: NSScreen?) -> NSColor {
        guard let screen else { return fallbackAccent }
        let key = ObjectIdentifier(screen)
        if let cached = cache[key] { return cached }
        let color = sample(screen: screen) ?? fallbackAccent
        cache[key] = color
        return color
    }

    func invalidate() {
        cache.removeAll()
        NotificationCenter.default.post(name: Self.didChangeNotification, object: self)
    }

    private var fallbackAccent: NSColor {
        NSColor.controlAccentColor.withAlphaComponent(1.0)
    }

    private func sample(screen: NSScreen) -> NSColor? {
        guard let imageURL = NSWorkspace.shared.desktopImageURL(for: screen),
              let source = CGImageSourceCreateWithURL(imageURL as CFURL, nil),
              let cgImage = CGImageSourceCreateThumbnailAtIndex(
                  source,
                  0,
                  [
                      kCGImageSourceCreateThumbnailFromImageAlways: true,
                      kCGImageSourceThumbnailMaxPixelSize: 64,
                      kCGImageSourceCreateThumbnailWithTransform: true,
                  ] as CFDictionary
              )
        else { return nil }

        return Self.averagedMutedColor(from: cgImage)
    }

    private static func averagedMutedColor(from image: CGImage) -> NSColor? {
        let width = image.width
        let height = image.height
        guard width > 0, height > 0 else { return nil }

        let bytesPerPixel = 4
        let bytesPerRow = bytesPerPixel * width
        let bitsPerComponent = 8
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        var data = [UInt8](repeating: 0, count: width * height * bytesPerPixel)

        guard let context = CGContext(
            data: &data,
            width: width,
            height: height,
            bitsPerComponent: bitsPerComponent,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

        var totalR: Double = 0
        var totalG: Double = 0
        var totalB: Double = 0
        var samples: Double = 0
        var i = 0
        while i < data.count {
            let r = Double(data[i]) / 255.0
            let g = Double(data[i + 1]) / 255.0
            let b = Double(data[i + 2]) / 255.0
            // Drop near-black and near-white so the tint picks up chroma
            // instead of shadows or skies.
            let lum = 0.299 * r + 0.587 * g + 0.114 * b
            if lum > 0.1 && lum < 0.9 {
                totalR += r
                totalG += g
                totalB += b
                samples += 1
            }
            i += bytesPerPixel
        }

        guard samples > 0 else { return nil }
        let avgR = CGFloat(totalR / samples)
        let avgG = CGFloat(totalG / samples)
        let avgB = CGFloat(totalB / samples)

        // Desaturate slightly so the tint stays subtle.
        let base = NSColor(srgbRed: avgR, green: avgG, blue: avgB, alpha: 1.0)
        guard let hsb = base.usingColorSpace(.sRGB) else { return base }
        let saturation = max(0.2, min(hsb.saturationComponent * 0.7, 0.55))
        let brightness = max(0.25, min(hsb.brightnessComponent, 0.65))
        return NSColor(
            hue: hsb.hueComponent,
            saturation: saturation,
            brightness: brightness,
            alpha: 1.0
        )
    }
}
