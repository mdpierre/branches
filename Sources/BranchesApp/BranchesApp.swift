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

        // `--screenshot <path.png> [--menu-screenshot <path.png>] [--window-size 460x620] [--scene dusk] [--scroll 120]`:
        // render the demo window (and the menu bar panel) to PNGs and quit. Used for the README.
        let args = CommandLine.arguments
        func value(after flag: String) -> URL? {
            guard let i = args.firstIndex(of: flag), i + 1 < args.count else { return nil }
            return URL(fileURLWithPath: args[i + 1])
        }
        if let url = value(after: "--screenshot") {
            NSApp.appearance = NSAppearance(named: .darkAqua) // dark is the primary theme
            let menuURL = value(after: "--menu-screenshot")
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                // Launched as a bare executable from a shell, SwiftUI sometimes doesn't open the
                // main window (it depends on whether macOS let the app activate). Stand one in.
                if Self.mainWindow == nil, let model = AppModel.current { Self.openStandIn(model) }
                Self.mainWindow?.setContentSize(Self.screenshotSize(args))
            }
            if let i = args.firstIndex(of: "--scroll"), i + 1 < args.count, let offset = Double(args[i + 1]) {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
                    if let view = Self.mainWindow?.contentView,
                       let scroll = Self.firstScrollView(in: view),
                       let wheel = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 1,
                                           wheel1: Int32(-offset), wheel2: 0, wheel3: 0),
                       let event = NSEvent(cgEvent: wheel) {
                        // A real scroll-wheel event, so SwiftUI sees the scroll the way it sees a user's.
                        scroll.scrollWheel(with: event)
                    }
                }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                if let window = Self.mainWindow,
                   !Self.captureOnScreen(window, to: url) {
                    Self.capture(window.contentView?.superview ?? window.contentView, to: url)
                }
                if let menuURL, let model = AppModel.current {
                    let host = NSHostingView(rootView: MenuBarPanel().environment(model).preferredColorScheme(.dark))
                    host.wantsLayer = true
                    host.layer?.cornerRadius = 10
                    host.layer?.masksToBounds = true
                    let panel = NSWindow(contentRect: NSRect(x: 240, y: 240, width: 340, height: 400),
                                         styleMask: [.borderless], backing: .buffered, defer: false)
                    panel.appearance = NSAppearance(named: .darkAqua)
                    panel.isOpaque = false
                    panel.backgroundColor = .clear
                    panel.contentView = host
                    panel.setContentSize(host.fittingSize)
                    panel.orderFront(nil)
                    // Give the fireflies and sprouts a moment to render before capturing.
                    RunLoop.main.run(until: Date().addingTimeInterval(0.5))
                    if !Self.captureOnScreen(panel, to: menuURL) {
                        Self.capture(host, to: menuURL, background: NSColor(srgbRed: 0.16, green: 0.17, blue: 0.16, alpha: 1))
                    }
                }
                NSApp.terminate(nil)
            }
        }
    }

    /// The window as the window server composites it, so Core Animation layers (the fireflies, the
    /// swaying sprouts) and the list's scroll view are included. Needs Screen Recording permission for
    /// whatever launched the app; returns false without it, and the caller falls back to `capture`.
    @MainActor
    private static func captureOnScreen(_ window: NSWindow, to url: URL) -> Bool {
        try? FileManager.default.removeItem(at: url)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        process.arguments = ["-x", "-o", "-l", "\(window.windowNumber)", url.path]
        guard (try? process.run()) != nil else { return false }
        process.waitUntilExit()
        return process.terminationStatus == 0 && FileManager.default.fileExists(atPath: url.path)
    }

    @MainActor private static var standIn: NSWindow?

    /// A window like the SwiftUI one (hidden title bar, content under the traffic lights).
    @MainActor
    private static func openStandIn(_ model: AppModel) {
        let window = NSWindow(
            contentRect: NSRect(x: 200, y: 200, width: 400, height: 560),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered, defer: false
        )
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: ContentView().environment(model).task { model.start() })
        window.makeKeyAndOrderFront(nil)
        standIn = window
    }

    /// The Branches window, not the menu bar icon's status-bar window (which is also "visible").
    @MainActor
    private static var mainWindow: NSWindow? {
        NSApp.windows.first { $0.isVisible && $0.styleMask.contains(.titled) }
    }

    @MainActor
    private static func firstScrollView(in view: NSView) -> NSScrollView? {
        if let scroll = view as? NSScrollView { return scroll }
        for sub in view.subviews { if let found = firstScrollView(in: sub) { return found } }
        return nil
    }

    private static func screenshotSize(_ args: [String]) -> NSSize {
        if let i = args.firstIndex(of: "--window-size"), i + 1 < args.count {
            let parts = args[i + 1].split(separator: "x").compactMap { Double($0) }
            if parts.count == 2 { return NSSize(width: parts[0], height: parts[1]) }
        }
        return NSSize(width: 460, height: 620)
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
