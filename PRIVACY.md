# Privacy

> Branches watches your local coding-agent sessions locally and does not send their contents anywhere.

## What Branches reads
| Path | Why |
|---|---|
| `~/.claude/sessions/*.json` | Which Claude sessions are running, their folder, and busy/idle status. The `*.key` files next to them are **never** read. |
| `~/.claude/projects/*/*.jsonl` | Session titles, the latest prompt and the current tool. Only the end of each file is read. |
| `~/.codex/sessions/**/rollout-*.jsonl` | Codex session folder, turn start/end and the current tool |
| `~/.codex/session_index.jsonl` | Codex thread titles |
| The macOS process table | Whether each agent is still running, and which app/terminal it runs in |

## What Branches keeps
- **In memory only:** the first line of each session's latest prompt (≤ 80 characters), the name of the file a tool is working on, and timestamps. It's gone when you quit.
- **On disk** (macOS preferences, `app.branches.Branches`): when you last jumped to each session (kept 7 days) and the "show ended sessions" setting. Nothing else.
- Branches never stores or logs transcript contents, command text or code.

## What Branches never does
- It makes no network connections of any kind. A test (`PrivacyGuardTests`) fails the build if networking code is added.
- It never writes to, moves or deletes anything in `~/.claude` or `~/.codex`.
- It never sends prompts to, or controls, any agent.
- It has no telemetry, no analytics and no crash reporting.

## Permissions
- **Automation (Terminal / iTerm2):** asked the first time you jump to a session running there, and used only to select that tab. If you decline, Branches just brings the app forward instead.
