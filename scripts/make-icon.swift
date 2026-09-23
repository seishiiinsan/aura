// Renders Aura's app icon (a glowing gradient ring with a sparkle) into an .icns.
// Usage: swift scripts/make-icon.swift <output.icns>
import AppKit

func render(size: CGFloat) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size),
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let ctx = NSGraphicsContext.current!.cgContext
    let s = size

    // macOS squircle background
    let inset = s * 0.1
    let rect = CGRect(x: inset, y: inset, width: s - 2 * inset, height: s - 2 * inset)
    let bg = CGPath(roundedRect: rect, cornerWidth: rect.width * 0.225, cornerHeight: rect.width * 0.225, transform: nil)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -s * 0.01), blur: s * 0.03, color: NSColor.black.withAlphaComponent(0.35).cgColor)
    ctx.addPath(bg)
    ctx.setFillColor(NSColor(calibratedRed: 0.06, green: 0.05, blue: 0.12, alpha: 1).cgColor)
    ctx.fillPath()
    ctx.restoreGState()

    ctx.saveGState()
    ctx.addPath(bg)
    ctx.clip()
    let space = CGColorSpaceCreateDeviceRGB()
    // Soft aurora glow in the background
    let glow = CGGradient(colorsSpace: space, colors: [
        NSColor(calibratedRed: 0.45, green: 0.25, blue: 0.95, alpha: 0.55).cgColor,
        NSColor(calibratedRed: 0.06, green: 0.05, blue: 0.12, alpha: 0).cgColor,
    ] as CFArray, locations: [0, 1])!
    ctx.drawRadialGradient(glow, startCenter: CGPoint(x: s / 2, y: s / 2), startRadius: 0,
                           endCenter: CGPoint(x: s / 2, y: s / 2), endRadius: s * 0.45, options: [])

    // Gradient ring
    let center = CGPoint(x: s / 2, y: s / 2)
    let radius = s * 0.26
    let ringWidth = s * 0.075
    let colors: [NSColor] = [
        .init(calibratedRed: 0.62, green: 0.36, blue: 1.0, alpha: 1),
        .init(calibratedRed: 0.33, green: 0.55, blue: 1.0, alpha: 1),
        .init(calibratedRed: 0.25, green: 0.88, blue: 0.95, alpha: 1),
        .init(calibratedRed: 1.0, green: 0.42, blue: 0.75, alpha: 1),
        .init(calibratedRed: 0.62, green: 0.36, blue: 1.0, alpha: 1),
    ]
    let ring = CGPath(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius, width: 2 * radius, height: 2 * radius), transform: nil)
        .copy(strokingWithWidth: ringWidth, lineCap: .round, lineJoin: .round, miterLimit: 1)
    // Glow: a blurred copy of the ring underneath.
    ctx.saveGState()
    ctx.setShadow(offset: .zero, blur: s * 0.06, color: NSColor(calibratedRed: 0.55, green: 0.45, blue: 1, alpha: 1).cgColor)
    ctx.addPath(ring)
    ctx.setFillColor(NSColor(calibratedRed: 0.5, green: 0.4, blue: 1, alpha: 0.6).cgColor)
    ctx.fillPath()
    ctx.restoreGState()
    // Crisp conic-gradient ring on top.
    ctx.saveGState()
    ctx.addPath(ring)
    ctx.clip()
    // Conic gradient approximated with thin pie wedges.
    let steps = 720
    for i in 0..<steps {
        let t = CGFloat(i) / CGFloat(steps)
        let seg = t * CGFloat(colors.count - 1)
        let a = colors[Int(seg)], b = colors[min(Int(seg) + 1, colors.count - 1)]
        let c = a.blended(withFraction: seg - floor(seg), of: b) ?? a
        let start = .pi / 2 + t * 2 * .pi, end = start + 2 * .pi / CGFloat(steps) * 1.2
        ctx.move(to: center)
        ctx.addArc(center: center, radius: radius + ringWidth, startAngle: start, endAngle: end, clockwise: false)
        ctx.closePath()
        ctx.setFillColor(c.cgColor)
        ctx.fillPath()
    }
    ctx.restoreGState()

    if insights {
        // Bar chart instead of the sparkle.
        ctx.setShadow(offset: .zero, blur: s * 0.03, color: NSColor.white.withAlphaComponent(0.8).cgColor)
        ctx.setFillColor(NSColor.white.cgColor)
        let barW = s * 0.045, gap = s * 0.028
        let heights: [CGFloat] = [0.07, 0.12, 0.09, 0.15]
        let totalW = CGFloat(heights.count) * barW + CGFloat(heights.count - 1) * gap
        for (i, h) in heights.enumerated() {
            let x = center.x - totalW / 2 + CGFloat(i) * (barW + gap)
            let rect = CGRect(x: x, y: center.y - s * 0.075, width: barW, height: s * h)
            ctx.addPath(CGPath(roundedRect: rect, cornerWidth: barW / 2, cornerHeight: barW / 2, transform: nil))
            ctx.fillPath()
        }
        ctx.restoreGState()
        NSGraphicsContext.restoreGraphicsState()
        return rep
    }

    // Four-point sparkle
    ctx.setShadow(offset: .zero, blur: s * 0.03, color: NSColor.white.withAlphaComponent(0.8).cgColor)
    let r = s * 0.12, k = s * 0.022
    let star = CGMutablePath()
    star.move(to: CGPoint(x: center.x, y: center.y + r))
    star.addQuadCurve(to: CGPoint(x: center.x + r, y: center.y), control: CGPoint(x: center.x + k, y: center.y + k))
    star.addQuadCurve(to: CGPoint(x: center.x, y: center.y - r), control: CGPoint(x: center.x + k, y: center.y - k))
    star.addQuadCurve(to: CGPoint(x: center.x - r, y: center.y), control: CGPoint(x: center.x - k, y: center.y - k))
    star.addQuadCurve(to: CGPoint(x: center.x, y: center.y + r), control: CGPoint(x: center.x - k, y: center.y + k))
    ctx.addPath(star)
    ctx.setFillColor(NSColor.white.cgColor)
    ctx.fillPath()
    ctx.restoreGState()

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

let args = CommandLine.arguments.dropFirst()
let insights = args.contains("--insights")
let output = args.first { !$0.hasPrefix("--") } ?? "AppIcon.icns"
let iconset = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(insights ? "Insights.iconset" : "AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let px = CGFloat(base * scale)
        let name = scale == 1 ? "icon_\(base)x\(base).png" : "icon_\(base)x\(base)@2x.png"
        let data = render(size: px).representation(using: .png, properties: [:])!
        try data.write(to: iconset.appendingPathComponent(name))
    }
}
let task = Process()
task.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
task.arguments = ["-c", "icns", iconset.path, "-o", output]
try task.run()
task.waitUntilExit()
print("Icon written to \(output)")
