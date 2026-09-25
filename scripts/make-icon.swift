// Draws the Branches app icon: a single cream stroke that forks once and ends in a
// bright node, on deep moss. Usage: swift scripts/make-icon.swift Resources/AppIcon.icns
import AppKit

func draw(size: CGFloat) -> NSImage {
    NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
        let s = size / 1024
        // Squircle-ish background with the standard macOS icon inset.
        let inset = 100 * s
        let bg = NSBezierPath(roundedRect: rect.insetBy(dx: inset, dy: inset), xRadius: 185 * s, yRadius: 185 * s)
        NSGradient(
            starting: NSColor(srgbRed: 0.20, green: 0.29, blue: 0.21, alpha: 1),
            ending: NSColor(srgbRed: 0.09, green: 0.12, blue: 0.09, alpha: 1)
        )!.draw(in: bg, angle: -90)

        let cream = NSColor(srgbRed: 0.93, green: 0.90, blue: 0.85, alpha: 1)
        let leaf = NSColor(srgbRed: 0.50, green: 0.81, blue: 0.48, alpha: 1)

        // Trunk rising from the bottom, forking once.
        let trunk = NSBezierPath()
        trunk.move(to: NSPoint(x: 430 * s, y: 250 * s))
        trunk.line(to: NSPoint(x: 430 * s, y: 520 * s))
        trunk.curve(to: NSPoint(x: 380 * s, y: 760 * s), controlPoint1: NSPoint(x: 430 * s, y: 620 * s), controlPoint2: NSPoint(x: 380 * s, y: 680 * s))
        trunk.move(to: NSPoint(x: 430 * s, y: 500 * s))
        trunk.curve(to: NSPoint(x: 640 * s, y: 690 * s), controlPoint1: NSPoint(x: 430 * s, y: 600 * s), controlPoint2: NSPoint(x: 560 * s, y: 620 * s))
        trunk.lineWidth = 46 * s
        trunk.lineCapStyle = .round
        cream.setStroke()
        trunk.stroke()

        // Resting node at the end of the left branch.
        cream.setFill()
        NSBezierPath(ovalIn: NSRect(x: 380 * s - 44 * s, y: 760 * s - 44 * s, width: 88 * s, height: 88 * s)).fill()

        // Live node with a soft glow at the end of the fork.
        let center = NSPoint(x: 660 * s, y: 705 * s)
        leaf.withAlphaComponent(0.22).setFill()
        NSBezierPath(ovalIn: NSRect(x: center.x - 110 * s, y: center.y - 110 * s, width: 220 * s, height: 220 * s)).fill()
        leaf.setFill()
        NSBezierPath(ovalIn: NSRect(x: center.x - 62 * s, y: center.y - 62 * s, width: 124 * s, height: 124 * s)).fill()
        return true
    }
}

func png(_ image: NSImage, pixels: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: pixels, height: pixels)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    image.draw(in: NSRect(x: 0, y: 0, width: pixels, height: pixels))
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let output = CommandLine.arguments.dropFirst().first ?? "Resources/AppIcon.icns"
let iconset = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("Branches.iconset")
try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
let master = draw(size: 1024)
for base in [16, 32, 128, 256, 512] {
    try png(master, pixels: base).write(to: iconset.appendingPathComponent("icon_\(base)x\(base).png"))
    try png(master, pixels: base * 2).write(to: iconset.appendingPathComponent("icon_\(base)x\(base)@2x.png"))
}
let task = Process()
task.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
task.arguments = ["-c", "icns", iconset.path, "-o", output]
try task.run()
task.waitUntilExit()
print(task.terminationStatus == 0 ? "Wrote \(output)" : "iconutil failed")
