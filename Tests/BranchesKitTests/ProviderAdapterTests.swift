import XCTest
@testable import BranchesKit

/// Fixtures mirror the shapes observed in Claude Code 2.1.282 and Codex CLI 0.139.0
/// (see docs/02-feasibility.md). Content is synthetic.
final class ClaudeAdapterTests: XCTestCase {
    let sid = "11111111-2222-3333-4444-555555555555"
    let t0 = Date(timeIntervalSince1970: 1_790_000_000)

    private func makeHome(status: String = "busy") -> TempHome {
        let home = TempHome()
        home.write(".claude/sessions/4242.json", """
        {"pid":4242,"sessionId":"\(sid)","cwd":"/tmp/proj","startedAt":\(Int(t0.timeIntervalSince1970 * 1000)),
         "version":"2.1.282","kind":"interactive","entrypoint":"cli","name":"proj-3b",
         "status":"\(status)","updatedAt":\(Int(t0.timeIntervalSince1970 * 1000) + 5000),"statusUpdatedAt":\(Int(t0.timeIntervalSince1970 * 1000) + 5000)}
        """)
        home.write(".claude/sessions/4242.abc.key", "SECRET-DO-NOT-READ")
        return home
    }

    private func transcript(_ home: TempHome, _ lines: [String]) {
        home.write(".claude/projects/-tmp-proj/\(sid).jsonl", lines.joined())
    }

    private func user(_ text: String, at: TimeInterval) -> String {
        line(["type": "user", "sessionId": sid, "cwd": "/tmp/proj", "timestamp": iso(t0 + at), "isSidechain": false,
              "message": ["role": "user", "content": text]])
    }

    private func toolUse(_ name: String, input: [String: Any], at: TimeInterval) -> String {
        line(["type": "assistant", "sessionId": sid, "cwd": "/tmp/proj", "timestamp": iso(t0 + at),
              "message": ["role": "assistant", "stop_reason": NSNull(),
                          "content": [["type": "tool_use", "id": "t1", "name": name, "input": input]]]])
    }

    private func toolResult(at: TimeInterval) -> String {
        line(["type": "user", "sessionId": sid, "timestamp": iso(t0 + at),
              "message": ["role": "user", "content": [["type": "tool_result", "tool_use_id": "t1", "content": "ok"]]]])
    }

    private func endTurn(at: TimeInterval) -> String {
        line(["type": "assistant", "sessionId": sid, "timestamp": iso(t0 + at),
              "message": ["role": "assistant", "stop_reason": "end_turn", "content": [["type": "text", "text": "Done."]]]])
    }

    func testDiscoversLiveSessionFromStateFile() throws {
        let home = makeHome()
        let adapter = ClaudeAdapter(home: home.path(".claude"))
        adapter.bootstrap(now: t0 + 10)

        let e = try XCTUnwrap(adapter.sessions.first)
        XCTAssertEqual(e.key, SessionKey(.claude, sid))
        XCTAssertEqual(e.pid, 4242)
        XCTAssertEqual(e.cwd, "/tmp/proj")
        XCTAssertEqual(e.liveStatus, .busy)
        XCTAssertNil(e.providerTitle, "auto-generated names like proj-3b are not titles")
        XCTAssertEqual(adapter.sessions.count, 1, "the .key file must be ignored")
    }

    func testWaitingStatusCarriesReason() throws {
        let home = makeHome(status: "waiting")
        let url = home.path(".claude/sessions/4242.json")
        var json = try String(contentsOf: url, encoding: .utf8)
        json = json.replacingOccurrences(of: "\"status\":", with: "\"waitingFor\":\"permission prompt\",\"status\":")
        try json.write(to: url, atomically: true, encoding: .utf8)
        let adapter = ClaudeAdapter(home: home.path(".claude"))
        adapter.bootstrap(now: t0 + 10)
        let e = try XCTUnwrap(adapter.sessions.first)
        XCTAssertEqual(e.liveStatus, .waiting)
        XCTAssertEqual(e.waitingFor, "permission prompt")
    }

    func testTranscriptGivesTitleActivityAndTurnEnd() throws {
        let home = makeHome()
        transcript(home, [
            user("Fix the login redirect bug\nmore details here", at: 1),
            toolUse("Edit", input: ["file_path": "/tmp/proj/Sources/Auth.swift", "old_string": "secret"], at: 2),
        ])
        let adapter = ClaudeAdapter(home: home.path(".claude"))
        adapter.bootstrap(now: t0 + 3)

        var e = try XCTUnwrap(adapter.sessions.first)
        XCTAssertEqual(e.title, "Fix the login redirect bug")
        XCTAssertEqual(e.activity, "Editing Auth.swift")
        XCTAssertEqual(e.pendingTool?.name, "Edit")

        home.append(".claude/projects/-tmp-proj/\(sid).jsonl", toolResult(at: 3) + endTurn(at: 4))
        adapter.ingest(paths: [home.path(".claude/projects/-tmp-proj/\(sid).jsonl").path], now: t0 + 5)
        e = try XCTUnwrap(adapter.sessions.first)
        XCTAssertEqual(e.turn, .ended(at: t0 + 4))
        XCTAssertNil(e.pendingTool)
    }

    func testCustomTitleWinsAndSyntheticPromptsAreIgnored() throws {
        let home = makeHome()
        transcript(home, [
            user("<command-name>/clear</command-name>", at: 1),
            user("Refactor the dashboard", at: 2),
            line(["type": "custom-title", "customTitle": "Dashboard refactor", "sessionId": sid]),
        ])
        let adapter = ClaudeAdapter(home: home.path(".claude"))
        adapter.bootstrap(now: t0 + 3)
        let e = try XCTUnwrap(adapter.sessions.first)
        XCTAssertEqual(e.firstPrompt, "Refactor the dashboard")
        XCTAssertEqual(e.title, "Dashboard refactor")
    }

    func testMalformedAndUnknownLinesNeverBreakParsing() throws {
        let home = makeHome()
        transcript(home, [
            "{not json\n",
            line(["type": "some-future-record", "whatever": [1, 2, 3]]),
            user("Still works", at: 1),
        ])
        let adapter = ClaudeAdapter(home: home.path(".claude"))
        adapter.bootstrap(now: t0 + 2)
        XCTAssertEqual(adapter.sessions.first?.lastPrompt, "Still works")
        XCTAssertEqual(adapter.diagnostics.linesSkipped, 1)
        XCTAssertEqual(adapter.diagnostics.ignoredTypes["some-future-record"], 1)
    }

    func testPIDReassignedToNewSessionEndsTheOldOne() throws {
        let home = makeHome()
        let adapter = ClaudeAdapter(home: home.path(".claude"))
        adapter.bootstrap(now: t0 + 1)
        home.write(".claude/sessions/4242.json", """
        {"pid":4242,"sessionId":"new-session","cwd":"/tmp/proj","status":"idle","updatedAt":\(Int(t0.timeIntervalSince1970 * 1000) + 9000)}
        """)
        adapter.ingest(paths: [home.path(".claude/sessions/4242.json").path], now: t0 + 10)
        let old = try XCTUnwrap(adapter.sessions.first { $0.key.id == sid })
        XCTAssertTrue(old.ended)
        XCTAssertEqual(adapter.sessions.count, 2)
    }

    func testToolDescriptionsNeverIncludeCommandText() {
        XCTAssertEqual(ClaudeTools.describe(name: "Bash", input: ["command": "export TOKEN=abc"]), "Running a command")
        XCTAssertEqual(ClaudeTools.describe(name: "Bash", input: ["command": "swift test", "description": "Run the tests"]), "Run the tests")
        XCTAssertEqual(ClaudeTools.describe(name: "mcp__github__create_issue", input: nil), "Using github")
    }
}

final class CodexAdapterTests: XCTestCase {
    let sid = "01a0c261-22cb-7e92-b55a-a52d8750bfb2"
    let t0 = Date(timeIntervalSince1970: 1_790_000_000)
    var rel: String { "sessions/2026/09/21/rollout-2026-09-21T01-12-20-\(sid).jsonl" }

    private func event(_ type: String, at: TimeInterval, _ extra: [String: Any] = [:]) -> String {
        var payload: [String: Any] = ["type": type]
        payload.merge(extra) { $1 }
        return line(["timestamp": iso(t0 + at), "type": "event_msg", "payload": payload])
    }

    private func meta(originator: String = "codex_cli_rs") -> String {
        line(["timestamp": iso(t0), "type": "session_meta", "payload": [
            "id": sid, "cwd": "/tmp/app", "cli_version": "0.139.0", "originator": originator, "timestamp": iso(t0),
            "base_instructions": ["text": String(repeating: "x", count: 5000)],
        ]])
    }

    func testTurnBoundariesAndTitles() throws {
        let home = TempHome()
        home.write(".codex/\(rel)", meta()
            + event("task_started", at: 1)
            + event("user_message", at: 1, ["message": "Fix Gmail parser"])
            + line(["timestamp": iso(t0 + 2), "type": "response_item", "payload": ["type": "function_call", "name": "apply_patch", "arguments": "{}"]]))
        home.write(".codex/session_index.jsonl", line(["id": sid, "thread_name": "Gmail parser fix", "updated_at": iso(t0)]))

        let adapter = CodexAdapter(home: home.path(".codex"))
        adapter.bootstrap(now: Date())
        var e = try XCTUnwrap(adapter.sessions.first)
        XCTAssertEqual(e.cwd, "/tmp/app")
        XCTAssertEqual(e.turn, .running(since: t0 + 1))
        XCTAssertTrue(e.turnReported)
        XCTAssertEqual(e.activity, "Editing files")
        XCTAssertEqual(e.title, "Gmail parser fix")
        XCTAssertEqual(e.firstPrompt, "Fix Gmail parser")
        XCTAssertTrue(e.expectsProcess)

        home.append(".codex/\(rel)", event("task_complete", at: 30, ["last_agent_message": "done", "duration_ms": 29000]))
        adapter.ingest(paths: [home.path(".codex/\(rel)").path], now: Date())
        e = try XCTUnwrap(adapter.sessions.first)
        XCTAssertEqual(e.turn, .ended(at: t0 + 30))
    }

    func testApprovalRequestNeedsAttention() throws {
        let home = TempHome()
        home.write(".codex/\(rel)", meta() + event("task_started", at: 1) + event("exec_approval_request", at: 2))
        let adapter = CodexAdapter(home: home.path(".codex"))
        adapter.bootstrap(now: Date())
        XCTAssertEqual(adapter.sessions.first?.attention, .permission)
    }

    func testAppHostedSessionsDontExpectAProcess() throws {
        let home = TempHome()
        home.write(".codex/\(rel)", meta(originator: "Codex Desktop"))
        let adapter = CodexAdapter(home: home.path(".codex"))
        adapter.bootstrap(now: Date())
        let e = try XCTUnwrap(adapter.sessions.first)
        XCTAssertFalse(e.expectsProcess)
        XCTAssertEqual(e.hostHint, .chatGPT)
    }

    func testSessionIDFromFileName() {
        XCTAssertEqual(CodexAdapter.sessionID(fromFileName: "rollout-2026-09-21T01-12-20-\(sid).jsonl"), sid)
    }
}
