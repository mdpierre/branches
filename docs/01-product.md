# Branches — Product Definition & PRD

Deliverables 1 and 2. Name: **Branches** (final). License: **MIT**.

---

## 1. Executive product definition

**One sentence.** Branches is a free, open-source macOS app that watches the coding agents already running on your Mac and shows, at a glance, what each one is doing and whether it needs you.

**Problem.** When you run several Claude Code and Codex sessions across several projects, you lose track of them. You keep switching between terminal tabs to find out which agent finished, which one is waiting for approval and which one is still working. The agents and terminals already work well. The missing piece is a single overview of all of them.

**Target user.** A developer on macOS who regularly runs 2–10 terminal coding agents in parallel, across several repositories, and who does not want to change their terminal, their agent CLI or how they launch sessions.

**Core job-to-be-done.** *"When I have several agents running, help me instantly see which ones need me, so I can go to the right one and otherwise stay focused."*

**Principles**
1. **Observe, don't control.** Branches reads what agents already write to disk. It never launches, prompts or proxies anything.
2. **Zero-config first.** Useful the moment it opens. Optional add-ons (such as the Claude hook) only make it more accurate.
3. **Honest status.** Never show a guess as if it were a fact. When unsure, say so quietly.
4. **Local and private.** Branches watches your local coding-agent sessions locally and does not send their contents anywhere.
5. **Small on purpose.** Every feature has to pass this test: *"Open Branches and immediately understand what your coding agents are doing."*
6. **Degrade gracefully.** If a provider's file format changes, that provider shows "unknown". Nothing crashes, and other providers keep working.

**Explicit non-goals.** Branches is not an IDE, a terminal emulator, a chat client, an agent launcher, an orchestrator, a task queue, a diff viewer, a code reviewer, a worktree manager, a Git host, a cloud service or a team tool. It has no accounts, no telemetry and no network calls.

**How this differs from agent orchestrators.** Tools like Tegment, Canopy, Commander, Parallel Code and similar ones ask you to run your agents *inside* them. Branches works the other way round: **it observes the workflow you already have.** It adds value for someone who refuses to change their terminal, CLI, tmux setup or launch habits. Think *Activity Monitor for agents*, not *IDE for agents*.

---

## 2. PRD

### User stories
| # | As a user I want to… | So that… |
|---|---|---|
| U1 | open Branches and see every running Claude Code / Codex session, grouped by project | I know what's running without hunting through tabs |
| U2 | see a one-line description of what each session is working on | I can tell sessions in the same repo apart |
| U3 | see whether each one is Working, Needs you, Done, Idle or Ended | I know where my attention is needed |
| U4 | see how long it has been in that state | I can tell a long-running task from a stuck one |
| U5 | click a session and land in the terminal where it's running | I can act on it instantly |
| U6 | have the list update live without refreshing | I can leave it open on the side |
| U7 | optionally install a Claude hook for more precise "needs you" detection | I get better accuracy only if I want it |
| U8 | know exactly what Branches reads and stores | I can trust it with private code |

### MVP features
1. **Auto-discovery** of Claude Code sessions (`~/.claude`) and Codex sessions (`~/.codex`). No setup.
2. **Project grouping**: sessions are grouped by repository root (git root of `cwd`, falling back to `cwd`).
3. **Session row**: provider, title, current activity, status node, time in state, host app (Terminal / VS Code / Claude app / ChatGPT app …).
4. **Live updates**, driven by file-system events rather than polling.
5. **Status engine** with five UI states: **Working · Needs you · Done · Idle · Ended**. An error counts as "Needs you" with an error reason.
6. **Jump to session**, using the best level available: exact tab → app → open folder → copy resume command.
7. **Optional Claude hook** (one button to install, one to remove) that makes "Needs you" precise.
8. **Diagnostics panel** (hidden in a menu) showing each provider's health: files seen, parse errors, format version.

### Acceptance criteria (MVP is done when all of these are true)
- With no configuration, a live Claude Code session started in any terminal appears in Branches within **2 s** of Branches launching.
- When a Claude session goes from idle to working, the row updates within **1 s**.
- A Codex CLI session appears and shows Working while a turn runs and Done when it finishes, within **2 s**.
- Killing an agent process moves its row to **Ended** within **5 s**.
- Clicking a session running in Terminal.app brings **that exact tab** to the front. For any other host app it at least activates the app.
- Idle CPU is **< 0.5 %** with 10 sessions open, and Branches uses no timers faster than 1 Hz while idle.
- A malformed or truncated JSONL line never crashes the app. It increments a diagnostic counter.
- Branches makes **zero network connections** (can be checked with Little Snitch or `nettop`).
- Branches never writes inside `~/.claude/projects` or `~/.codex/sessions`.

### Interaction model
- A single compact window, plus (later) a menu-bar item.
- Rows are grouped under project headers. The most urgent project comes first ("Needs you", then "Working", then everything else).
- Click or Return → jump to session. ⌘-click → reveal the project folder in Finder. Right-click → context menu (Jump, Open folder, Copy resume command, Copy session ID, Hide).
- Arrow keys move the selection. Type-to-filter by project or title.

### Edge cases (behaviour is defined in `03-architecture.md` §Status engine)
Branches launched mid-session · process died but transcript remains · process alive but transcript quiet · session ended with no clean event · sleep/wake · Branches restarts · missed hook event · several sessions in the same `cwd` · several agents in one project · tmux detached · PID reuse · provider format changed · Claude desktop-app sessions (not in a terminal) · Codex running inside ChatGPT.app.

### v1 non-goals
Sending prompts, approving tool calls from Branches, launching agents, notifications (maybe v1.1), transcript viewer, token/cost tracking, history search, Linux/Windows, Gemini/OpenCode adapters, custom themes, a Mac App Store build.

### Future possibilities (explicitly *not* MVP)
- Menu-bar extra with a "N need you" badge
- Optional macOS notification when a session moves to Needs you
- Gemini CLI / OpenCode adapters
- Subagent fork visualization (the data is already captured in v1)
- tmux pane-exact focusing
- Ghostty / iTerm2 exact-surface focusing
- Homebrew Cask
