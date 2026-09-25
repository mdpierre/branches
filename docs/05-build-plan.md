# Branches — Repo Structure, Milestones, Experiments, Testing, Build Checklist

Deliverables 11–15, plus "What I would build first tomorrow morning".

---

## 11. Repository structure

```
branches/
├── Package.swift                     # targets: BranchesKit, BranchesApp, BranchesKitTests
├── README.md                         # what it is, install, privacy promise, screenshot
├── PRIVACY.md                        # exactly what is read / held / stored / never sent
├── CLAUDE.md                         # guardrails for AI contributors
├── LICENSE                           # (choose: MIT recommended)
├── docs/                             # this planning package
├── scripts/
│   ├── bundle.sh                     # swift build -c release → Branches.app (+ codesign)
│   ├── make-icon.sh                  # Resources/AppIcon.png → AppIcon.icns
│   ├── notarize.sh
│   └── probes/                       # Phase 0 throwaway experiments (kept for reference)
├── Resources/
│   ├── Info.plist
│   ├── Branches.entitlements
│   ├── AppIcon.png                   # 1024 × 1024 icon master
│   ├── AppIcon.icns
│   └── hooks/branches-claude-hook.sh
├── Sources/
│   ├── BranchesKit/                  # all logic; no SwiftUI import allowed
│   │   ├── Domain/                   # Session, SessionKey, ProjectRef, StatusResult, Observation, Fact
│   │   ├── Status/                   # StatusEngine.swift (pure), DecayScheduler.swift
│   │   ├── Store/                    # SessionStore.swift (actor)
│   │   ├── Observation/              # FileWatcher.swift (FSEvents), JSONLTailReader.swift
│   │   ├── Providers/
│   │   │   ├── README.md             # "How to add a provider" — the contributor contract
│   │   │   ├── ProviderAdapter.swift # protocol + capabilities + diagnostics
│   │   │   ├── Claude/               # ClaudeAdapter, ClaudeRecords (Decodable), ClaudeSessionsFile, ClaudeHookInbox
│   │   │   └── Codex/                # CodexAdapter, CodexRecords, CodexSessionIndex
│   │   ├── Processes/                # ProcessScanner (sysctl/libproc), HostAppResolver
│   │   ├── Navigation/               # FocusService, TerminalAppFocuser, ResumeCommands
│   │   ├── Hooks/                    # HookInstaller (merge/unmerge settings.json with backup)
│   │   └── Support/                  # Log.swift, Clock protocol (for tests), Paths.swift
│   └── BranchesApp/
│       ├── BranchesApp.swift         # @main, Window scene
│       ├── AppModel.swift            # @MainActor @Observable; grouping/sorting
│       ├── Views/                    # SessionListView, ProjectGroupView, SessionRowView,
│       │                             # StatusNodeView, BranchConnector, EmptyStateView, SettingsPopover
│       └── DesignSystem/             # Palette, Typography, Metrics, Motion
└── Tests/
    └── BranchesKitTests/
        ├── Fixtures/
        │   ├── claude/2.1.282/…      # sanitized .jsonl + sessions/*.json, one folder per observed version
        │   └── codex/0.139.0/…
        ├── JSONLTailReaderTests.swift
        ├── ClaudeAdapterTests.swift
        ├── CodexAdapterTests.swift
        ├── StatusEngineTests.swift   # table-driven, mirrors the transition table
        ├── SessionStoreTests.swift
        └── HookInstallerTests.swift
```

Rule: **a provider update should touch only `Providers/<Name>/` and `Fixtures/<name>/`.**

---

## 12. Vertical-slice milestones (each one leaves a runnable app)

| M | Result you can see | Scope |
|---|---|---|
| **M1 — "They're alive"** | A window listing every live Claude session: project name, name/last prompt, busy/idle, updating live | `sessions/*.json` only + FSEvents + a basic list. **No transcript parsing yet.** |
| **M2 — "What are they doing"** | Titles and a live activity line ("Editing Auth.swift"), grouped by project, Done vs Idle | Claude transcript tail-reader + summarizer + StatusEngine v1 |
| **M3 — "Codex too"** | Codex sessions appear alongside, Working/Done from `task_*` events | CodexAdapter + session_index titles |
| **M4 — "Take me there"** | Click → exact Terminal tab; others → app / folder / copy resume | ProcessScanner + HostAppResolver + FocusService |
| **M5 — "Needs you, precisely"** | Permission prompts show as Needs you instantly | Optional hook + installer + HookInbox |
| **M6 — "Feels like a tool"** | Branch connectors, nodes, breathing animation, keyboard nav, empty states | Design system polish |
| **M7 — "Shippable"** | Signed, notarized `.app` from GitHub Releases | bundle/notarize scripts, README, PRIVACY, LICENSE |
| v1.1 | Menu-bar extra, notifications, tmux, iTerm2 | — |

---

## 13. Experiments before lock-in (Phase 0, ~1 day total, all as throwaway scripts in `scripts/probes/`)

| # | Hypothesis | Implementation | Pass if… |
|---|---|---|---|
| **E1** | `~/.claude/sessions/<pid>.json` `status` has a distinct value while Claude waits for **permission** | Start a session in default permission mode and ask it to run a shell command. While the approval prompt is up, `cat` the file. Repeat for an `AskUserQuestion`-style question. | If a third value appears (e.g. `waiting`), the hook becomes nearly unnecessary. If it stays `busy`, the hook or the 20 s heuristic is needed. *Either result is fine; this decides M5 priority.* |
| **E2** | Stale `sessions/*.json` files are cleaned up when Claude exits, including on `kill -9` | Start a session, `kill -9` it, then `ls ~/.claude/sessions`. | The file is removed → deletion = Ended. The file stays → the pid-liveness check is mandatory (it is planned anyway). |
| **E3** | A running Codex process can be tied to its rollout file | While `codex` runs, `lsof -p <pid> \| grep rollout`. | The rollout path appears → exact PID correlation via `proc_pidfdinfo`. If not → match on cwd + start time and leave the pid nil when ambiguous. |
| **E4** | Codex rollouts contain an event while waiting for command **approval** | Run Codex with `approval_policy=on-request`, trigger a command, then `tail -f` the rollout during the prompt. | Some `event_msg` with approval-ish type appears → Codex gets `waitingDetection`. |
| **E5** | Codex `notify` / `hooks.json` can report turn state without breaking the user's config | Read the current Codex docs/source for the hooks schema and `notify`. Test a no-op script. | Documented and non-destructive → a future optional Codex hook. *Not needed for v1.* |
| **E6** | The hook script can pull fields from stdin JSON using only built-in macOS tools, in < 10 ms | `sh` script using `/usr/bin/plutil -extract … raw -` (reads JSON) or `osascript -l JavaScript`. Time it with `hyperfine` or `time` over 100 runs. | p95 < 10 ms and no `jq`. Otherwise just copy stdin verbatim (it's small) and let Branches do the filtering. |
| **E7** | Ghostty can focus a specific surface from outside | Check Ghostty's current AppleScript/CLI docs (install Ghostty first). | Documented → v1.1 L1. Otherwise L2. |
| **E8** | Terminal.app tab focus by tty works from a signed, non-sandboxed app with one Automation prompt | `osascript -e 'tell application "Terminal" to repeat with w in windows … if tty of t is "/dev/ttys003" then set selected of t to true; set index of w to 1'` | The correct tab comes forward, the prompt appears once, and denial is detectable (error −1743). |
| **E9** | FSEvents file-level events on `~/.claude/projects` fire within 300 ms of an append, with negligible CPU | 30-line Swift script that prints events; tail a live session. | Latency < 0.5 s, idle CPU ≈ 0. |
| **E10** | Tail-reading 64 KB is enough to recover title + last state for >95% of sessions | Run over all local transcripts. Compare the result against a full parse. | ≥ 95% agreement; otherwise raise to 256 KB. |

---

## 14. Testing strategy

Focus: the parts that can silently lie to the user (parsing and status). Skip snapshot-testing SwiftUI.

| Area | Tests |
|---|---|
| **Fixtures** | Sanitized real transcripts per provider version (prompts replaced with lorem ipsum, paths anonymized). A `scripts/sanitize-fixture.py` makes adding a new version a one-command job. Scenarios: one-turn session, tool-heavy session, permission wait, error turn, subagent, resumed session. |
| **JSONLTailReader** | Line split across two reads. File truncated (offset > size). File replaced (new inode). CRLF. Empty lines. A 200 MB file only reads the tail. Invalid UTF-8. |
| **Malformed / changed formats** | Garbage line → skipped + counted. Unknown `type` → ignored + counted. Missing required field → the record is skipped, not the file. Extra fields → no effect. Test: "every fixture from every version still parses without throwing". |
| **StatusEngine** | **Table-driven**, with one test case per row of the transition table, an injected `Clock`, and time-travel for decay (3 min / 15 min / 30 min / 12 h). Evidence precedence and same-timestamp tie-breaks. |
| **Process disappearance / PID reuse** | A fake `ProcessTable` protocol: the pid vanishes → Ended. The same pid returns with a different start time → Ended. |
| **Sleep/wake** | Simulate a clock jump of 2 h plus a wake notification → no false Unknown, rescan triggered. |
| **App restart** | Bootstrap from a fixture directory → the same sessions and statuses as live ingestion of the same files. |
| **Simultaneous sessions** | 3 sessions in the same cwd plus 2 providers in the same project → correct keys, grouping, no cross-talk. |
| **HookInstaller** | Merge into an empty settings file, into existing hooks (the user's real shape), idempotent re-install, uninstall restores byte-identical JSON, backup file created. |
| **Integration (manual, scripted)** | `scripts/probes/fake-agent.sh` appends fixture lines to a temp dir with realistic timing. Run the app pointed at it (`BRANCHES_ROOT_OVERRIDE`) and eyeball it. |
| **Privacy guard** | A test that fails if `BranchesKit` sources contain `URLSession`, `import Network` or `NWConnection`. |

---

## 15. Build checklist (hand this to Claude Code, top to bottom)

Each task is small, verifiable, and depends only on tasks above it.

### Phase 0 — Probes
- [ ] 0.1 Run **E1, E2** (Claude state file behavior). Record the results in `docs/probe-results.md`.
- [ ] 0.2 Run **E9** (FSEvents Swift script). Record latency and CPU.
- [ ] 0.3 Run **E3, E4** (Codex PID correlation, approval events).
- [ ] 0.4 Run **E8** (Terminal tty focus via osascript).
- [ ] 0.5 Run **E6** (hook script field extraction timing).
- [ ] 0.6 Run **E10** (64 KB tail sufficiency).
- [ ] 0.7 Update `03-architecture.md` wherever a probe contradicted an assumption.

### Phase 1 — Skeleton
- [ ] 1.1 `Package.swift` with `BranchesKit`, `BranchesApp` and `BranchesKitTests`. `swift build` and `swift test` pass.
- [ ] 1.2 `BranchesApp` shows a single `Window` with the placeholder text "No coding agents running."
- [ ] 1.3 `scripts/bundle.sh` produces a double-clickable `Branches.app` (ad-hoc signed).
- [ ] 1.4 `Support/Log.swift`, `Support/Clock.swift`, `Support/Paths.swift` (with `BRANCHES_ROOT_OVERRIDE` for tests).
- [ ] 1.5 Domain types: `SessionKey`, `Session`, `ProjectRef`, `Observation`, `Fact`, `StatusResult`. They compile, with no logic.
- [ ] 1.6 `ProviderAdapter` protocol + `ProviderCapabilities` + `ProviderDiagnostics`.

### Phase 2 — Claude observer
- [ ] 2.1 `FileWatcher`: FSEvents → `AsyncStream<[URL]>`. Test: create/append in a temp dir → an event is received.
- [ ] 2.2 `ClaudeSessionsFile`: decode `sessions/*.json` (every field optional; ignore `*.key`). Fixture test.
- [ ] 2.3 `ClaudeAdapter.bootstrap` + `ingest` for `sessions/*.json` only → `.discovered`, `.pid`, `.liveStatus`.
- [ ] 2.4 `SessionStore` actor: apply observations, publish a snapshot. `AppModel` renders a plain list. **→ M1 runnable.**
- [ ] 2.5 `JSONLTailReader` with cursor, partial-line and truncation handling, plus its tests.
- [ ] 2.6 `ClaudeRecords`: an envelope decode + `user` / `assistant` / `last-prompt` / `custom-title` shapes. Fixture tests, including unknown types.
- [ ] 2.7 Adapter emits `.userPrompt`, `.toolStarted/.toolFinished`, `.turnEnded`, `.title` from transcripts. Maps tool names to activity text ("Edit" + file → "Editing Auth.swift", "Bash" → "Running command", "Read" → "Reading …").
- [ ] 2.8 Project grouping by git root (walk up looking for `.git`, cached per cwd).

### Phase 3 — Status
- [ ] 3.1 `StatusEngine` pure function + table-driven tests for every transition-table row.
- [ ] 3.2 Decay scheduler (a single earliest-deadline task) + tests using the fake clock.
- [ ] 3.3 `lastSeen` in UserDefaults; Done → Idle on focus.
- [ ] 3.4 Sleep/wake handling. **→ M2 runnable.**

### Phase 4 — Codex
- [ ] 4.1 `CodexRecords` (`session_meta`, `turn_context`, `event_msg` types, `response_item` tool calls) + fixtures.
- [ ] 4.2 `CodexAdapter` watching `~/.codex/sessions/**` + `session_index.jsonl` titles.
- [ ] 4.3 Register the adapter; Codex rows appear. **→ M3 runnable.**

### Phase 5 — Process correlation
- [ ] 5.1 `ProcessScanner`: `sysctl` snapshot (pid, ppid, start time, tty, uid), `proc_pidpath`, cwd via `proc_pidinfo`. Behind a `ProcessTable` protocol for tests.
- [ ] 5.2 `HostAppResolver`: walk ppid to the first `.app` → `HostApp`.
- [ ] 5.3 Liveness: pid death / start-time mismatch → `.sessionEnded`. A 2 s tick only while Working or Needs you.
- [ ] 5.4 Codex pid matching per the E3 result.

### Phase 6 — Navigation
- [ ] 6.1 `FocusService` with the L1→L4 ladder and a result enum (for the toast).
- [ ] 6.2 `TerminalAppFocuser` (AppleScript tty match; handle −1743 denial → L2).
- [ ] 6.3 L2 via `NSRunningApplication.activate`, L3 `NSWorkspace.open(folder)`, L4 copy the resume command. **→ M4 runnable.**
- [ ] 6.4 `HookInstaller` (backup, tagged merge, diff confirm, uninstall) + tests.
- [ ] 6.5 `branches-claude-hook.sh` + `ClaudeHookInbox` → `.needsAttention`, `.toolStarted`, etc. **→ M5 runnable.**

### Phase 7 — Visual polish
- [ ] 7.1 DesignSystem tokens (Palette, Typography, Metrics, Motion).
- [ ] 7.2 `ProjectGroupView` + `BranchConnector` + `StatusNodeView` (all node variants, Reduce Motion).
- [ ] 7.3 Row hover, selection, context menu, toast.
- [ ] 7.4 Keyboard navigation and filter.
- [ ] 7.5 Empty state, first-run hook card, settings popover, diagnostics view. **→ M6 runnable.**

### Phase 8 — Packaging
- [ ] 8.1 Info.plist (`NSAppleEventsUsageDescription`), entitlements, Hardened Runtime.
- [ ] 8.2 `notarize.sh` (Developer ID, notarytool, stapler).
- [ ] 8.3 README with screenshot, PRIVACY.md, LICENSE, `Providers/README.md`.
- [ ] 8.4 GitHub Actions: `swift build` + `swift test` on macOS runners.
- [ ] 8.5 First GitHub Release (zip/DMG). **→ M7.** A Homebrew Cask can follow later.

---

## What I would build first tomorrow morning

The goal: a real Claude Code session appears live in a native Branches window, in about 2 hours.

1. **(10 min) Check the key assumption.** Open two Claude sessions in Terminal. In a third tab: `watch -n 0.5 'ls ~/.claude/sessions; grep -h status ~/.claude/sessions/*.json'`. Prompt one session and watch it flip `idle → busy → idle`. Then trigger a permission prompt and note the status value (E1).
2. **(15 min)** `swift package init --type executable --name Branches`, then turn it into the 3-target `Package.swift`. Add an `@main` SwiftUI `App` with one `Window`. Run `swift run BranchesApp` and a window appears.
3. **(20 min)** `ClaudeSessionsFile.swift`: a `Decodable` struct with every field optional. A function reads every `~/.claude/sessions/*.json` (skipping `*.key`) → `[LiveClaudeSession]`.
4. **(20 min)** `FileWatcher.swift`: a minimal FSEvents stream on `~/.claude/sessions` → `AsyncStream`. On every event, re-read the whole folder (there are only a handful of tiny files, so no cursors needed yet).
5. **(20 min)** `AppModel` (`@Observable`): holds `[LiveClaudeSession]`, grouped by `cwd` last path component. `ContentView`: a `List` of project headers → rows showing `name`, a green dot for `busy` or a grey dot for `idle`, and "since" computed from `statusUpdatedAt` with `Text(date, style: .relative)`.
6. **(15 min)** Liveness: `kill(pid, 0) == 0` to filter out dead pids (covers E2 either way).
7. **(10 min)** Row click → `NSWorkspace.shared.open(URL(fileURLWithPath: cwd))` as a crude L3 jump.
8. **(10 min)** Run it next to your real sessions. Prompt Claude and watch the dot go green within a second.

That is **M1**. Every later milestone adds to this without replacing it: the transcript reader supplies better titles and activity, Codex becomes a second adapter, and the Terminal focus replaces step 7.
