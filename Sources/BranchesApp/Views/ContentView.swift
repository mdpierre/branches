import AppKit
import BranchesKit
import SwiftUI

struct ContentView: View {
    @Environment(AppModel.self) private var model
    @FocusState private var focused: Bool
    @State private var showSettings = false

    var body: some View {
        VStack(spacing: 0) {
            topStrip
            Rectangle().fill(Palette.bark.opacity(0.4)).frame(height: 0.5)
            if model.snapshot.sessions.isEmpty {
                EmptyStateView(diagnostics: model.snapshot.diagnostics)
            } else if model.groups.isEmpty {
                Text(model.filter.isEmpty ? "Nothing active. Ended sessions are hidden." : "No sessions match “\(model.filter)”.")
                    .font(Typo.caption)
                    .foregroundStyle(Palette.textSecondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                sessionList
            }
        }
        .overlay(alignment: .bottom) { toast }
        .background {
            ZStack {
                VisualEffectBackground()
                Palette.window.opacity(0.82)
            }
            .ignoresSafeArea()
        }
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

    private var topStrip: some View {
        HStack(spacing: 8) {
            Text("BRANCHES")
                .font(Typo.wordmark)
                .tracking(1.2)
                .foregroundStyle(Palette.textSecondary)
            if !model.filter.isEmpty {
                HStack(spacing: 4) {
                    Image(systemName: "line.3.horizontal.decrease")
                    Text(model.filter)
                    Button { model.filter = "" } label: { Image(systemName: "xmark.circle.fill") }
                        .buttonStyle(.plain)
                }
                .font(Typo.caption)
                .foregroundStyle(Palette.textSecondary)
            }
            Spacer()
            summaryChip
            Button { showSettings.toggle() } label: {
                Image(systemName: "ellipsis")
                    .frame(width: 20, height: 20)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(Palette.textSecondary)
            .popover(isPresented: $showSettings, arrowEdge: .bottom) {
                SettingsPopover().environment(model)
            }
            .help("Settings & diagnostics")
        }
        .padding(.leading, 78) // clear the traffic lights
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
                        Text("\(waiting) need\(waiting == 1 ? "s" : "") you").foregroundStyle(Palette.amber)
                    }
                    if waiting > 0 && working > 0 { Text("·").foregroundStyle(Palette.textTertiary) }
                    if working > 0 {
                        Text("\(working) working").foregroundStyle(Palette.textSecondary)
                    }
                }
                .font(Typo.captionEmphasized)
                .monospacedDigit()
            }
            .buttonStyle(.plain)
            .help("Tab cycles through sessions that need you")
        }
    }

    private var sessionList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: Metrics.groupSpacing) {
                    ForEach(model.groups) { group in
                        ProjectGroupView(group: group)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 12)
                .animation(.easeOut(duration: 0.2), value: model.flatRows.map(\.id))
            }
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
