# Branches: start here

**What it is:** a small Mac app that shows every Claude Code and Codex session running on your computer, what each one is doing, and whether it needs you. You click one to jump to its terminal. It never talks to the agents and never sends anything anywhere.

## Build status (2026-09-24)
v0.1 is built: milestones M1–M4 and M6 from `05-build-plan.md`, plus most of M7. It runs on real sessions. `swift test` passes 34 tests. `scripts/bundle.sh` builds a universal `dist/Branches.app`.

Where the build differs from the plan:
- **The Claude hook (M5) is not needed.** Experiment E1 showed that Claude writes `status: "waiting"` and a `waitingFor` reason ("permission prompt", "input needed", "dialog open", …) to its own status file whenever it's waiting for you. Branches reads that directly. The 6 s "pending tool" guess is now only a fallback for sessions without a status file.
- **Codex PID** is matched by working directory against running `codex` processes, because Codex doesn't record its PID (experiment E3 is still open).
- **Bundle ID** is `app.branches.Branches`. **License** is MIT.
- **Added after v0.1:** a menu bar icon with a "needs you" count and drop-down panel, plus optional notifications (needs you / finished a turn).
- **Forest v1 visual pass (2026-09-25):** treeline header with a time-of-day sky and "needs you" fireflies, plant status glyphs, twig connectors and a forest-floor background. See `04-design.md`. `--screenshot` also takes `--window-size WxH`, `--scene dawn|day|dusk|night`, `--scroll N` and `--menu-bar-screenshot <prefix>` (captures the real menu bar icon and the drop-down it opens).
- **Not done yet:** Developer ID signing + notarization (`scripts/notarize.sh` is ready but needs your Apple Developer certificate) and tmux pane focusing.

## The planning package
| File | Covers (deliverable #) |
|---|---|
| [01-product.md](01-product.md) | Product definition (1), PRD (2) |
| [02-feasibility.md](02-feasibility.md) | What was verified on this Mac and how fragile each part is (3) |
| [03-architecture.md](03-architecture.md) | Architecture (4), provider contract (5), status engine (6), data model (7), implementation spec (10) |
| [04-design.md](04-design.md) | UI spec (8), visual design system (9) |
| [05-build-plan.md](05-build-plan.md) | Repo tree (11), milestones (12), experiments (13), testing (14), build checklist (15), "tomorrow morning" |
| [source/](source/) | The original briefs these were written from |

## The five decisions that shape everything
1. **Claude Code already reports its own live status** in `~/.claude/sessions/<pid>.json` (`busy`/`idle`, plus pid, cwd and session ID). Branches can therefore work with zero setup. The Claude hook becomes optional, used for precise "needs permission" detection.
2. **Codex marks each turn** with `task_started` / `task_complete` events in its session logs, which gives Working → Done without any setup.
3. **No database, no server, no network.** Everything is rebuilt from the agents' own files each time the app opens. Preferences go in `UserDefaults`.
4. **Distributed outside the Mac App Store** (signed and notarized through GitHub Releases), because the App Store sandbox would block reading those folders and focusing terminals.
5. **Five status words:** Working · Needs you · Done · Idle · Ended. Internally, each status also carries a confidence level (reported / inferred / unknown), so a guess is never shown as a fact.

## Verified vs. assumed
Verified on 2026-09-24 against Claude Code 2.1.282 and Codex 0.139.0 by inspecting file structure on this Mac (see `02-feasibility.md`). Still open, and resolved by the Phase 0 experiments (E1–E10):
- Does the Claude status file show a distinct value while waiting for permission?
- Is the status file cleaned up when Claude crashes?
- Can a Codex process be matched to its log file?
- Does Codex log approval waits?
