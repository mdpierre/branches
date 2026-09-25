# Branches — Architecture, Provider Contract, Status Engine, Data Model, Implementation Spec

Deliverables 4, 5, 6, 7 and 10.

Notation: **[FACT]** means verified in `02-feasibility.md`. **[REC]** is a recommendation. **[ASSUME]** is an assumption to confirm in Phase 0.

---

## 4. Architecture

### Components

```
                         ┌─────────────────────── BranchesKit (library, no UI) ───────────────────────┐
 ~/.claude/projects ─┐   │                                                                              │
 ~/.claude/sessions ─┤   │  FileWatcher (FSEvents) ──► ProviderAdapter.ingest(changes) ──► [Observation] │
 ~/.codex/sessions  ─┤──►│        ▲                    ClaudeAdapter / CodexAdapter        │             │
 ~/.codex/session_   │   │        │                    (JSONLTailReader inside)            ▼             │
   index.jsonl      ─┘   │   HookInbox (FSEvents on    ────────────────────────────►  SessionStore     │
 Branches hook drop  ───►│   App Support/…/inbox)                                    (actor; merges,   │
                         │                                                           runs StatusEngine)│
 sysctl / proc_pidinfo ─►│   ProcessScanner (on demand + 2 s while any Working) ───►        │           │
                         │                                                                  ▼           │
                         │                                              snapshot: [SessionViewModel]    │
                         └────────────────────────────────────────────────────────────────┬─────────────┘
                                                                                          ▼
                                                   BranchesApp: AppModel (@Observable, @MainActor) → SwiftUI
                                                   FocusService (AppleScript / NSWorkspace) ◄── user click
```

| Component | Job | Runs |
|---|---|---|
| **FileWatcher** | One FSEvents stream over the watched roots, with file-level events and 0.2 s latency. It emits `[URL]` of changed files. | Event-driven |
| **JSONLTailReader** | Keeps `(inode, offset, partialLineBuffer)` per file. Reads only new bytes, splits on `\n` and holds back a trailing partial line. | On change |
| **ProviderAdapter** (Claude, Codex) | Turns provider files into provider-neutral `Observation`s. It is the *only* code that knows provider formats. | On change |
| **HookInbox** | Watches the folder the optional Claude hook writes to, and turns each dropped event into an `Observation`. | Event-driven |
| **ProcessScanner** | Snapshot of `kinfo_proc` (pid, ppid, tty, start time) plus cwd for candidate processes. It resolves the host app by walking ppid. | On demand; a 2 s tick only while something is Working/Needs-you (to catch deaths). Pauses on sleep. |
| **SessionStore** (actor) | Holds sessions, applies observations, runs `StatusEngine`, and publishes an immutable snapshot. | Event-driven |
| **StatusEngine** | A pure function `(evidence, now) → (DisplayStatus, Confidence, reason)`. | Called by the store and by a coarse 15 s "decay" tick (only when some session has a time-based transition pending) |
| **Summarizer** | Deterministic title and activity text. No LLM. | Inside the adapters |
| **FocusService** | Picks the best jump level and performs it. | On click |
| **AppModel / UI** | Displays the snapshot and sorts and groups it. | Main actor |

**Deliberately absent in v1:** a database, a network stack, a socket server, a background daemon, a login item (added later with the menu-bar extra) and any LLM calls.

### Data flow (one example)
1. Claude writes `sessions/4242.json` with `status:"busy"` → FSEvents → `ClaudeAdapter` decodes it → `Observation(.liveStatus(.busy), source: .providerStateFile)`.
2. `SessionStore` finds or creates `Session(id: "claude:<sessionId>")`, attaches pid 4242, and calls `ProcessScanner.resolve(4242)` → tty `ttys003`, host `Terminal`.
3. `StatusEngine` → `.working` with confidence `.reported`.
4. The store publishes a snapshot → the AppModel on the main actor → the row animates to Working.
5. Transcript appends (tool_use `Edit Auth.swift`) → activity text "Editing Auth.swift".

### Hook IPC decision — **file drop, not a socket** [REC]
The optional Claude hook is a tiny POSIX shell script that writes the stdin JSON (already small), plus a timestamp, to
`~/Library/Application Support/Branches/inbox/<session_id>.json` using write-to-temp-then-`mv` (atomic).

Why not a Unix socket or localhost:
- If Branches isn't running, a socket client blocks, errors or needs a timeout, and **the hook adds latency to every tool call**. A file write takes about 1 ms and always succeeds.
- Missed events are impossible: Branches reads the latest file per session when it starts.
- No listener means no port, no firewall prompt and no security surface.
- One file per session (overwritten each time) means the inbox never grows. Branches deletes files older than 24 h.

The hook script copies only these fields from stdin: `hook_event_name, session_id, cwd, transcript_path, tool_name, notification type/message (truncated to 120 chars)`. It never copies prompts or tool inputs. Written in `sh` + `/usr/bin/plutil` or plain `sed` (no `jq` dependency). The field extraction approach gets checked in E6.

---

## 5. Provider adapter contract

```swift
/// Everything a provider can (maybe) tell us. Adapters declare honestly what they support.
public struct ProviderCapabilities: OptionSet, Sendable {
    public let rawValue: Int
    public static let sessionDiscovery   = Self(rawValue: 1 << 0)
    public static let transcriptReading  = Self(rawValue: 1 << 1)
    public static let liveStatus         = Self(rawValue: 1 << 2) // provider-reported busy/idle (Claude sessions/*.json)
    public static let turnBoundaries     = Self(rawValue: 1 << 3) // explicit start/end of a turn (Codex task_*)
    public static let toolActivity       = Self(rawValue: 1 << 4)
    public static let waitingDetection   = Self(rawValue: 1 << 5) // "needs permission/input" signal
    public static let processCorrelation = Self(rawValue: 1 << 6) // provider gives us a PID
    public static let resumeCommand      = Self(rawValue: 1 << 7)
    public static let subagents          = Self(rawValue: 1 << 8)
}

public enum ProviderID: String, Sendable, Codable { case claude, codex }

public protocol ProviderAdapter: Sendable {
    var id: ProviderID { get }
    var displayName: String { get }                 // "Claude Code"
    var capabilities: ProviderCapabilities { get }
    /// Directories the FileWatcher should watch. Missing dirs are fine (provider not installed).
    var watchRoots: [URL] { get }

    /// Initial scan at launch: return observations for sessions active within `since`.
    func bootstrap(since: Date) async -> [Observation]

    /// Called with changed files under watchRoots. Must be incremental and must never throw:
    /// malformed input becomes a diagnostic, not an error.
    func ingest(changedFiles: [URL]) async -> [Observation]

    /// Deterministic resume hint for Level-4 navigation, if supported.
    func resumeCommand(for providerSessionID: String) -> String?

    /// For the diagnostics panel.
    func diagnostics() async -> ProviderDiagnostics
}

public struct ProviderDiagnostics: Sendable {
    public var filesTracked: Int
    public var linesParsed: Int
    public var linesSkipped: Int            // malformed / unknown
    public var unknownRecordTypes: [String: Int]
    public var lastError: String?
    public var observedFormatVersions: Set<String> // e.g. Claude "2.1.282", Codex "0.139.0"
}
```

**Observation**: the only thing that crosses the provider boundary.

```swift
public struct Observation: Sendable {
    public var key: SessionKey                  // provider + providerSessionID
    public var at: Date                         // when it happened (from the record, else file mtime)
    public var source: EvidenceSource           // .providerStateFile, .transcript, .hook, .process
    public var fact: Fact
}

public enum Fact: Sendable {
    case discovered(cwd: String, startedAt: Date?, transcriptPath: URL?, parent: SessionKey?)
    case pid(Int32, processStart: Date?)
    case liveStatus(LiveStatus)                 // .busy / .idle / .waiting / .unknown(raw)
    case turnStarted
    case turnEnded(outcome: TurnOutcome)        // .success / .error(String) / .interrupted
    case toolStarted(name: String, target: String?)  // "Edit", "Auth.swift"
    case toolFinished
    case needsAttention(reason: AttentionReason)     // .permission / .input / .error
    case userPrompt(firstLine: String)          // truncated to 80 chars; the only raw text we keep
    case title(String, TitleSource)             // .userSet / .provider / .derived
    case sessionEnded
    case activity                               // "something was appended"; evidence of liveness only
}
```

Rules for adapters:
- **Never throw out of `ingest`.** Malformed line → `linesSkipped += 1`, continue.
- **Unknown record type → ignore and count it.** Unknown field → ignore it (`Decodable` structs with every field optional, decoded per record type rather than as one giant enum).
- **Adapters are stateful but own only parse state** (cursors, per-session last tool). No UI and no status decisions.
- Adding a provider = a new folder under `Providers/`, one type conforming to `ProviderAdapter`, fixtures, and one line registering it. Documented in `Providers/README.md`.

**Claude adapter** (capabilities: all except `turnBoundaries`, which it infers)
- `sessions/*.json` → `.pid`, `.liveStatus`, `.discovered`, `.title(name)` if `nameSource` indicates user-set **[ASSUME]**. Ignore `*.key`.
- A `sessions/*.json` file being deleted → `.sessionEnded` **[ASSUME, E2]**.
- Transcript `user` with string content → `.userPrompt`, `.turnStarted`. `assistant` with `tool_use` → `.toolStarted`. `user` with `tool_result` → `.toolFinished`. `assistant` with `stop_reason == "end_turn"` → `.turnEnded(.success)`. API error records → `.turnEnded(.error)`. `custom-title` → `.title(.userSet)`. `last-prompt` → `.userPrompt`.
- `…/subagents/agent-*.jsonl` → `.discovered(parent:)`.
- Resume: `claude --resume <sessionId>` (run in `cwd`).

**Codex adapter** (capabilities: discovery, transcript, turnBoundaries, toolActivity, subagents, resume; `waitingDetection` only if E4 passes; `processCorrelation` only if E3 passes)
- `session_meta` → `.discovered(parent: parent_thread_id)`.
- `event_msg.task_started` → `.turnStarted`. `task_complete` → `.turnEnded(.success)`. Error events → `.turnEnded(.error)`.
- `response_item` function/tool call → `.toolStarted`. First `response_item` user message → `.userPrompt`.
- `session_index.jsonl` → `.title(thread_name, .provider)`.
- Resume: `codex resume <id>`.

---

## 6. Status engine

### Two layers
- **Internal `Activity`** (fine-grained): `thinking, toolUse(name), waitingForPermission, waitingForInput, turnComplete, errored, stopped(ended), unknown`
- **UI `DisplayStatus`** (five states):

| DisplayStatus | Meaning | Node |
|---|---|---|
| **Working** | The agent is actively doing something | green, softly pulsing |
| **Needs you** | Blocked on permission, a question or an error | amber attention ring |
| **Done** | Finished a turn since you last looked | hollow cream ring |
| **Idle** | Alive, nothing happening, and you've already seen the result | small muted dot |
| **Ended** | The process is gone | dimmed row, no node |

`Error` is not a sixth state. It is **Needs you** with reason `error` (a different glyph, same attention level). That keeps the vocabulary to five words.

### Confidence (kept separately from status)
```swift
enum Confidence { case reported, inferred, unknown }
```
- **reported**: the provider itself said so (Claude `sessions/*.json` status, a hook event, Codex `task_*` events).
- **inferred**: derived from transcript shape, file mtime or process liveness.
- **unknown**: not enough evidence.

The UI shows inferred status with no special marking, but an **unknown/stale** row gets a dotted node and the text "No recent activity". Confidence is always kept internally and shown in the row tooltip ("Working — reported by Claude Code 12 s ago").

### Evidence precedence
When signals conflict, the one with the **newer timestamp** wins. If they have the same timestamp (within 1 s), precedence is **hook > provider state file > turn events > transcript shape > process/file-mtime**. Process death **always** wins → Ended.

### Transition table

| From | Signal | To | Confidence |
|---|---|---|---|
| any | `.discovered` with no other evidence | Idle (if last activity > 10 min ago) else Unknown→Working-inferred | inferred |
| any | `.liveStatus(.busy)` | Working | reported |
| any | `.turnStarted`, `.userPrompt`, hook `UserPromptSubmit` | Working | reported (hook/Codex) / inferred (Claude transcript) |
| Working | `.toolStarted` / hook `PreToolUse` | Working (activity = tool) | same as source |
| Working | hook `Notification` (permission) / `.needsAttention(.permission)` | **Needs you** | reported |
| Working | tool_use with no tool_result for **> 20 s** *and* `liveStatus` not busy *[heuristic for permission prompts, no hook]* | Needs you (permission?) | inferred |
| Working | `.turnEnded(.success)`, hook `Stop`, `.liveStatus(.idle)` | **Done** | reported/inferred |
| Working | `.turnEnded(.error)` | Needs you (error) | reported |
| Needs you | `.toolFinished`, `.liveStatus(.busy)`, `.turnStarted` | Working | per source |
| Done | user focuses the session through Branches, **or** 30 min pass | Idle | — |
| Working (inferred only) | no new evidence for **3 min** and the process is alive | Unknown ("No recent activity") | unknown |
| Working (reported) | no new evidence for **15 min** | Unknown | unknown |
| any | process gone (pid dead, or pid reused: start time mismatch), `.sessionEnded`, hook `SessionEnd` | **Ended** | reported |
| Ended | new transcript lines for the same session ID (resumed) | re-evaluate as a new run | — |
| any (no pid known) | no file activity for **12 h** | hidden (Ended, collapsed) | inferred |

"Done → Idle on focus" is the one piece of user-driven state. It is kept in memory plus `UserDefaults` (`lastSeen[sessionKey]`).

### Timeouts & timers
- There is **no per-session timer**. The store keeps the *earliest pending decay deadline* and schedules one `Task.sleep` until then.
- The ProcessScanner ticks every 2 s **only while at least one session is Working or Needs you** (to detect death quickly). Otherwise it runs only when a file event arrives.

### Failure modes
| Situation | Handling |
|---|---|
| Branches launched mid-session | `bootstrap(since: 24 h)`: read every `sessions/*.json` and tail-read the last 64 KB of each recent transcript to get title, last prompt and last event. Status comes from the provider state file if present, else inferred. |
| Transcript exists, process died | No pid, or pid dead → Ended. Claude: the `sessions/<pid>.json` is gone or its pid is dead. |
| Process alive, transcript quiet | Reported status is trusted up to 15 min, inferred status up to 3 min, then Unknown. |
| Session ended without a clean event | Process death covers it. With no pid (Codex before E3), 12 h of inactivity → hidden. |
| Laptop sleeps | On `NSWorkspace.willSleep`: pause the scanner. On `didWake`: full rescan plus reset of the decay deadlines (sleep time doesn't count as "no evidence"). FSEvents replays missed events via `sinceWhen`. |
| Branches restarts | Same as launch. Nothing important is lost, because the providers' files are the source of truth. |
| Hook message missed | The next hook event, `sessions/*.json` or transcript event overrides it (newest wins). The hook is never the only path to any state. |
| Several sessions in the same cwd | Sessions are keyed by provider session ID, never by cwd. The pid comes from `sessions/*.json` (Claude). For Codex, when ambiguous, leave pid nil rather than guessing. |
| Same project, several agents | Normal: several rows under one project header. |
| tmux detached | The process is still alive → normal status. Jump = L2/L4 (v1). |
| PID reuse | Compare the process start time from `kinfo_proc` with Claude's `procStart`/`startedAt`. On mismatch → Ended. |
| Format changes | Unknown types are ignored. If a provider yields no recognizable records from files that are clearly active, the diagnostics badge shows "Claude Code format may have changed". Sessions still show as Unknown/inferred from mtime. |

---

## 7. Data model

**Ownership rules**
1. Provider files are the **source of truth** and read-only, forever.
2. Branches' in-memory `Session` is a **derived view**, rebuilt on every launch.
3. The only things Branches persists: user preferences (hidden projects, `lastSeen` per session, whether the hook was installed) in `UserDefaults`, plus the hook inbox files. **No transcript content is persisted.** The only raw text held in memory is the ≤80-character first line of the latest prompt and the tool target file name.

```swift
// ── Domain (provider-neutral) ─────────────────────────────
public struct SessionKey: Hashable, Sendable, Codable {
    public let provider: ProviderID
    public let providerSessionID: String
}

public struct Session: Identifiable, Sendable {
    public var id: SessionKey
    public var project: ProjectRef          // derived from cwd
    public var cwd: String
    public var title: SessionTitle          // text + source (userSet / provider / derived)
    public var activity: String?            // "Editing Auth.swift"
    public var parent: SessionKey?          // subagent → parent
    public var startedAt: Date?
    public var lastEvidenceAt: Date
    public var status: StatusResult         // DisplayStatus + Confidence + reason + since
    public var runtime: RuntimeInfo?        // nil if no process known
    public var providerInfo: ProviderInfo   // opaque-ish bag, see below
}

public struct ProjectRef: Hashable, Sendable {
    public let rootPath: String             // git toplevel of cwd, else cwd
    public var name: String { (rootPath as NSString).lastPathComponent }
}

public struct StatusResult: Sendable, Equatable {
    public var display: DisplayStatus       // working, needsYou, done, idle, ended
    public var activity: Activity           // fine-grained
    public var confidence: Confidence
    public var reason: String               // tooltip/diagnostics: "hook: Notification(permission)"
    public var since: Date
}

// ── Runtime / process (ephemeral) ─────────────────────────
public struct RuntimeInfo: Sendable {
    public var pid: Int32
    public var processStart: Date
    public var tty: String?                 // "ttys003"
    public var host: HostApp                // .terminal, .iterm2, .ghostty, .warp, .vscode, .cursor,
                                            // .claudeDesktop, .chatGPT, .tmux(inner: HostApp?), .unknown(bundleID)
    public var hostPID: Int32?
}

// ── Provider-specific (only adapters + FocusService read this) ──
public struct ProviderInfo: Sendable {
    public var transcriptPath: URL?
    public var formatVersion: String?       // "2.1.282"
    public var entrypoint: String?          // Claude "cli" / "claude-desktop"; Codex originator
}

// ── Parse state (inside adapters, in-memory only) ─────────
struct FileCursor { var inode: UInt64; var offset: UInt64; var partial: Data }
```

A persisted cache is **not needed in v1** [REC]. Launch cost is roughly 20–50 recent files × a 64 KB tail read, well under 100 ms. Revisit this only if a measurement says otherwise.

---

## 10. Implementation specification

| Topic | Recommendation |
|---|---|
| **Min macOS** | **14.0 Sonoma** (`@Observable`, mature `MenuBarExtra`, modern SwiftUI lists). Dev machine is on 26.x. |
| **Swift** | Swift 6 language mode, strict concurrency on. Toolchain 6.3 (Xcode 26.5). |
| **UI** | SwiftUI for all views. AppKit only for `NSWorkspace` (open/activate, sleep/wake), `NSRunningApplication`, `NSAppleScript`, `NSPasteboard` and the window's visual-effect material. |
| **Packages** | **None.** |
| **Build system** | **SwiftPM only** (`Package.swift` with targets `BranchesKit` (library), `BranchesApp` (executable) and `BranchesKitTests`), plus `scripts/bundle.sh` that wraps the executable into `Branches.app` (Info.plist, icon, codesign). Contributors can `swift build && swift test` or open `Package.swift` in Xcode. No checked-in `.xcodeproj` and no XcodeGen. |
| **Concurrency** | `SessionStore` is an `actor`. Adapters are actors (they own cursors). The FSEvents callback runs on a private serial `DispatchQueue` and forwards into an `AsyncStream<[URL]>`. The UI model is `@MainActor @Observable`. There is exactly one consumer loop: `for await batch in fileEvents { observations = await adapter.ingest(batch); await store.apply(observations) }`. |
| **File watching** | `FSEventStreamCreate` with `kFSEventStreamCreateFlagFileEvents | UseCFTypes | NoDefer`, latency 0.2 s, roots `~/.claude/projects`, `~/.claude/sessions`, `~/.codex/sessions`, `~/.codex` (for `session_index.jsonl`; filter by path) and the hook inbox. Missing roots: watch the parent and add them when they appear. Save the last event ID in `UserDefaults` (optional replay after wake). |
| **JSONL ingestion** | `FileHandle(forReadingFrom:)` → `seek(toOffset:)` → `readToEnd()`. Split on `0x0A`. The last fragment without a newline goes into `partial`. If the inode changed or `size < offset` → reset the cursor to 0 (truncation/rotation). First read of a big file: seek to `max(0, size − 64 KB)`, drop the first (partial) line, and parse forward. Decode each line with `JSONDecoder` into a tiny `struct Envelope { let type: String?; … }` first, then decode the specific shape only for types we care about. |
| **Hook IPC** | File drop into `~/Library/Application Support/Branches/inbox/` (see §4). Install = merge 6 entries (`UserPromptSubmit, PreToolUse, PostToolUse, Notification, Stop, SessionEnd`) into `~/.claude/settings.json` after writing a timestamped backup, **tagging each entry** so uninstall removes exactly ours. Always show a diff and confirm before writing. |
| **Process enumeration** | `sysctl([CTL_KERN, KERN_PROC, KERN_PROC_ALL])` → filter by uid and by command name (`claude`, `codex`, `node` with codex args via `KERN_PROCARGS2`). `proc_pidinfo(PROC_PIDVNODEPATHINFO)` for cwd. `devname(e_tdev, S_IFCHR)` for the tty. Walk ppid until a process whose `proc_pidpath` is inside a `.app` bundle → `NSRunningApplication(processIdentifier:)` → bundle ID → `HostApp`. |
| **Focus** | `FocusService.jump(session)` tries L1 → L4. Terminal L1: `NSAppleScript` with a tty-matching script (see `05-build-plan.md` E8). Add `NSAppleEventsUsageDescription` to Info.plist. Enable the Hardened Runtime `apple-events` entitlement. |
| **Persistence** | `UserDefaults` only: `hiddenProjects`, `lastSeen`, `hookInstalled`, `fseventsLastID`. |
| **App lifecycle** | Regular app with a single `Window` scene (not `WindowGroup`, so there's one instance). "Keep in Dock" by default. A menu-bar extra comes in v1.1. Closing the window keeps observation running only once the menu-bar extra exists; until then, quit on close. |
| **Logging** | `os.Logger(subsystem: "dev.branches.app", category: "claude"|"codex"|"fs"|"process"|"status"|"focus")`. **Never log prompt text or tool inputs.** Diagnostics panel = counters from `ProviderDiagnostics`. |
| **Identifiers** | Bundle ID `dev.branches.app` and the product name live in one `Config.swift` / Info.plist variable, so a rename is a one-line change. |
| **Signing** | Developer ID Application cert, Hardened Runtime, `notarytool submit --wait`, `stapler staple`. **No App Sandbox.** Entitlement: `com.apple.security.automation.apple-events`. |
| **Network** | None. Add a test (or CI check) that `BranchesKit` never imports `Network` or uses `URLSession`. |
