import AppKit
import Foundation

/// Takes the user back to a session, using the best level available:
/// 1. exact terminal tab  2. the host app  3. copy the resume command.
@MainActor
public enum FocusService {
    public enum Outcome: Equatable {
        case exactTab(String)
        case app(String)
        case copiedResume
        case needsAutomationPermission(String)
        case failed(String)

        public var message: String? {
            switch self {
            case .exactTab: nil
            case .app: nil
            case .copiedResume: "Session isn't running. Resume command copied."
            case .needsAutomationPermission(let app):
                "Opened \(app). For exact tabs, allow Branches under System Settings › Privacy › Automation."
            case .failed(let why): why
            }
        }
    }

    public static func jump(to session: SessionSnapshot) -> Outcome {
        guard session.status.display != .ended, let host = session.host else {
            return copyResume(session)
        }

        if let tty = session.tty, let script = tabScript(for: host.kind, tty: "/dev/\(tty)") {
            switch runAppleScript(script) {
            case .ok(true):
                return .exactTab(host.name)
            case .failed(-1743):
                activate(host)
                return .needsAutomationPermission(host.name)
            default:
                break
            }
        }
        if activate(host) { return .app(host.name) }
        return copyResume(session)
    }

    public static func openFolder(_ session: SessionSnapshot) {
        let path = session.projectPath.isEmpty ? session.cwd : session.projectPath
        guard !path.isEmpty else { return }
        NSWorkspace.shared.open(URL(fileURLWithPath: path))
    }

    @discardableResult
    public static func copyResume(_ session: SessionSnapshot) -> Outcome {
        guard let cmd = session.resumeCommand else { return .failed("No resume command for this session.") }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(cmd, forType: .string)
        return .copiedResume
    }

    // MARK: -

    @discardableResult
    private static func activate(_ host: HostApp) -> Bool {
        if let pid = host.pid, let app = NSRunningApplication(processIdentifier: pid) {
            return app.activate()
        }
        if let id = host.bundleID ?? defaultBundleID(host.kind),
           let app = NSRunningApplication.runningApplications(withBundleIdentifier: id).first {
            return app.activate()
        }
        return false
    }

    private static func defaultBundleID(_ kind: HostKind) -> String? {
        switch kind {
        case .chatGPT: "com.openai.chat"
        case .vscode: "com.microsoft.VSCode"
        case .claudeDesktop: "com.anthropic.claudefordesktop"
        default: nil
        }
    }

    private static func tabScript(for kind: HostKind, tty: String) -> String? {
        switch kind {
        case .terminal:
            return """
            tell application "Terminal"
                repeat with w in windows
                    repeat with t in tabs of w
                        if tty of t is "\(tty)" then
                            set selected tab of w to t
                            set index of w to 1
                            activate
                            return true
                        end if
                    end repeat
                end repeat
            end tell
            return false
            """
        case .iTerm:
            return """
            tell application "iTerm2"
                repeat with w in windows
                    repeat with t in tabs of w
                        repeat with s in sessions of t
                            if tty of s is "\(tty)" then
                                select w
                                select t
                                select s
                                activate
                                return true
                            end if
                        end repeat
                    end repeat
                end repeat
            end tell
            return false
            """
        default:
            return nil
        }
    }

    private enum ScriptResult { case ok(Bool), failed(Int) }

    private static func runAppleScript(_ source: String) -> ScriptResult {
        guard let script = NSAppleScript(source: source) else { return .failed(0) }
        var error: NSDictionary?
        let result = script.executeAndReturnError(&error)
        if let error {
            let code = (error[NSAppleScript.errorNumber] as? Int) ?? 0
            Log.focus.error("AppleScript failed: \(code)")
            return .failed(code)
        }
        return .ok(result.booleanValue)
    }
}
