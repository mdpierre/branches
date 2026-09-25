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

        MenuBarExtra(isInserted: $model.showMenuBarIcon) {
            MenuBarPanel().environment(model)
        } label: {
            MenuBarLabel().environment(model)
        }
        .menuBarExtraStyle(.window)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Needed when launched as a bare executable (`swift run`); harmless in a bundle.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        Notifier.shared.install()

        // `--screenshot <path.png> [--menu-screenshot <path.png>]`: render the demo window (and
        // the menu bar panel) to PNGs and quit. Used for the README.
        let args = CommandLine.arguments
        func value(after flag: String) -> URL? {
            guard let i = args.firstIndex(of: flag), i + 1 < args.count else { return nil }
            return URL(fileURLWithPath: args[i + 1])
        }
        if let url = value(after: "--screenshot") {
            NSApp.appearance = NSAppearance(named: .darkAqua) // dark is the primary theme
            let menuURL = value(after: "--menu-screenshot")
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                if let window = NSApp.windows.first(where: { $0.isVisible && $0.contentView != nil }) {
                    window.setContentSize(NSSize(width: 460, height: 532))
                    Self.capture(window.contentView?.superview ?? window.contentView, to: url)
                }
                if let menuURL, let model = AppModel.current {
                    let host = NSHostingView(rootView: MenuBarPanel().environment(model).preferredColorScheme(.dark))
                    let panel = NSWindow(contentRect: NSRect(x: -4000, y: 0, width: 340, height: 400),
                                         styleMask: [.borderless], backing: .buffered, defer: false)
                    panel.appearance = NSAppearance(named: .darkAqua)
                    panel.contentView = host
                    panel.setContentSize(host.fittingSize)
                    panel.orderFront(nil)
                    Self.capture(host, to: menuURL, background: NSColor(srgbRed: 0.16, green: 0.17, blue: 0.16, alpha: 1))
                }
                NSApp.terminate(nil)
            }
        }
    }

    @MainActor
    private static func capture(
        _ view: NSView?, to url: URL,
        background: NSColor = NSColor(srgbRed: 0x14 / 255, green: 0x16 / 255, blue: 0x13 / 255, alpha: 1)
    ) {
        guard let view else { return }
        view.layoutSubtreeIfNeeded()
        view.displayIfNeeded()
        // Always render at 2x so the image is crisp regardless of the current display.
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: Int(view.bounds.width * 2), pixelsHigh: Int(view.bounds.height * 2),
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        ) else { return }
        rep.size = view.bounds.size
        view.cacheDisplay(in: view.bounds, to: rep)

        // Flatten onto the window color with rounded corners, like a real macOS window.
        let size = view.bounds.size
        let image = NSImage(size: size, flipped: false) { rect in
            let clip = NSBezierPath(roundedRect: rect, xRadius: 12, yRadius: 12)
            clip.addClip()
            background.setFill()
            rect.fill()
            rep.draw(in: rect)
            return true
        }
        guard let out = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: rep.pixelsWide, pixelsHigh: rep.pixelsHigh,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        ) else { return }
        out.size = size
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: out)
        image.draw(in: NSRect(origin: .zero, size: size))
        NSGraphicsContext.restoreGraphicsState()
        guard let png = out.representation(using: .png, properties: [:]) else { return }
        try? png.write(to: url)
    }

    /// With the menu bar icon on, closing the window keeps Branches watching in the menu bar.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        !UserDefaults.standard.bool(forKey: AppModel.menuBarKey)
    }
}
