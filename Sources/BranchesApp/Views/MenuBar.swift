import AppKit
import BranchesKit
import SwiftUI

/// The menu bar icon: a small fork glyph, plus a count when sessions need you.
struct MenuBarLabel: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let waiting = model.needsYouCount
        HStack(spacing: 3) {
            Image(nsImage: MenuBarGlyph.image(alert: waiting > 0))
            if waiting > 0 {
                Text("\(waiting)").monospacedDigit()
            }
        }
        .task { model.start() }
        .accessibilityLabel(waiting > 0 ? "Branches: \(waiting) need you" : "Branches")
    }
}

/// The Branches mark: a trunk that forks into two nodes. Drawn in code so it stays crisp at any
/// scale. Normally it's a template image, so it follows the menu bar's light/dark style. When a
/// session needs you it switches to the accent colors (brown trunk, green and red nodes).
enum MenuBarGlyph {
    @MainActor private static var cache: [Bool: NSImage] = [:]

    @MainActor
    static func image(alert: Bool) -> NSImage {
        if let cached = cache[alert] { return cached }
        let image = NSImage(size: NSSize(width: 15, height: 16), flipped: true) { _ in
            if alert { drawAccent() } else { drawTemplate() }
            return true
        }
        image.isTemplate = !alert
        cache[alert] = image
        return image
    }

    // Traced from the design sheet (the mark is 303 × 358 there) and scaled to 16 pt tall.
    private static let scale: CGFloat = 16 / 358
    private static func pt(_ x: CGFloat, _ y: CGFloat) -> NSPoint {
        NSPoint(x: (x - 146) * scale + 0.7, y: (y - 312) * scale)
    }
    private static func node(_ x: CGFloat, _ y: CGFloat, _ r: CGFloat) -> NSBezierPath {
        let c = pt(x, y), r = r * scale
        return NSBezierPath(ovalIn: NSRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2))
    }
    private static var leftNode: NSBezierPath { node(188.5, 424, 43) }
    private static var rightNode: NSBezierPath { node(403.5, 358, 45.5) }

    /// The trunk and both branches as one outline (strokes flattened and unioned so it fills cleanly).
    private static var wood: NSBezierPath {
        func stroked(_ width: CGFloat, _ build: (NSBezierPath) -> Void) -> CGPath {
            let path = NSBezierPath()
            build(path)
            return path.cgPath.copy(strokingWithWidth: width * scale, lineCap: .round, lineJoin: .round, miterLimit: 10)
        }
        let left = stroked(36) { p in
            p.move(to: pt(188.5, 424))
            p.line(to: pt(262, 518))
            p.curve(to: pt(292, 585), controlPoint1: pt(276, 542), controlPoint2: pt(292, 560))
        }
        let right = stroked(42) { p in
            p.move(to: pt(403.5, 358))
            p.curve(to: pt(292, 585), controlPoint1: pt(406, 448), controlPoint2: pt(308, 516))
        }
        let base = pt(261, 560), foot = pt(323, 670)
        let trunk = CGPath(roundedRect: CGRect(x: base.x, y: base.y, width: foot.x - base.x, height: foot.y - base.y),
                           cornerWidth: 14 * scale, cornerHeight: 14 * scale, transform: nil)
        // The crotch where the branches meet the trunk.
        let crotch = CGMutablePath()
        crotch.addLines(between: [pt(272, 548), pt(292, 524), pt(312, 548), pt(292, 590)])
        crotch.closeSubpath()
        return NSBezierPath(cgPath: [right, trunk, crotch].reduce(left) { $0.union($1) })
    }

    private static var mark: NSBezierPath {
        NSBezierPath(cgPath: wood.cgPath.union(leftNode.cgPath).union(rightNode.cgPath))
    }

    private static func drawTemplate() {
        NSColor.black.setFill()
        mark.fill()
    }

    private static func drawAccent() {
        NSGradient(starting: rgb(0xD1975A), ending: rgb(0xA3663A))?.draw(in: wood, angle: 90)
        NSGradient(starting: rgb(0x9EE367), ending: rgb(0x50BD43))?.draw(in: leftNode, angle: 45)
        NSGradient(starting: rgb(0xFD5F37), ending: rgb(0xED1417))?.draw(in: rightNode, angle: 45)
    }

    private static func rgb(_ hex: UInt32) -> NSColor {
        NSColor(srgbRed: CGFloat(hex >> 16 & 0xFF) / 255, green: CGFloat(hex >> 8 & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    }
}

/// The panel that drops down from the menu bar icon.
struct MenuBarPanel: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow

    private var sessions: [SessionSnapshot] {
        model.snapshot.sessions
            .filter { $0.status.display != .ended && $0.parent == nil }
            .sorted { a, b in
                if a.status.display != b.status.display { return a.status.display < b.status.display }
                return a.status.since > b.status.since
            }
    }

    /// A short strip of the main window's treeline: the same scene, shrunk most of the way.
    private static let headerHeight: CGFloat = 60

    var body: some View {
        TimelineView(.everyMinute) { context in
            let time = model.timeOfDay(at: context.date)
            panel
                .background { ForestBackground(time: time, headerHeight: Self.headerHeight) }
                .overlay(alignment: .top) {
                    ForestHeader(
                        collapse: (Metrics.headerHeight - Self.headerHeight) / Metrics.headerCollapseDistance,
                        time: time,
                        fireflies: model.fireflies,
                        skyDrop: 14,
                        fireflyDrop: 16
                    )
                    .frame(height: Self.headerHeight)
                    .overlay(alignment: .topLeading) { topStrip }
                }
        }
        .frame(width: 340)
        .foregroundStyle(Palette.textPrimary)
    }

    private var topStrip: some View {
        HStack {
            Text("BRANCHES")
                .font(Typo.wordmark)
                .tracking(1.6)
                .foregroundStyle(Palette.textPrimary.opacity(0.8))
            Spacer()
            if model.needsYouCount + model.workingCount > 0 {
                SummaryChip(waiting: model.needsYouCount, working: model.workingCount)
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 9)
    }

    private var panel: some View {
        VStack(alignment: .leading, spacing: 0) {
            Color.clear.frame(height: Self.headerHeight)

            if sessions.isEmpty {
                Text("No coding agents running.")
                    .font(Typo.caption)
                    .foregroundStyle(Palette.textSecondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
            } else {
                ScrollView {
                    VStack(spacing: 2) {
                        ForEach(sessions.prefix(12)) { session in
                            MenuBarRow(session: session)
                        }
                    }
                    .padding(6)
                }
                .frame(maxHeight: 420)
                .fixedSize(horizontal: false, vertical: true)
            }

            Rectangle().fill(Palette.bark.opacity(0.4)).frame(height: 0.5)

            HStack {
                Button("Open Branches") {
                    openWindow(id: "main")
                    NSApp.activate(ignoringOtherApps: true)
                }
                Spacer()
                Button("Quit") { NSApp.terminate(nil) }
            }
            .buttonStyle(.plain)
            .font(Typo.caption)
            .foregroundStyle(Palette.textSecondary)
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
        }
    }
}

private struct MenuBarRow: View {
    @Environment(AppModel.self) private var model
    let session: SessionSnapshot
    @State private var hovering = false

    var body: some View {
        Button { model.jump(session) } label: {
            HStack(alignment: .top, spacing: 8) {
                StatusNode(status: session.status)
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 6) {
                        Text(session.title)
                            .font(Typo.title)
                            .lineLimit(1)
                        Spacer(minLength: 6)
                        StatusTimeText(status: session.status)
                    }
                    Text("\(session.projectName) · \(session.provider.displayName)")
                        .font(Typo.caption)
                        .foregroundStyle(Palette.textSecondary)
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: Metrics.rowCorner).fill(hovering ? Palette.hover : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(session.status.display == .ended ? "Copy resume command" : "Jump to session")
    }
}
