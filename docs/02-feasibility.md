# Branches — Technical Feasibility Report

Deliverable 3. Verified on **2026-09-24** on macOS 26.5.2 (arm64), Xcode 26.5, Swift 6.3.2, **Claude Code 2.1.282**, **Codex CLI 0.139.0**.

Labels:
- **[DOC]** documented/stable
- **[OBS]** undocumented, but verified by inspecting real files and processes on this machine
- **[HEU]** heuristic
- **[OPT]** optional enhancement
- **[UNVERIFIED]** not yet checked; it becomes a Phase 0 experiment

Only file *structure* (keys and record types) was inspected, never message contents.

---

## Headline finding (changes the original plan)

**Claude Code already writes a live, per-process status file:** `~/.claude/sessions/<pid>.json`. **[OBS]**

```jsonc
{
  "pid": 12345,
  "sessionId": "uuid",            // → matches ~/.claude/projects/*/<sessionId>.jsonl
  "cwd": "/path/to/project",
  "startedAt": 1790290222308,     // ms epoch
  "procStart": "Thu Sep 24 22:50:21 2026",  // guards against PID reuse
  "version": "2.1.282",
  "kind": "interactive",
  "entrypoint": "cli",            // or "claude-desktop"
  "name": "…", "nameSource": …,   // session display name
  "status": "busy",               // observed values: "busy", "idle"
  "statusUpdatedAt": 1790290425103,
  "updatedAt": 1790290425103,
  "messagingSocketPath": "/tmp/cc-socks/<pid>.sock"
}
```
Next to each `.json` there is a `<pid>.<hash>.key` file. **Branches must never read `.key` files.**

With only this file, Branches gets live status, PID↔session↔cwd correlation and the session name, with **zero configuration and no hook**. That turns the Claude hook from "the main live source" into "an optional precision upgrade" (mainly for detecting *waiting for permission*).

Risk: it's undocumented, so it could change or disappear in any release. Treat it as a strong signal with fallbacks, not as the foundation. Values other than `busy`/`idle` (for example a waiting state) are **[UNVERIFIED]** → Experiment E1.

---

## Claude Code

| Mechanism | Label | Verified facts | Breakage risk |
|---|---|---|---|
| Transcripts `~/.claude/projects/<encoded-cwd>/<sessionId>.jsonl` | OBS | Present. The directory name is the cwd with `/` and non-alphanumerics replaced by `-` (e.g. `My Project` → `My-Project`). **Lossy**, so never decode it; read `cwd` from the records instead. | Medium |
| Subagent transcripts `…/<sessionId>/subagents/agent-<id>.jsonl` | OBS | Present. Records carry `isSidechain`. | Medium |
| Record envelope | OBS | Common keys: `type, uuid, parentUuid, sessionId, timestamp, cwd, gitBranch, version, entrypoint, isSidechain, userType`. | Low–Med |
| Record `type` values | OBS | `user`, `assistant`, `attachment`, `last-prompt`, `custom-title`, `agent-name`, `queue-operation`, `file-history-snapshot`, plus others. **Unknown types must be ignored.** | High (new types appear often) |
| `assistant.message` | OBS | Anthropic API shape: `content[]` with `text` / `thinking` / `tool_use`, plus `stop_reason`, `model`, `usage`. | Low (mirrors the public API) |
| `user.message.content` | OBS | Either a string (a human prompt) or a list of `tool_result` blocks. | Low |
| `last-prompt` record | OBS | `{lastPrompt, sessionId}`: a ready-made "latest prompt" for titles. | Medium |
| `custom-title` record | OBS | `{customTitle}`: a user- or app-assigned title. | Medium |
| Live status `~/.claude/sessions/<pid>.json` | OBS | See above. Four live sessions ↔ four files ↔ four live PIDs. Whether stale files are cleaned up after a crash is **[UNVERIFIED]** (E2). | High |
| Hooks (`settings.json` → `hooks`) | DOC | Events include `SessionStart`, `UserPromptSubmit`, `PreToolUse`, `PostToolUse`, `Notification`, `Stop`, `SubagentStop`, `SessionEnd`, `PreCompact`. The payload arrives on stdin as JSON with `session_id`, `transcript_path`, `cwd`, `hook_event_name`. `Notification` fires when Claude needs permission or has been waiting for input. Re-check against the current docs in Phase 0. | Low |
| User already has hooks | OBS | The existing `~/.claude/settings.json` already defines `PreToolUse`, `PostToolUse`, `Stop` and `PostCompact` hooks. **The Branches installer must merge, never overwrite**, and must uninstall cleanly. | — |
| Process tree | OBS | `claude` → `-zsh` → `login` → `Terminal.app`, each on a real tty (`ttys001` …). Desktop-app sessions have the Claude app as parent and `entrypoint: "claude-desktop"`. | Low |

## Codex

| Mechanism | Label | Verified facts | Breakage risk |
|---|---|---|---|
| Rollouts `~/.codex/sessions/YYYY/MM/DD/rollout-<ISO-ts>-<uuid>.jsonl` | OBS (paths mentioned in Codex docs) | Present (~150 files). The folder is the **start** date, so a session running past midnight stays in yesterday's folder. Watch the whole tree. | Medium |
| Line envelope | OBS | `{timestamp, type, payload, ordinal}` | Medium |
| `session_meta` | OBS | `id, session_id, cwd, cli_version, originator, source, parent_thread_id, timestamp` → identity, project, **parent thread (subagents)**, and origin (CLI vs app). | Medium |
| `turn_context` | OBS | `cwd, model, approval_policy, sandbox_policy, turn_id, …` | Medium |
| `event_msg` → `task_started` / `task_complete` | OBS | Clean **turn start/end** markers. `task_complete` has `last_agent_message`, `duration_ms`. This is the Codex "Working → Done" signal. | Medium |
| `event_msg` → `item_completed`, `token_count` | OBS | Progress ticks while working. | Medium |
| `response_item` → `message`, `reasoning`, tool calls | OBS | OpenAI Responses-API shape. | Medium |
| Approval / "waiting for user" events | **UNVERIFIED** | Not seen in the sample. → E4. | — |
| `~/.codex/session_index.jsonl` | OBS | `{id, thread_name, updated_at}`: **ready-made titles**. | Medium |
| `~/.codex/state_*.sqlite`, `logs_*.sqlite` | OBS | Exist. **Do not depend on them**: the version number is in the filename and they are locked by the running app. | High |
| `~/.codex/hooks.json`, `config.toml` `notify` | DOC/UNVERIFIED | A hooks file exists, and Codex documents a `notify` program for turn-complete. The schema has not been inspected yet → E5. Optional only. | — |
| `~/.codex/archived_sessions/` | OBS | Exists. Ignore it in v1. | — |
| Codex app-server API | — | Rejected for v1: you can't attach to *already running* arbitrary CLI sessions. | — |
| Codex inside ChatGPT.app | OBS | On this Mac, Codex also runs as `Codex (Service)` inside ChatGPT.app. Its rollouts presumably land in the same folder (`originator`/`source` tell them apart). Jump target = activate ChatGPT.app. | Medium |

## macOS process inspection **[DOC]**

- `sysctl(KERN_PROC_ALL)` gives `kinfo_proc` for every process: pid, ppid, start time, **tty device** and uid. No special permission is needed for the user's own processes when the app is **not sandboxed**.
- `proc_pidinfo(PROC_PIDVNODEPATHINFO)` gives the **cwd**. `proc_pidpath` gives the executable. `proc_pidinfo(PROC_PIDLISTFDS)` + `proc_pidfdinfo` gives open files (useful for tying a Codex PID to its rollout file → E3).
- Under **App Sandbox** these calls are restricted for other processes, and `~/.claude` and `~/.codex` can't be read without the user picking them in a folder dialog.

## Terminal focusing

| Target | Best level | How | Label |
|---|---|---|---|
| Terminal.app | **L1 exact tab** | AppleScript: loop over `windows → tabs`, match `tty of tab` to the agent's tty, then `set selected` and activate. Needs a **one-time Automation permission** prompt. | DOC (Terminal scripting dictionary) |
| iTerm2 | L1 | AppleScript sessions expose `tty`. | DOC — not installed here, v1.1 |
| Ghostty | L2 (L1 **UNVERIFIED**) | Activate the app. Scripting support is changing → E7. | — |
| Warp | L2 | Activate app. No stable tab API. | HEU |
| VS Code / Cursor terminal | L2 | Activate the app (optionally `code <folder>` to raise the right window). | HEU |
| Claude desktop / ChatGPT app | L2 | Activate the app. | HEU |
| tmux | L1 inside tmux, + L1/L2 for the outer terminal | `tmux list-panes -a -F '#{pane_pid} #{pane_tty} #{session_name}:#{window_index}.#{pane_index}'` → `select-window`/`select-pane`, then focus the client's terminal. **tmux is not installed on this Mac**, so it's v1.1. | DOC |
| Anything | L3 / L4 | `NSWorkspace.open(folder)` / copy `claude --resume <id>` or `codex resume <id>`. | DOC |

Installed here: Terminal.app, VS Code, Cursor, the Claude desktop app, ChatGPT.app. **So v1 = Terminal.app L1, everything else L2 + L3/L4.**

## Sandbox vs direct distribution — decision

| Need | Under App Sandbox | Direct (Developer ID + Hardened Runtime) |
|---|---|---|
| Read `~/.claude`, `~/.codex` | Only through a user-picked folder + security-scoped bookmark (breaks zero-config) | ✅ |
| `sysctl` / `proc_pidinfo` on agent processes | ❌ / restricted | ✅ |
| AppleScript to Terminal | Needs a temporary-exception entitlement (App Review risk) | ✅ with `com.apple.security.automation.apple-events` + usage string |
| Run `tmux` subprocess | ❌ | ✅ |
| Hook writes into a Branches folder | Container path awkward | ✅ |

**Decision: no sandbox. Ship a Developer ID-signed, notarized app with Hardened Runtime, through GitHub Releases (DMG/zip), then Homebrew Cask.** The Mac App Store is out of scope.

## Things most likely to break on upstream updates
1. `~/.claude/sessions/<pid>.json` (undocumented, recent). This is the highest risk and highest value.
2. New Claude transcript `type` values (harmless if unknown types are ignored).
3. Codex `event_msg` names (`task_started` / `task_complete` have been renamed in Codex's history before).
4. Codex folder layout (`YYYY/MM/DD`).
5. Encoded project folder names (irrelevant if we never decode them).

Mitigation: each provider parses defensively, fixture tests per provider version, a diagnostics panel, and the "unknown" status instead of a crash.
