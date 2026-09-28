import AppKit
import CoreGraphics

// Generates build/AppIcon.iconset from a drawn black tile with a white chip glyph.
// Run via ./make-icon.sh

@main
struct IconGen {
    static func main() {
        let outDir = URL(fileURLWithPath: "build/AppIcon.iconset")
        try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

        // iconutil wants these exact pixel sizes.
        let variants: [(name: String, px: Int)] = [
            ("icon_16x16", 16), ("icon_16x16@2x", 32),
            ("icon_32x32", 32), ("icon_32x32@2x", 64),
            ("icon_128x128", 128), ("icon_128x128@2x", 256),
            ("icon_256x256", 256), ("icon_256x256@2x", 512),
            ("icon_512x512", 512), ("icon_512x512@2x", 1024),
        ]

        for v in variants {
            guard let img = draw(px: v.px),
                  let tiff = NSBitmapImageRep(cgImage: img).representation(using: .tiff, properties: [:]),
                  let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:])
            else { continue }
            try? png.write(to: outDir.appendingPathComponent("\(v.name).png"))
        }
        print("iconset written to \(outDir.path)")
    }

    /// Draws the icon: near-black rounded square, subtle border, white chip outline
    /// with pins — matching the app's minimal black theme.
    static func draw(px: Int) -> CGImage? {
        let s = CGFloat(px)
        let cs = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(data: nil, width: px, height: px, bitsPerComponent: 8,
                                  bytesPerRow: 0, space: cs,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }

        ctx.clear(CGRect(x: 0, y: 0, width: s, height: s))
        ctx.setAllowsAntialiasing(true)
        ctx.setShouldAntialias(true)

        let inset = s * 0.055
        let body = CGRect(x: inset, y: inset, width: s - inset * 2, height: s - inset * 2)
        let radius = s * 0.2237   // matches the macOS squircle proportion

        // Background
        let bg = CGGradient(colorsSpace: cs,
                            colors: [
                                CGColor(red: 0.13, green: 0.13, blue: 0.14, alpha: 1),
                                CGColor(red: 0.04, green: 0.04, blue: 0.045, alpha: 1)
                            ] as CFArray,
                            locations: [0, 1])!
        ctx.addPath(CGPath(roundedRect: body, cornerWidth: radius, cornerHeight: radius, transform: nil))
        ctx.clip()
        ctx.drawLinearGradient(bg, start: CGPoint(x: 0, y: s), end: CGPoint(x: 0, y: 0), options: [])

        // Hairline border
        ctx.setStrokeColor(CGColor(red: 0.30, green: 0.30, blue: 0.32, alpha: 1))
        ctx.setLineWidth(max(1, s * 0.008))
        ctx.addPath(CGPath(roundedRect: body.insetBy(dx: s * 0.004, dy: s * 0.004),
                           cornerWidth: radius, cornerHeight: radius, transform: nil))
        ctx.strokePath()

        // Chip body
        let chipSide = s * 0.40
        let chip = CGRect(x: (s - chipSide) / 2, y: (s - chipSide) / 2, width: chipSide, height: chipSide)
        let chipRadius = chipSide * 0.16
        ctx.setStrokeColor(CGColor(red: 0.97, green: 0.97, blue: 0.98, alpha: 1))
        ctx.setLineWidth(max(1.5, s * 0.035))
        ctx.setLineCap(.round)
        ctx.addPath(CGPath(roundedRect: chip, cornerWidth: chipRadius, cornerHeight: chipRadius, transform: nil))
        ctx.strokePath()

        // Inner square
        let inner = chip.insetBy(dx: chipSide * 0.24, dy: chipSide * 0.24)
        ctx.setStrokeColor(CGColor(red: 0.97, green: 0.97, blue: 0.98, alpha: 0.55))
        ctx.setLineWidth(max(1, s * 0.018))
        ctx.addPath(CGPath(roundedRect: inner, cornerWidth: chipRadius * 0.5,
                           cornerHeight: chipRadius * 0.5, transform: nil))
        ctx.strokePath()

        // Pins on all four sides
        ctx.setStrokeColor(CGColor(red: 0.97, green: 0.97, blue: 0.98, alpha: 1))
        ctx.setLineWidth(max(1.5, s * 0.032))
        let pinLen = s * 0.075
        let pinGap = chipSide * 0.215
        for i in -1...1 {
            let off = CGFloat(i) * pinGap
            // left & right
            ctx.move(to: CGPoint(x: chip.minX, y: chip.midY + off))
            ctx.addLine(to: CGPoint(x: chip.minX - pinLen, y: chip.midY + off))
            ctx.move(to: CGPoint(x: chip.maxX, y: chip.midY + off))
            ctx.addLine(to: CGPoint(x: chip.maxX + pinLen, y: chip.midY + off))
            // bottom & top
            ctx.move(to: CGPoint(x: chip.midX + off, y: chip.minY))
            ctx.addLine(to: CGPoint(x: chip.midX + off, y: chip.minY - pinLen))
            ctx.move(to: CGPoint(x: chip.midX + off, y: chip.maxY))
            ctx.addLine(to: CGPoint(x: chip.midX + off, y: chip.maxY + pinLen))
        }
        ctx.strokePath()

        return ctx.makeImage()
    }
}
