import BranchesKit
import SwiftUI

struct EmptyStateView: View {
    let diagnostics: [ProviderDiagnostics]

    var body: some View {
        VStack(spacing: 10) {
            Text("No coding agents running.")
                .font(Typo.title)
                .foregroundStyle(Palette.textSecondary)
            Text("Branches watches Claude Code and Codex automatically.\nStart one in any terminal.")
                .font(Typo.caption)
                .foregroundStyle(Palette.textTertiary)
                .multilineTextAlignment(.center)
            VStack(alignment: .leading, spacing: 3) {
                ForEach(diagnostics, id: \.provider) { d in
                    HStack(spacing: 6) {
                        Image(systemName: d.rootExists ? "checkmark" : "minus")
                            .foregroundStyle(d.rootExists ? Palette.leaf : Palette.textTertiary)
                        Text(abbreviate(d.root)).font(Typo.mono)
                        Text(d.rootExists ? "" : "not found").font(Typo.caption)
                    }
                    .foregroundStyle(Palette.textTertiary)
                }
            }
            .padding(.top, 6)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct SettingsPopover: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        VStack(alignment: .leading, spacing: 12) {
            Toggle("Show ended sessions", isOn: $model.showEnded)
                .toggleStyle(.switch)
                .controlSize(.small)

            Divider()

            Text("Watching").font(Typo.captionEmphasized).foregroundStyle(.secondary)
            ForEach(model.snapshot.diagnostics, id: \.provider) { d in
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text(d.provider == .claude ? "Claude Code" : "Codex").font(Typo.captionEmphasized)
                        Spacer()
                        Text(d.rootExists ? "OK" : "Not installed")
                            .font(Typo.caption)
                            .foregroundStyle(d.rootExists ? Palette.leaf : .secondary)
                    }
                    Text(abbreviate(d.root)).font(Typo.mono).foregroundStyle(.secondary)
                    Text(summary(d)).font(Typo.caption).foregroundStyle(.secondary)
                }
            }

            Divider()

            Text("Branches watches your local coding-agent sessions locally and does not send their contents anywhere.")
                .font(Typo.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Text("Double-click or Return to jump · ⌘O folder · ⇧⌘C resume · Tab cycles “Needs you” · type to filter")
                .font(Typo.caption)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(width: 290)
    }

    private func summary(_ d: ProviderDiagnostics) -> String {
        var s = "\(d.filesTracked) files · \(d.linesParsed) lines read"
        if d.linesSkipped > 0 { s += " · \(d.linesSkipped) unreadable" }
        if let v = d.formatVersions.sorted().last { s += " · v\(v)" }
        return s
    }
}
