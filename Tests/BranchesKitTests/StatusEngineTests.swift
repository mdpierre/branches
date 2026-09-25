import XCTest
@testable import BranchesKit

/// One test per row of the transition table in docs/03-architecture.md §6.
final class StatusEngineTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_790_000_000)

    private func evidence(_ provider: ProviderID = .claude, _ build: (inout SessionEvidence) -> Void = { _ in }) -> SessionEvidence {
        var e = SessionEvidence(key: SessionKey(provider, "s"), cwd: "/p", lastActivityAt: now - 5)
        e.lastPrompt = "Do a thing"
        build(&e)
        return e
    }

    private func eval(_ e: SessionEvidence, alive: Bool? = true, seen: Date? = nil, at: Date? = nil) -> StatusResult {
        StatusEngine.evaluate(e, processAlive: alive, lastSeen: seen, now: at ?? now)
    }

    func testProcessGoneIsEnded() {
        XCTAssertEqual(eval(evidence { $0.liveStatus = .busy; $0.liveStatusAt = self.now }, alive: false).display, .ended)
    }

    func testReplacedSessionIsEnded() {
        XCTAssertEqual(eval(evidence { $0.ended = true }).display, .ended)
    }

    func testNoProcessAndSilentFor12HoursIsEnded() {
        let e = evidence(.codex) { $0.lastActivityAt = self.now - 13 * 3600; $0.expectsProcess = false }
        XCTAssertEqual(eval(e, alive: nil).display, .ended)
    }

    func testLiveBusyIsReportedWorking() {
        let r = eval(evidence { $0.liveStatus = .busy; $0.liveStatusAt = self.now - 3 })
        XCTAssertEqual(r.display, .working)
        XCTAssertEqual(r.confidence, .reported)
    }

    func testLiveWaitingIsNeedsYou() {
        XCTAssertEqual(eval(evidence { $0.liveStatus = .waiting; $0.liveStatusAt = self.now }).display, .needsYou)
    }

    func testInstantToolPendingTooLongIsProbablyPermission() {
        let r = eval(evidence {
            $0.liveStatus = .busy; $0.liveStatusAt = self.now - 20
            $0.pendingTool = PendingTool(name: "Edit", since: self.now - 10)
        })
        XCTAssertEqual(r.display, .needsYou)
        XCTAssertEqual(r.confidence, .inferred)
    }

    func testSlowToolPendingStaysWorking() {
        let r = eval(evidence {
            $0.liveStatus = .busy; $0.liveStatusAt = self.now - 60
            $0.pendingTool = PendingTool(name: "Bash", since: self.now - 45)
        })
        XCTAssertEqual(r.display, .working)
    }

    func testLiveIdleAfterTurnIsDoneUntilSeen() {
        let e = evidence { $0.liveStatus = .idle; $0.liveStatusAt = self.now - 60; $0.turn = .ended(at: self.now - 60) }
        XCTAssertEqual(eval(e).display, .done)
        XCTAssertEqual(eval(e, seen: now - 10).display, .idle)
    }

    func testDoneDecaysToIdleAfter30Minutes() {
        let e = evidence { $0.liveStatus = .idle; $0.liveStatusAt = self.now - 31 * 60; $0.turn = .ended(at: self.now - 31 * 60) }
        XCTAssertEqual(eval(e).display, .idle)
    }

    func testFreshSessionWithNoTurnsIsIdleNotDone() {
        let e = evidence { $0.lastPrompt = nil; $0.liveStatus = .idle; $0.liveStatusAt = self.now }
        XCTAssertEqual(eval(e).display, .idle)
    }

    func testReportedTurnRunningIsWorking() {
        let r = eval(evidence(.codex) { $0.turn = .running(since: self.now - 30); $0.turnReported = true })
        XCTAssertEqual(r.display, .working)
        XCTAssertEqual(r.confidence, .reported)
        XCTAssertEqual(r.since, now - 30)
    }

    func testInferredTurnGoesQuietAfter3Minutes() {
        let e = evidence { $0.turn = .running(since: self.now - 600); $0.lastActivityAt = self.now - 200 }
        let r = eval(e)
        XCTAssertEqual(r.display, .idle)
        XCTAssertEqual(r.confidence, .unknown)
    }

    func testReportedTurnToleratesLongQuiet() {
        let e = evidence(.codex) { $0.turn = .running(since: self.now - 600); $0.turnReported = true; $0.lastActivityAt = self.now - 400 }
        XCTAssertEqual(eval(e).display, .working)
    }

    func testErrorIsNeedsYou() {
        let r = eval(evidence(.codex) { $0.turn = .ended(at: self.now); $0.attention = .error })
        XCTAssertEqual(r.display, .needsYou)
        XCTAssertEqual(r.attention, .error)
    }

    func testCodexApprovalIsNeedsYou() {
        XCTAssertEqual(eval(evidence(.codex) { $0.turn = .running(since: self.now); $0.attention = .permission }).display, .needsYou)
    }

    func testNoTurnInfoRecentActivityIsWorkingElseIdle() {
        XCTAssertEqual(eval(evidence { $0.lastActivityAt = self.now - 10 }).display, .working)
        XCTAssertEqual(eval(evidence { $0.lastActivityAt = self.now - 600 }).display, .idle)
    }

    func testNewerTranscriptOverridesStaleLiveFile() {
        // Live file still says busy from long ago, transcript shows the turn ended afterwards.
        let e = evidence { $0.liveStatus = .busy; $0.liveStatusAt = self.now - 120; $0.turn = .ended(at: self.now - 30) }
        XCTAssertEqual(eval(e).display, .done)
    }
}

final class PrivacyGuardTests: XCTestCase {
    /// Branches promises it never sends session contents anywhere.
    func testKitHasNoNetworkingCode() throws {
        let kit = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources")
        let forbidden = ["URLSession", "import Network", "NWConnection", "CFSocket", "URLRequest"]
        let files = FileManager.default.enumerator(at: kit, includingPropertiesForKeys: nil)!
            .compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" }
        XCTAssertFalse(files.isEmpty)
        for file in files {
            let text = try String(contentsOf: file, encoding: .utf8)
            for word in forbidden {
                XCTAssertFalse(text.contains(word), "\(file.lastPathComponent) mentions \(word)")
            }
        }
    }
}
