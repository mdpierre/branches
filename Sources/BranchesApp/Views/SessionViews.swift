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
                let taper = CGFloat(index) / CGFloat(max(group.rows.count, 1))
                SessionRowView(row: row, isLast: isLast, hasChildBelow: nextIsChild, trunkWidth: 2.6 - taper * 1.1)
                    .id(row.id)
            }

            if group.endedCount > 0 {
                Button {
                    if model.expandedEnded.contains(group.path) { model.expandedEnded.remove(group.path) }
                    else { model.expandedEnded.insert(group.path) }
                } label: {
                    HStack(spacing: 0) {
                        BranchConnector(depth: 0, isLast: true, hasChildBelow: false, trunkWidth: 1.4)
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
    let trunkWidth: CGFloat
    @State private var hovering = false

    private var session: SessionSnapshot { row.session }
    private var isSelected: Bool { model.selection == session.id }
    private var indent: CGFloat { CGFloat(row.depth) * 16 }

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            BranchConnector(depth: row.depth, isLast: isLast, hasChildBelow: hasChildBelow, trunkWidth: trunkWidth)
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
            return s.needsYouText
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

// MARK: - Branch connector

/// The trunk runs down the left of a project group, thinning toward its last row; each row
/// gets a twig that curves up into its glyph. Subagents grow from their parent's glyph.
struct BranchConnector: View {
    let depth: Int
    let isLast: Bool
    let hasChildBelow: Bool
    /// Trunk thickness for this row (thicker at the top of the group).
    var trunkWidth: CGFloat = 1.5

    /// How far below the glyph the twig leaves the trunk.
    private static let twigDrop: CGFloat = 16.5

    var body: some View {
        Canvas { ctx, size in
            let trunkX: CGFloat = 8
            let y = Metrics.elbowY
            let nodeX = Metrics.connectorWidth + CGFloat(depth) * 16
            let twigStart = y + Self.twigDrop

            var trunk = Path()
            trunk.move(to: CGPoint(x: trunkX, y: 0))
            trunk.addLine(to: CGPoint(x: trunkX, y: isLast && depth == 0 ? twigStart : size.height))
            ctx.stroke(trunk, with: .color(Palette.trunk), style: StrokeStyle(lineWidth: trunkWidth, lineCap: .round))

            var twig = Path()
            if depth == 0 {
                twig.move(to: CGPoint(x: trunkX, y: twigStart))
                twig.addCurve(to: CGPoint(x: nodeX + 1, y: y),
                              control1: CGPoint(x: trunkX, y: y + 7.5),
                              control2: CGPoint(x: trunkX + 4.5, y: y + 1))
            } else {
                // Grows from the parent's glyph, just above this row.
                let forkX = Metrics.connectorWidth + Metrics.nodeColumn / 2 + CGFloat(depth - 1) * 16
                twig.move(to: CGPoint(x: forkX, y: 0))
                twig.addCurve(to: CGPoint(x: nodeX + 2, y: y),
                              control1: CGPoint(x: forkX, y: y * 0.7),
                              control2: CGPoint(x: forkX + 3, y: y))
            }
            if hasChildBelow {
                // The start of a subagent's twig, down from this row's glyph.
                let childForkX = Metrics.connectorWidth + Metrics.nodeColumn / 2 + CGFloat(depth) * 16
                twig.move(to: CGPoint(x: childForkX, y: y + 10))
                twig.addLine(to: CGPoint(x: childForkX, y: size.height))
            }
            ctx.stroke(twig, with: .color(Palette.trunk), style: StrokeStyle(lineWidth: depth == 0 ? 1.5 : 1.2, lineCap: .round))
        }
    }
}

// MARK: - Helpers

func abbreviate(_ path: String) -> String {
    let home = FileManager.default.homeDirectoryForCurrentUser.path
    return path.hasPrefix(home) ? "~" + path.dropFirst(home.count) : path
}
