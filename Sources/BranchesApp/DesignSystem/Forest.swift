import AppKit
import SwiftUI

// The Forest v1 scene (docs/04-design.md §9): the treeline header, its fireflies, and the
// window's gradient with dappled light and grain. Everything is drawn in code; there are no image assets.

// MARK: - Time of day

enum TimeOfDay: String, CaseIterable, Identifiable {
    case dawn, day, dusk, night

    var id: String { rawValue }
    var label: String { rawValue.capitalized }

    /// Fixed hours rather than real sunrise and sunset, which would need the user's location.
    static func at(_ date: Date, calendar: Calendar = .current) -> TimeOfDay {
        switch calendar.component(.hour, from: date) {
        case 5..<9: .dawn
        case 9..<17: .day
        case 17..<20: .dusk
        default: .night
        }
    }
}

struct ScenePalette {
    var skyTop: Color
    var skyBottom: Color
    var far: Color
    var mid: Color
    var glow: Color
    var moon: Double
    var stars: Double
    /// Tint of the dappled light on the window background.
    var dapple: Color

    static func of(_ time: TimeOfDay, dark: Bool) -> ScenePalette {
        let h = Palette.hex
        guard dark else {
            // Light mode is a pale morning whatever the hour.
            return ScenePalette(skyTop: h(0xC9D6D6, 1), skyBottom: h(0xEDE4D2, 1), far: h(0xB6C5B6, 1), mid: h(0x9CB29D, 1),
                                glow: h(0xFFDCA0, 0.5), moon: 0, stars: 0, dapple: h(0x789664, 0.05))
        }
        switch time {
        case .dawn:
            return ScenePalette(skyTop: h(0x26303A, 1), skyBottom: h(0x6A5842, 1), far: h(0x3A473E, 1), mid: h(0x27352B, 1),
                                glow: h(0xF0BE78, 0.45), moon: 0, stars: 0, dapple: h(0xE6BE82, 0.06))
        case .day:
            return ScenePalette(skyTop: h(0x23404A, 1), skyBottom: h(0x5E7B68, 1), far: h(0x35503F, 1), mid: h(0x253A2D, 1),
                                glow: h(0xFFF0C8, 0.18), moon: 0, stars: 0, dapple: h(0xC8E196, 0.075))
        case .dusk:
            return ScenePalette(skyTop: h(0x131D23, 1), skyBottom: h(0x38382A, 1), far: h(0x26352D, 1), mid: h(0x1C2A21, 1),
                                glow: h(0xE0A94A, 0.22), moon: 0.85, stars: 0.25, dapple: h(0x96BE78, 0.055))
        case .night:
            return ScenePalette(skyTop: h(0x090E11, 1), skyBottom: h(0x15201B, 1), far: h(0x223029, 1), mid: h(0x1A251E, 1),
                                glow: .clear, moon: 0.95, stars: 0.8, dapple: h(0xBED2E6, 0.035))
        }
    }
}

// MARK: - Treeline

/// Three layers of pines. Trees are placed left to right from a fixed seed, so a wider window
/// adds trees on the right and the existing ones never move.
enum Treeline {
    struct Layers {
        var far: Path
        var mid: Path
        var near: Path
        var stars: Path
    }

    @MainActor private static var cache: [Int: Layers] = [:]

    @MainActor
    static func layers(width: CGFloat) -> Layers {
        let key = Int(width.rounded(.up))
        if let cached = cache[key] { return cached }
        if cache.count > 16 { cache.removeAll() }
        let w = CGFloat(key)
        let layers = Layers(
            far: layer(seed: 7, width: w, base: 104, minH: 22, maxH: 48, step: 12),
            mid: layer(seed: 19, width: w, base: 116, minH: 26, maxH: 60, step: 18),
            near: layer(seed: 31, width: w, base: 126, minH: 12, maxH: 32, step: 26),
            stars: stars(width: w)
        )
        cache[key] = layers
        return layers
    }

    private struct Random {
        var state: Int
        mutating func next() -> CGFloat {
            state = (state * 16807) % 2147483647
            return CGFloat(state - 1) / 2147483646
        }
    }

    private static func layer(seed: Int, width: CGFloat, base: CGFloat, minH: CGFloat, maxH: CGFloat, step: CGFloat) -> Path {
        var r = Random(state: seed)
        var p = Path(CGRect(x: 0, y: base, width: width, height: Metrics.headerHeight - base))
        var x: CGFloat = -8
        while x < width + 12 {
            let h = minH + r.next() * (maxH - minH)
            let w = h * (0.38 + r.next() * 0.14)
            // Two tiers per pine.
            p.addLines([CGPoint(x: x - w / 2, y: base), CGPoint(x: x, y: base - h * 0.62), CGPoint(x: x + w / 2, y: base)])
            p.closeSubpath()
            p.addLines([CGPoint(x: x - w * 0.4, y: base - h * 0.4), CGPoint(x: x, y: base - h), CGPoint(x: x + w * 0.4, y: base - h * 0.4)])
            p.closeSubpath()
            x += step * (0.6 + r.next() * 0.8)
        }
        return p
    }

    private static func stars(width: CGFloat) -> Path {
        var r = Random(state: 4242)
        var p = Path()
        for _ in 0..<Int(width / 20) {
            let x = 90 + r.next() * (width - 100), y = 4 + r.next() * 56, radius = 0.5 + r.next() * 0.6
            p.addEllipse(in: CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2))
        }
        return p
    }
}

// MARK: - Header

/// The treeline header. `collapse` runs from 0 (at rest, 128 pt) to 1 (a 40 pt strip of treetops);
/// the layers move up at different rates so the shrink reads as depth.
struct ForestHeader: View {
    var collapse: CGFloat
    var time: TimeOfDay
    /// One firefly per session that needs you (true = an error), at most five.
    var fireflies: [Bool]
    /// Nudges for a short, fixed-height use (the menu bar panel): keep the moon inside the strip
    /// and the fireflies below the summary chip.
    var skyDrop: CGFloat = 0
    var fireflyDrop: CGFloat = 0
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let fireflySpots: [(x: CGFloat, y: CGFloat)] = [(0.30, 92), (0.66, 86), (0.47, 98), (0.84, 90), (0.14, 95)]

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let layers = Treeline.layers(width: width)
            let palette = ScenePalette.of(time, dark: colorScheme == .dark)
            let c = collapse
            let midY = -80 * c
            ZStack(alignment: .topLeading) {
                Canvas { ctx, _ in
                    let sky = Path(CGRect(x: 0, y: 0, width: width, height: Metrics.headerHeight))
                    ctx.fill(sky, with: .linearGradient(Gradient(colors: [palette.skyTop, palette.skyBottom]),
                                                        startPoint: .zero, endPoint: CGPoint(x: 0, y: Metrics.headerHeight)))
                    var skyCtx = ctx
                    skyCtx.translateBy(x: 0, y: -30 * c + skyDrop)
                    skyCtx.drawLayer { glow in
                        glow.addFilter(.blur(radius: 16))
                        glow.fill(Path(ellipseIn: CGRect(x: width * 0.7 - 170, y: 66, width: 340, height: 68)), with: .color(palette.glow))
                    }
                    skyCtx.fill(layers.stars, with: .color(Palette.cream.opacity(palette.stars)))
                    let moon = CGPoint(x: width * 0.57, y: 22)
                    skyCtx.drawLayer { halo in
                        halo.addFilter(.blur(radius: 3))
                        halo.fill(Path(ellipseIn: CGRect(x: moon.x - 11, y: moon.y - 11, width: 22, height: 22)),
                                  with: .color(Palette.hex(0xECE6D8, palette.moon * 0.22)))
                    }
                    skyCtx.fill(Path(ellipseIn: CGRect(x: moon.x - 5.5, y: moon.y - 5.5, width: 11, height: 11)),
                                with: .color(Palette.hex(0xEFE8D4, palette.moon)))

                    var far = ctx
                    far.translateBy(x: 0, y: -70 * c)
                    far.fill(layers.far, with: .color(palette.far))
                    var mid = ctx
                    mid.translateBy(x: 0, y: midY)
                    mid.fill(layers.mid, with: .color(palette.mid))
                }
                FireflyField(
                    flies: fireflies.prefix(Self.fireflySpots.count).enumerated().map { i, isError in
                        let spot = Self.fireflySpots[i]
                        return Firefly(x: (spot.x * width).rounded(), y: spot.y + midY + fireflyDrop, isError: isError)
                    },
                    animated: !reduceMotion
                )
                Canvas { ctx, _ in
                    ctx.translateBy(x: 0, y: -88 * c)
                    ctx.fill(layers.near, with: .color(Palette.forestTop))
                }
                GrainOverlay()
            }
        }
        .clipped()
        .accessibilityHidden(true)
    }
}

// MARK: - Fireflies

struct Firefly: Equatable {
    var x: CGFloat
    var y: CGFloat
    var isError: Bool
}

/// Fireflies flicker with Core Animation, so they cost the app no CPU while idle.
struct FireflyField: NSViewRepresentable {
    var flies: [Firefly]
    var animated: Bool

    func makeNSView(context: Context) -> FireflyView { FireflyView() }
    func updateNSView(_ view: FireflyView, context: Context) { view.update(flies, animated: animated) }
}

final class FireflyView: NSView {
    private var glows: [CAGradientLayer] = []
    private var flies: [Firefly] = []
    private var animated = true

    init() {
        super.init(frame: .zero)
        wantsLayer = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    func update(_ next: [Firefly], animated: Bool) {
        let rebuild = next.map(\.isError) != flies.map(\.isError) || animated != self.animated
        flies = next
        self.animated = animated
        if rebuild { rebuildLayers() }
        place()
    }

    override func layout() {
        super.layout()
        place()
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        let scale = window?.backingScaleFactor ?? 2
        glows.forEach { $0.contentsScale = scale }
    }

    private func rebuildLayers() {
        glows.forEach { $0.removeFromSuperlayer() }
        glows = flies.enumerated().map { i, fly in
            let glow = CAGradientLayer()
            glow.type = .radial
            glow.startPoint = CGPoint(x: 0.5, y: 0.5)
            glow.endPoint = CGPoint(x: 1, y: 1)
            let core = fly.isError ? NSColor(srgbRed: 0.94, green: 0.60, blue: 0.48, alpha: 1)
                                   : NSColor(srgbRed: 1, green: 0.82, blue: 0.48, alpha: 1)
            let halo = fly.isError ? NSColor(srgbRed: 0.78, green: 0.40, blue: 0.29, alpha: 0.45)
                                   : NSColor(srgbRed: 0.88, green: 0.66, blue: 0.29, alpha: 0.4)
            glow.colors = [core.cgColor, core.cgColor, halo.cgColor, NSColor.clear.cgColor]
            glow.locations = [0, 0.14, 0.3, 0.7]
            glow.bounds = CGRect(x: 0, y: 0, width: 16, height: 16)
            glow.contentsScale = window?.backingScaleFactor ?? 2
            glow.opacity = 0.8
            if animated {
                let flicker = CABasicAnimation(keyPath: "opacity")
                flicker.fromValue = 0.45
                flicker.toValue = 1
                flicker.duration = 1.5
                flicker.autoreverses = true
                flicker.repeatCount = .infinity
                flicker.timeOffset = Double(i) * 0.9
                flicker.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                glow.add(flicker, forKey: "flicker")
            }
            layer?.addSublayer(glow)
            return glow
        }
    }

    private func place() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for (glow, fly) in zip(glows, flies) {
            // Layer space is y-up.
            glow.position = CGPoint(x: fly.x, y: bounds.height - fly.y)
        }
        CATransaction.commit()
    }
}

// MARK: - Window background

/// Dark moss at the top (matching the header's nearest trees) fading to near-black, with a few
/// soft patches of light as if through leaves, and a fine grain.
struct ForestBackground: View {
    var time: TimeOfDay
    /// How far down the header's color holds before the fade starts.
    var headerHeight: CGFloat = Metrics.headerHeight
    @Environment(\.colorScheme) private var colorScheme

    /// Patches of light: center (x as a fraction of the width, y in points), radii, and strength.
    private static let patches: [(x: CGFloat, y: CGFloat, rx: CGFloat, ry: CGFloat, strength: Double)] = [
        (0.74, 190, 230, 150, 1), (0.16, 300, 170, 120, 0.8), (0.90, 430, 260, 170, 0.6), (0.40, 150, 120, 90, 0.7),
    ]

    var body: some View {
        GeometryReader { geo in
            let hold = min(headerHeight / max(geo.size.height, 1), 0.4)
            let dapple = ScenePalette.of(time, dark: colorScheme == .dark).dapple
            ZStack {
                LinearGradient(stops: [
                    .init(color: Palette.forestTop, location: 0),
                    .init(color: Palette.forestTop, location: hold),
                    .init(color: Palette.forestMid, location: 0.48),
                    .init(color: Palette.forestBottom, location: 1),
                ], startPoint: .top, endPoint: .bottom)
                Canvas { ctx, size in
                    for patch in Self.patches {
                        var layer = ctx
                        layer.translateBy(x: patch.x * size.width, y: patch.y)
                        layer.scaleBy(x: 1, y: patch.ry / patch.rx)
                        let reach = patch.rx * 0.7
                        layer.fill(Path(ellipseIn: CGRect(x: -reach, y: -reach, width: reach * 2, height: reach * 2)),
                                   with: .radialGradient(Gradient(colors: [dapple.opacity(patch.strength), dapple.opacity(0)]),
                                                         center: .zero, startRadius: 0, endRadius: reach))
                    }
                }
                GrainOverlay()
            }
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Grain

/// A tile of random gray noise, generated once, repeated at very low strength.
struct GrainOverlay: View {
    var body: some View {
        if let tile = Self.tile {
            Image(decorative: tile, scale: 2)
                .resizable(resizingMode: .tile)
                .blendMode(.screen)
                .opacity(0.07)
                .allowsHitTesting(false)
        }
    }

    @MainActor private static let tile: CGImage? = {
        let size = 128
        var state: UInt64 = 0x9E37_79B9_7F4A_7C15
        var bytes = [UInt8](repeating: 0, count: size * size)
        for i in bytes.indices {
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            bytes[i] = UInt8(truncatingIfNeeded: state >> 56)
        }
        guard let provider = CGDataProvider(data: Data(bytes) as CFData) else { return nil }
        return CGImage(width: size, height: size, bitsPerComponent: 8, bitsPerPixel: 8, bytesPerRow: size,
                       space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
    }()
}
