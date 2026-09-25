import AppKit
import BranchesKit
import SwiftUI

// MARK: - Project group

struct ProjectGroupView: View {
    @Environment(AppModel.self) private var model
    let group: ProjectGroup
    @State private var hovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text(group.name).font(Typo.project)
                Spacer(minLength: 8)
                Text(abbreviate(group.path))
                    .font(Typo.mono)
                    .foregroundStyle(Palette.textTertiary)
                    .lineLimit(1)
                    .truncationMode(.head)
                    .opacity(hovering ? 1 : 0)
            }
            .padding(.leading, 2)
            .padding(.trailing, 6)
            .padding(.bottom, 2)

            ForEach(Array(group.rows.enumerated()), id: \.element.id) { index, row in
                let isLast = index == group.rows.count - 1 && group.endedCount == 0
                let nextIsChild = index + 1 < group.rows.count && group.rows[index + 1].depth > row.depth
                SessionRowView(row: row, isLast: isLast, hasChildBelow: nextIsChild, trunkContinues: !isLast)
                    .id(row.id)
            }

            if group.endedCount > 0 {
                Button {
                    if model.expandedEnded.contains(group.path) { model.expandedEnded.remove(group.path) }
                    else { model.expandedEnded.insert(group.path) }
                } label: {
                    HStack(spacing: 0) {
                        BranchConnector(depth: 0, isLast: true, hasChildBelow: false)
                            .frame(width: Metrics.connectorWidth, height: 24)
                        Text("\(group.endedCount) ended")
                            .font(Typo.caption)
                            .foregroundStyle(Palette.textTertiary)
                            .padding(.leading, 4)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .onHover { hovering = $0 }
    }
}

// MARK: - Session row

struct SessionRowView: View {
    @Environment(AppModel.self) private var model
    let row: ProjectGroup.Row
    let isLast: Bool
    let hasChildBelow: Bool
    let trunkContinues: Bool
    @State private var hovering = false

    private var session: SessionSnapshot { row.session }
    private var isSelected: Bool { model.selection == session.id }
    private var indent: CGFloat { CGFloat(row.depth) * 16 }

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            BranchConnector(depth: row.depth, isLast: isLast, hasChildBelow: hasChildBelow)
                .frame(width: Metrics.connectorWidth + indent)
            StatusNode(status: session.status)
                .frame(width: Metrics.nodeColumn, height: Metrics.elbowY * 2)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(session.provider.displayName)
                        .font(Typo.captionEmphasized)
                        .foregroundStyle(Palette.textSecondary)
                        .frame(width: 44, alignment: .leading)
                    Text(session.title)
                        .font(Typo.title)
                        .foregroundStyle(session.status.display == .idle ? Palette.textSecondary : Palette.textPrimary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Spacer(minLength: 6)
                    if hovering {
                        Button { model.jump(session) } label: {
                            Image(systemName: "arrow.turn.down.left")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(Palette.textSecondary)
                        }
                        .buttonStyle(.plain)
                        .help(session.status.display == .ended ? "Copy resume command" : "Jump to session")
                    }
                    StatusTimeText(status: session.status)
                }
                .frame(height: Metrics.elbowY * 2 - 4)
                Text(secondLine)
                    .font(Typo.caption)
                    .foregroundStyle(Palette.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .padding(.leading, 50)
            }
            .padding(.top, 2)
            .padding(.bottom, 7)
            .padding(.leading, 4)
            .padding(.trailing, 10)
            .background(alignment: .leading) {
                RoundedRectangle(cornerRadius: Metrics.rowCorner)
                    .fill(isSelected ? Palette.selection : hovering ? Palette.hover : .clear)
                    .overlay(alignment: .leading) {
                        if isSelected {
                            RoundedRectangle(cornerRadius: 1).fill(Palette.leaf).frame(width: 2).padding(.vertical, 6)
                        }
                    }
                    .padding(.leading, -Metrics.nodeColumn - 2)
            }
        }
        .opacity(session.status.display == .ended ? 0.5 : 1)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture(count: 2) { model.jump(session) }
        .onTapGesture { model.selection = session.id }
        .contextMenu { menu }
        .help(tooltip)
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    private var secondLine: String {
        let s = session
        switch s.status.display {
        case .needsYou:
            if s.status.attention == .error { return "Stopped with an error" }
            return s.activity.map { "\($0) · waiting for approval" } ?? "Waiting for approval"
        case .working:
            return s.activity ?? "Working"
        case .ended:
            return "Exited · double-click to copy resume command"
        case .done, .idle:
            if s.status.confidence == .unknown { return "No recent activity" }
            return hostLine ?? s.lastPrompt.map { "Last: \($0)" } ?? abbreviate(s.cwd)
        }
    }

    private var hostLine: String? {
        guard let host = session.host else { return nil }
        if let tty = session.tty, host.kind == .terminal || host.kind == .iTerm { return "\(host.name) · \(tty)" }
        return host.name
    }

    private var tooltip: String {
        let s = session.status
        var parts = ["\(s.display.label) (\(s.confidence.rawValue)): \(s.reason)"]
        if let p = session.lastPrompt { parts.append("Last prompt: \(p)") }
        parts.append(session.cwd)
        return parts.joined(separator: "\n")
    }

    @ViewBuilder private var menu: some View {
        Button(session.status.display == .ended ? "Copy Resume Command" : "Jump to Session") { model.jump(session) }
        Button("Open Project Folder") { model.openFolder(session) }
        Divider()
        Button("Copy Resume Command") { model.copyResume(session) }
        Button("Copy Session ID") { model.copySessionID(session) }
    }
}

// MARK: - Status time

struct StatusTimeText: View {
    let status: StatusResult

    var body: some View {
        let live = status.display == .working || status.display == .needsYou
        TimelineView(.periodic(from: .now, by: live ? 1 : 30)) { context in
            Text("\(status.display.label) · \(format(context.date.timeIntervalSince(status.since), live: live))")
                .font(Typo.caption)
                .monospacedDigit()
                .foregroundStyle(status.display == .needsYou ? Palette.color(for: status) : Palette.textSecondary)
                .lineLimit(1)
                .fixedSize()
        }
    }

    private func format(_ seconds: TimeInterval, live: Bool) -> String {
        let s = max(0, Int(seconds))
        if live {
            if s < 60 { return "\(s)s" }
            if s < 3600 { return "\(s / 60)m \(s % 60)s" }
            return "\(s / 3600)h \(s % 3600 / 60)m"
        }
        if s < 60 { return "just now" }
        if s < 3600 { return "\(s / 60)m ago" }
        if s < 86400 { return "\(s / 3600)h ago" }
        return "\(s / 86400)d ago"
    }
}

// MARK: - Status node

struct StatusNode: View {
    let status: StatusResult
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            switch status.display {
            case .working:
                if !reduceMotion {
                    BreathingGlow(color: NSColor(Palette.leaf)).frame(width: 16, height: 16)
                }
                Circle().fill(Palette.leaf).frame(width: 8, height: 8)
            case .needsYou:
                let color = Palette.color(for: status)
                Circle().strokeBorder(color, lineWidth: 2).frame(width: 11, height: 11)
                if status.attention == .error {
                    Text("!").font(.system(size: 8, weight: .heavy)).foregroundStyle(color)
                } else {
                    Circle().fill(color).frame(width: 4, height: 4)
                }
            case .done:
                Circle().strokeBorder(Palette.cream, lineWidth: 1.5).frame(width: 9, height: 9)
            case .idle:
                if status.confidence == .unknown {
                    Circle()
                        .strokeBorder(Palette.textTertiary, style: StrokeStyle(lineWidth: 1.2, dash: [1.5, 1.5]))
                        .frame(width: 9, height: 9)
                } else {
                    Circle().fill(Palette.moss).frame(width: 6, height: 6)
                }
            case .ended:
                Capsule().fill(Palette.bark).frame(width: 5, height: 2)
            }
        }
        .animation(.easeInOut(duration: 0.15), value: status.display)
        .accessibilityLabel(status.display.label)
    }
}

/// The "living" pulse behind a working node. Runs as a Core Animation layer animation,
/// so it costs the app no CPU (a SwiftUI repeatForever animation re-lays out every frame).
struct BreathingGlow: NSViewRepresentable {
    let color: NSColor

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        view.wantsLayer = true
        let glow = CALayer()
        glow.cornerRadius = 8
        glow.frame = CGRect(x: 0, y: 0, width: 16, height: 16)
        view.layer?.addSublayer(glow)
        let pulse = CABasicAnimation(keyPath: "opacity")
        pulse.fromValue = 0.08
        pulse.toValue = 0.4
        pulse.duration = 1.2
        pulse.autoreverses = true
        pulse.repeatCount = .infinity
        pulse.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        glow.add(pulse, forKey: "breathe")
        updateColor(glow, view: view)
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        if let glow = view.layer?.sublayers?.first { updateColor(glow, view: view) }
    }

    private func updateColor(_ layer: CALayer, view: NSView) {
        view.effectiveAppearance.performAsCurrentDrawingAppearance {
            layer.backgroundColor = color.cgColor
        }
    }
}

// MARK: - Branch connector

/// The trunk runs down the left of a project group; each row gets an elbow into its node.
/// Subagents fork from their parent's node.
struct BranchConnector: View {
    let depth: Int
    let isLast: Bool
    let hasChildBelow: Bool

    var body: some View {
        Canvas { ctx, size in
            let trunkX: CGFloat = 8
            let y = Metrics.elbowY
            let nodeX = Metrics.connectorWidth + CGFloat(depth) * 16
            var path = Path()
            // Trunk
            path.move(to: CGPoint(x: trunkX, y: 0))
            path.addLine(to: CGPoint(x: trunkX, y: isLast && depth == 0 ? y - 4 : size.height))
            if depth == 0 {
                // Rounded elbow into the node
                path.move(to: CGPoint(x: trunkX, y: y - 4))
                path.addQuadCurve(to: CGPoint(x: trunkX + 4, y: y), control: CGPoint(x: trunkX, y: y))
                path.addLine(to: CGPoint(x: nodeX - 1, y: y))
            } else {
                // Fork from the parent's node column
                let forkX = Metrics.connectorWidth + Metrics.nodeColumn / 2 + CGFloat(depth - 1) * 16
                path.move(to: CGPoint(x: forkX, y: 0))
                path.addLine(to: CGPoint(x: forkX, y: y - 4))
                path.addQuadCurve(to: CGPoint(x: forkX + 4, y: y), control: CGPoint(x: forkX, y: y))
                path.addLine(to: CGPoint(x: nodeX - 1, y: y))
            }
            ctx.stroke(path, with: .color(Palette.bark), lineWidth: 1)
        }
    }
}

// MARK: - Helpers

func abbreviate(_ path: String) -> String {
    let home = FileManager.default.homeDirectoryForCurrentUser.path
    return path.hasPrefix(home) ? "~" + path.dropFirst(home.count) : path
}
