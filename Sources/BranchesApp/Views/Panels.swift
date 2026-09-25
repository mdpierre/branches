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
            Toggle("Show in menu bar", isOn: $model.showMenuBarIcon)
                .toggleStyle(.switch)
                .controlSize(.small)
                .help("Keeps Branches running in the menu bar when you close the window")

            Divider()

            Text("Time of day").font(Typo.captionEmphasized).foregroundStyle(.secondary)
            Picker("Time of day", selection: $model.sceneTime) {
                Text("Auto").tag("auto")
                ForEach(TimeOfDay.allCases) { Text($0.label).tag($0.rawValue) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .controlSize(.small)
            .help("Auto follows your clock: dawn 5–9, day 9–17, dusk 17–20, night after that")

            Divider()

            Text("Notify me when a session…").font(Typo.captionEmphasized).foregroundStyle(.secondary)
            Toggle("Needs me", isOn: $model.notifyNeedsYou)
                .toggleStyle(.switch)
                .controlSize(.small)
                .disabled(!Notifier.shared.isAvailable)
            Toggle("Finishes a turn", isOn: $model.notifyDone)
                .toggleStyle(.switch)
                .controlSize(.small)
                .disabled(!Notifier.shared.isAvailable)
            if !Notifier.shared.isAvailable {
                Text("Notifications need the bundled app (scripts/bundle.sh).")
                    .font(Typo.caption)
                    .foregroundStyle(.tertiary)
            }

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
