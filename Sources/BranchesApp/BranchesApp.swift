import AppKit
import BranchesKit
import SwiftUI

@main
struct BranchesApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var model = AppModel()

    var body: some Scene {
        Window("Branches", id: "main") {
            ContentView()
                .environment(model)
                .task { model.start() }
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 400, height: 560)
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandMenu("Session") {
                Button("Jump to Session") { model.selectedSession.map(model.jump) }
                    .keyboardShortcut(.return, modifiers: .command)
                Button("Open Project Folder") { model.selectedSession.map(model.openFolder) }
                    .keyboardShortcut("o")
                Button("Copy Resume Command") { model.selectedSession.map(model.copyResume) }
                    .keyboardShortcut("c", modifiers: [.command, .shift])
                Divider()
                ForEach(0..<9) { i in
                    Button("Jump to Waiting Session \(i + 1)") { model.jumpToNeedsYou(i) }
                        .keyboardShortcut(KeyEquivalent(Character("\(i + 1)")), modifiers: .command)
                }
                Divider()
                Toggle("Show Ended Sessions", isOn: $model.showEnded)
            }
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Needed when launched as a bare executable (`swift run`); harmless in a bundle.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}
