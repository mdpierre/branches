import AppKit
import BranchesKit
import SwiftUI

struct ContentView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var focused: Bool
    @State private var showSettings = false
    @State private var scrollOffset: CGFloat = 0

    var body: some View {
        TimelineView(.everyMinute) { context in
            let time = model.timeOfDay(at: context.date)
            GeometryReader { geo in
                let compact = geo.size.height < Metrics.compactWindowHeight
                let c = collapse(compact: compact)
                ZStack(alignment: .top) {
                    content(top: compact ? Metrics.headerCollapsed : Metrics.headerHeight)
                    ForestHeader(collapse: c, time: time, fireflies: model.fireflies)
                        .frame(height: Metrics.headerHeight + (Metrics.headerCollapsed - Metrics.headerHeight) * c)
                        .overlay(alignment: .bottom) {
                            Rectangle().fill(Palette.bark.opacity(0.5 * c)).frame(height: 0.5)
                        }
                    topStrip
                        .padding(.leading, 16 + (78 - 16) * c) // shrunk: beside the traffic lights
                        .padding(.top, 32 * (1 - c))
                }
                .background { ForestBackground(time: time) }
            }
            .ignoresSafeArea()
        }
        .overlay(alignment: .bottom) { toast }
        .foregroundStyle(Palette.textPrimary)
        .frame(minWidth: 320, minHeight: 280)
        .focusable()
        .focused($focused)
        .focusEffectDisabled()
        .onKeyPress(.upArrow) { model.moveSelection(-1); return .handled }
        .onKeyPress(.downArrow) { model.moveSelection(1); return .handled }
        .onKeyPress(.return) {
            model.selectedSession.map(model.jump)
            return .handled
        }
        .onKeyPress(.tab) { model.cycleNeedsYou(); return .handled }
        .onKeyPress(.escape) { model.filter = ""; return .handled }
        .onKeyPress(.delete) {
            if !model.filter.isEmpty { model.filter.removeLast() }
            return .handled
        }
        .onKeyPress(phases: .down) { press in
            guard press.modifiers.subtracting(.shift).isEmpty,
                  let scalar = press.characters.unicodeScalars.first,
                  CharacterSet.alphanumerics.union(.punctuationCharacters).union(.whitespaces).contains(scalar)
            else { return .ignored }
            model.filter += press.characters
            return .handled
        }
        .onAppear { focused = true }
    }

    /// 0 = header at rest, 1 = shrunk. Short windows keep it shrunk; Reduce Motion snaps between the two.
    private func collapse(compact: Bool) -> CGFloat {
        if compact { return 1 }
        let raw = min(max(scrollOffset / Metrics.headerCollapseDistance, 0), 1)
        return reduceMotion ? (raw < 0.5 ? 0 : 1) : raw
    }

    @ViewBuilder private func content(top: CGFloat) -> some View {
        if model.snapshot.sessions.isEmpty {
            EmptyStateView(diagnostics: model.snapshot.diagnostics)
                .padding(.top, top)
        } else if model.groups.isEmpty {
            Text(model.filter.isEmpty ? "Nothing active. Ended sessions are hidden." : "No sessions match “\(model.filter)”.")
                .font(Typo.caption)
                .foregroundStyle(Palette.textSecondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.top, top)
        } else {
            sessionList(top: top)
        }
    }

    private var topStrip: some View {
        HStack(spacing: 6) {
            Text("BRANCHES")
                .font(Typo.wordmark)
                .tracking(1.6)
                .foregroundStyle(Palette.textPrimary.opacity(0.8))
            if !model.filter.isEmpty {
                HStack(spacing: 4) {
                    Image(systemName: "line.3.horizontal.decrease")
                    Text(model.filter)
                    Button { model.filter = "" } label: { Image(systemName: "xmark.circle.fill") }
                        .buttonStyle(.plain)
                }
                .font(Typo.caption)
                .foregroundStyle(Palette.textSecondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Capsule().fill(Palette.chip))
            }
            Spacer()
            summaryChip
            Button { showSettings.toggle() } label: {
                Image(systemName: "ellipsis")
                    .frame(width: 26, height: 22)
                    .background(Capsule().fill(Palette.chip))
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .foregroundStyle(Palette.textSecondary)
            .popover(isPresented: $showSettings, arrowEdge: .bottom) {
                SettingsPopover().environment(model)
            }
            .help("Settings & diagnostics")
        }
        .padding(.trailing, 12)
        .frame(height: 30)
    }

    @ViewBuilder private var summaryChip: some View {
        let waiting = model.needsYouCount
        let working = model.workingCount
        if waiting + working > 0 {
            Button { model.cycleNeedsYou() } label: {
                HStack(spacing: 4) {
                    if waiting > 0 {
                        LanternShape().scaleEffect(0.65).frame(width: 13, height: 13)
                        Text("\(waiting) need\(waiting == 1 ? "s" : "") you").foregroundStyle(Palette.amber)
                    }
                    if waiting > 0 && working > 0 { Text("·").foregroundStyle(Palette.textTertiary) }
                    if working > 0 {
                        SproutShape().scaleEffect(0.65).frame(width: 13, height: 13)
                        Text("\(working) working").foregroundStyle(Palette.textSecondary)
                    }
                }
                .font(Typo.captionEmphasized)
                .monospacedDigit()
                .padding(.leading, 6)
                .padding(.trailing, 9)
                .frame(height: 22)
                .background(Capsule().fill(Palette.chip))
            }
            .buttonStyle(.plain)
            .help("Tab cycles through sessions that need you")
        }
    }

    private func sessionList(top: CGFloat) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: Metrics.groupSpacing) {
                    ForEach(model.groups) { group in
                        ProjectGroupView(group: group)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.top, top + 4)
                .padding(.bottom, 16)
                .animation(.easeOut(duration: 0.2), value: model.flatRows.map(\.id))
                .background { ScrollOffsetReader(offset: $scrollOffset) }
            }
            .contentMargins(.top, top, for: .scrollIndicators)
            .scrollIndicators(.automatic)
            .onChange(of: model.selection) { _, key in
                if let key { withAnimation(.easeOut(duration: 0.15)) { proxy.scrollTo(key) } }
            }
        }
    }

    @ViewBuilder private var toast: some View {
        if let message = model.toast {
            Text(message)
                .font(Typo.caption)
                .foregroundStyle(Palette.textPrimary)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(RoundedRectangle(cornerRadius: 8).fill(Palette.moss.opacity(0.95)))
                .padding(12)
                .transition(.opacity.combined(with: .move(edge: .bottom)))
                .animation(.easeOut(duration: 0.2), value: model.toast)
        }
    }
}

/// Reports how far the enclosing scroll view has scrolled. A GeometryReader in the scroll content
/// doesn't re-report on macOS as the list scrolls (and `onScrollGeometryChange` needs macOS 15),
/// so this watches the NSScrollView's clip view directly.
private struct ScrollOffsetReader: NSViewRepresentable {
    @Binding var offset: CGFloat

    func makeNSView(context: Context) -> ProbeView {
        let view = ProbeView()
        view.onChange = { value in
            if abs(offset - value) > 0.5 { offset = value }
        }
        return view
    }

    func updateNSView(_ view: ProbeView, context: Context) {}

    final class ProbeView: NSView {
        var onChange: ((CGFloat) -> Void)?
        private var observer: NSObjectProtocol?

        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let observer { NotificationCenter.default.removeObserver(observer) }
            observer = nil
            guard let clip = enclosingScrollView?.contentView else { return }
            clip.postsBoundsChangedNotifications = true
            observer = NotificationCenter.default.addObserver(
                forName: NSView.boundsDidChangeNotification, object: clip, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.report(clip) }
            }
            report(clip)
        }

        private func report(_ clip: NSClipView) {
            let y: CGFloat
            if let document = clip.documentView, !document.isFlipped {
                y = document.frame.height - clip.bounds.maxY
            } else {
                y = clip.bounds.minY
            }
            onChange?(y + clip.contentInsets.top)
        }
    }
}

struct VisualEffectBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .sidebar
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}
