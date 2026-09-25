import AppKit
import BranchesKit
import UserNotifications

/// Posts an optional macOS notification when a session starts needing you or finishes a turn.
/// Both are off by default. Clicking a notification jumps to the session.
@MainActor
final class Notifier: NSObject, UNUserNotificationCenterDelegate {
    static let shared = Notifier()

    /// nil until the first snapshot, so launching Branches never fires a burst of notifications.
    private var previous: [SessionKey: StatusTransitions.Seen]?
    private var lastPosted: [String: Date] = [:]

    /// Notifications only work from a bundled app (not `swift run`).
    var isAvailable: Bool { Bundle.main.bundleIdentifier != nil }
    private var center: UNUserNotificationCenter? { isAvailable ? .current() : nil }

    func install() {
        center?.delegate = self
    }

    func requestPermission() async -> Bool {
        guard let center else { return false }
        return (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
    }

    func process(_ snapshot: StoreSnapshot, needsYou: Bool, done: Bool) {
        defer { previous = StatusTransitions.seen(snapshot.sessions) }
        guard let previous else { return }
        let byKey = Dictionary(snapshot.sessions.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })

        for event in StatusTransitions.detect(previous: previous, current: snapshot.sessions) {
            guard let session = byKey[event.session] else { continue }
            switch event.kind {
            case .startedNeedingYou where needsYou:
                post(needsYouFor: session)
            case .finished(let workingSince) where done:
                post(doneFor: session, workingSince: workingSince)
            case .stoppedNeedingYou:
                center?.removeDeliveredNotifications(withIdentifiers: [identifier("needs", session.id)])
            default:
                break
            }
        }
    }

    // MARK: Posting

    private func post(needsYouFor s: SessionSnapshot) {
        let content = UNMutableNotificationContent()
        content.title = "\(s.projectName) needs you"
        content.subtitle = "\(s.provider.displayName) · \(s.title)"
        content.body = s.needsYouText
        content.sound = .default
        send(content, id: identifier("needs", s.id), session: s.id)
    }

    private func post(doneFor s: SessionSnapshot, workingSince: Date?) {
        let content = UNMutableNotificationContent()
        content.title = "\(s.projectName): done"
        content.subtitle = "\(s.provider.displayName) · \(s.title)"
        if let workingSince {
            content.body = "Finished after \(Self.duration(s.status.since.timeIntervalSince(workingSince)))"
        }
        send(content, id: identifier("done", s.id), session: s.id)
    }

    private func send(_ content: UNMutableNotificationContent, id: String, session: SessionKey) {
        guard let center else { return }
        // Don't repeat the same notification for a session that flaps back and forth.
        if let last = lastPosted[id], Date().timeIntervalSince(last) < 30 { return }
        lastPosted[id] = Date()
        content.userInfo = ["provider": session.provider.rawValue, "id": session.id]
        content.threadIdentifier = session.description
        center.add(UNNotificationRequest(identifier: id, content: content, trigger: nil))
    }

    private func identifier(_ kind: String, _ key: SessionKey) -> String { "\(kind):\(key)" }

    private static func duration(_ seconds: TimeInterval) -> String {
        let s = max(0, Int(seconds))
        if s < 60 { return "\(s)s" }
        if s < 3600 { return "\(s / 60)m \(s % 60)s" }
        return "\(s / 3600)h \(s % 3600 / 60)m"
    }

    // MARK: UNUserNotificationCenterDelegate

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let info = response.notification.request.content.userInfo
        let provider = (info["provider"] as? String).flatMap(ProviderID.init(rawValue:))
        let id = info["id"] as? String
        completionHandler()
        Task { @MainActor in
            if let provider, let id, let model = AppModel.current,
               let session = model.snapshot.sessions.first(where: { $0.id == SessionKey(provider, id) }) {
                model.jump(session)
            }
        }
    }
}

extension SessionSnapshot {
    /// What a "Needs you" session is waiting for, in plain words.
    var needsYouText: String {
        switch status.attention {
        case .error:
            return "Stopped with an error"
        case .input:
            guard let reason = waitingFor, !reason.isEmpty else { return "Waiting for you" }
            if reason.lowercased() == "input needed" { return "Waiting for your answer" }
            return reason.prefix(1).uppercased() + reason.dropFirst()
        default:
            return activity.map { "\($0) · waiting for approval" } ?? "Waiting for approval"
        }
    }
}
