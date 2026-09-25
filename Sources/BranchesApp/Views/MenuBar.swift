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

/// Drawn in code as a template image so it matches the menu bar's light/dark style.
enum MenuBarGlyph {
    @MainActor private static var cache: [Bool: NSImage] = [:]

    @MainActor
    static func image(alert: Bool) -> NSImage {
        if let cached = cache[alert] { return cached }
        let image = NSImage(size: NSSize(width: 16, height: 16), flipped: true) { _ in
            NSColor.black.set()
            let stroke = NSBezierPath()
            stroke.lineWidth = 1.6
            stroke.lineCapStyle = .round
            // Trunk
            stroke.move(to: NSPoint(x: 6.5, y: 15))
            stroke.line(to: NSPoint(x: 6.5, y: 8))
            stroke.curve(to: NSPoint(x: 5, y: 3.5), controlPoint1: NSPoint(x: 6.5, y: 6), controlPoint2: NSPoint(x: 5, y: 5))
            // Fork
            stroke.move(to: NSPoint(x: 6.5, y: 9))
            stroke.curve(to: NSPoint(x: 11, y: 5.5), controlPoint1: NSPoint(x: 6.5, y: 7), controlPoint2: NSPoint(x: 9, y: 6))
            stroke.stroke()
            NSBezierPath(ovalIn: NSRect(x: 3.2, y: 1.2, width: 3.6, height: 3.6)).fill()
            if alert {
                // A bigger ring-and-dot "attention node" at the end of the fork.
                let ring = NSBezierPath(ovalIn: NSRect(x: 9.2, y: 1.2, width: 6, height: 6))
                ring.lineWidth = 1.4
                ring.stroke()
                NSBezierPath(ovalIn: NSRect(x: 11.2, y: 3.2, width: 2, height: 2)).fill()
            } else {
                NSBezierPath(ovalIn: NSRect(x: 9.7, y: 3.7, width: 3.2, height: 3.2)).fill()
            }
            return true
        }
        image.isTemplate = true
        cache[alert] = image
        return image
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

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("BRANCHES")
                    .font(Typo.wordmark)
                    .tracking(1.2)
                    .foregroundStyle(Palette.textSecondary)
                Spacer()
                summary
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)

            Rectangle().fill(Palette.bark.opacity(0.4)).frame(height: 0.5)

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
        .frame(width: 340)
        .background {
            ZStack {
                VisualEffectBackground()
                Palette.window.opacity(0.82)
            }
        }
        .foregroundStyle(Palette.textPrimary)
    }

    @ViewBuilder private var summary: some View {
        let waiting = model.needsYouCount
        let working = model.workingCount
        HStack(spacing: 4) {
            if waiting > 0 { Text("\(waiting) need\(waiting == 1 ? "s" : "") you").foregroundStyle(Palette.amber) }
            if waiting > 0 && working > 0 { Text("·").foregroundStyle(Palette.textTertiary) }
            if working > 0 { Text("\(working) working").foregroundStyle(Palette.textSecondary) }
        }
        .font(Typo.captionEmphasized)
        .monospacedDigit()
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
                    .frame(width: 16, height: 16)
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
