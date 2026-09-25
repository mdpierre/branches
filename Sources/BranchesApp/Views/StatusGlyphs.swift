import AppKit
import BranchesKit
import SwiftUI

// MARK: - Status node

/// The small plant drawn at the end of each branch (docs/04-design.md, "Status glyphs").
/// Drawn in a 20 × 20 box; the status words beside it stay literal, so the glyph is never the only signal.
struct StatusNode: View {
    let status: StatusResult
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            switch status.display {
            case .working:
                if reduceMotion { SproutShape() } else { SwayingSprout() }
            case .needsYou:
                if status.attention == .error { EmberShape() } else { LanternShape() }
            case .done:
                LeafShape()
            case .idle:
                if status.confidence == .unknown {
                    Circle()
                        .strokeBorder(Palette.textTertiary, style: StrokeStyle(lineWidth: 1.2, dash: [1.5, 1.5]))
                        .frame(width: 9, height: 9)
                } else {
                    SeedShape()
                }
            case .ended:
                FallenLeafShape()
            }
        }
        .frame(width: 20, height: 20)
        .animation(.easeInOut(duration: 0.15), value: status.display)
        .accessibilityLabel(status.display.label)
    }
}

// MARK: - Glyph paths (20 × 20, y down)

enum GlyphPath {
    static let stem = Path { p in
        p.move(to: CGPoint(x: 10, y: 18))
        p.addLine(to: CGPoint(x: 10, y: 9))
    }
    static let leftLeaf = Path { p in
        p.move(to: CGPoint(x: 10, y: 11.5))
        p.addCurve(to: CGPoint(x: 4, y: 5.5), control1: CGPoint(x: 6.5, y: 11.5), control2: CGPoint(x: 4, y: 9))
        p.addCurve(to: CGPoint(x: 10, y: 11.5), control1: CGPoint(x: 7.5, y: 5.5), control2: CGPoint(x: 10, y: 8))
        p.closeSubpath()
    }
    static let rightLeaf = Path { p in
        p.move(to: CGPoint(x: 10, y: 9))
        p.addCurve(to: CGPoint(x: 16, y: 3), control1: CGPoint(x: 13.5, y: 9), control2: CGPoint(x: 16, y: 6.5))
        p.addCurve(to: CGPoint(x: 10, y: 9), control1: CGPoint(x: 12.5, y: 3), control2: CGPoint(x: 10, y: 5.5))
        p.closeSubpath()
    }
    static let leaf = Path { p in
        p.move(to: CGPoint(x: 4, y: 16))
        p.addCurve(to: CGPoint(x: 16, y: 4), control1: CGPoint(x: 4, y: 8.5), control2: CGPoint(x: 9, y: 4))
        p.addCurve(to: CGPoint(x: 4, y: 16), control1: CGPoint(x: 16, y: 11), control2: CGPoint(x: 11.5, y: 16))
        p.closeSubpath()
    }
    static let midrib = Path { p in
        p.move(to: CGPoint(x: 4.5, y: 15.5))
        p.addLine(to: CGPoint(x: 12.5, y: 7.5))
    }
    static func circle(_ r: CGFloat) -> Path {
        Path(ellipseIn: CGRect(x: 10 - r, y: 10 - r, width: r * 2, height: r * 2))
    }
}

/// Working, without motion (Reduce Motion, and the summary chip).
struct SproutShape: View {
    var body: some View {
        ZStack {
            GlyphPath.stem.stroke(Palette.leaf, style: StrokeStyle(lineWidth: 1.6, lineCap: .round))
            GlyphPath.leftLeaf.fill(Palette.leaf)
            GlyphPath.rightLeaf.fill(Palette.leafLight)
        }
        .frame(width: 20, height: 20)
    }
}

/// Needs you: a lit lantern.
struct LanternShape: View {
    var body: some View {
        ZStack {
            GlyphPath.circle(9).fill(Palette.amber.opacity(0.12))
            GlyphPath.circle(6).fill(Palette.amber.opacity(0.22))
            GlyphPath.circle(3.4).fill(Palette.lanternCore)
        }
        .frame(width: 20, height: 20)
    }
}

/// Needs you because of an error: an ember with a `!`.
struct EmberShape: View {
    var body: some View {
        ZStack {
            GlyphPath.circle(9).fill(Palette.rust.opacity(0.14))
            GlyphPath.circle(6).fill(Palette.rust)
            Path(roundedRect: CGRect(x: 9.1, y: 5.8, width: 1.8, height: 5), cornerRadius: 0.9).fill(Palette.glyphInk)
            Path(ellipseIn: CGRect(x: 9, y: 12.4, width: 2, height: 2)).fill(Palette.glyphInk)
        }
        .frame(width: 20, height: 20)
    }
}

/// Done: a full leaf.
struct LeafShape: View {
    var body: some View {
        ZStack {
            GlyphPath.leaf.fill(Palette.cream.opacity(0.10))
            GlyphPath.leaf.stroke(Palette.cream, style: StrokeStyle(lineWidth: 1.3, lineJoin: .round))
            GlyphPath.midrib.stroke(Palette.cream, lineWidth: 1)
        }
        .frame(width: 20, height: 20)
    }
}

/// Idle: a seed, waiting.
struct SeedShape: View {
    var body: some View {
        Ellipse()
            .fill(Palette.seed)
            .frame(width: 6, height: 8.4)
            .rotationEffect(.degrees(-20))
            .offset(y: 1)
            .frame(width: 20, height: 20)
    }
}

/// Ended: a fallen leaf.
struct FallenLeafShape: View {
    var body: some View {
        ZStack {
            GlyphPath.leaf.fill(Palette.textTertiary)
            GlyphPath.midrib.stroke(Palette.forestBottom, lineWidth: 1)
        }
        .frame(width: 20, height: 20)
        .rotationEffect(.degrees(115))
        .scaleEffect(0.8)
    }
}

// MARK: - Swaying sprout

/// Working: a sprout that sways gently. The sway is a Core Animation layer animation, so it
/// costs the app no CPU (a SwiftUI repeatForever animation re-lays out every frame).
struct SwayingSprout: NSViewRepresentable {
    func makeNSView(context: Context) -> SproutView { SproutView() }
    func updateNSView(_ view: SproutView, context: Context) { view.updateColors() }
}

final class SproutView: NSView {
    private let plant = CALayer()
    private let stem = CAShapeLayer()
    private let left = CAShapeLayer()
    private let right = CAShapeLayer()

    init() {
        super.init(frame: NSRect(x: 0, y: 0, width: 20, height: 20))
        wantsLayer = true
        // Layer space is y-up; the glyph paths are y-down.
        var flip = CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: 0, ty: 20)
        stem.path = GlyphPath.stem.cgPath.copy(using: &flip)
        stem.lineWidth = 1.6
        stem.lineCap = .round
        stem.fillColor = nil
        left.path = GlyphPath.leftLeaf.cgPath.copy(using: &flip)
        right.path = GlyphPath.rightLeaf.cgPath.copy(using: &flip)
        for shape in [stem, left, right] {
            shape.frame = CGRect(x: 0, y: 0, width: 20, height: 20)
            plant.addSublayer(shape)
        }
        // Pivot at the foot of the stem.
        plant.bounds = CGRect(x: 0, y: 0, width: 20, height: 20)
        plant.anchorPoint = CGPoint(x: 0.5, y: 0.1)
        plant.position = CGPoint(x: 10, y: 2)
        layer?.addSublayer(plant)

        let sway = CABasicAnimation(keyPath: "transform.rotation.z")
        sway.fromValue = -0.1
        sway.toValue = 0.1
        sway.duration = 1.6
        sway.autoreverses = true
        sway.repeatCount = .infinity
        sway.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        plant.add(sway, forKey: "sway")
        updateColors()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override var intrinsicContentSize: NSSize { NSSize(width: 20, height: 20) }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateColors()
    }

    func updateColors() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            stem.strokeColor = NSColor(Palette.leaf).cgColor
            left.fillColor = NSColor(Palette.leaf).cgColor
            right.fillColor = NSColor(Palette.leafLight).cgColor
        }
    }
}
