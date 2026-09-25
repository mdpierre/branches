# Branches: guardrails for AI contributors

Branches is a free, open-source, native macOS app that **observes** running Claude Code and Codex sessions and shows what each one is doing. It is an Activity Monitor for coding agents.

Read first: `docs/00-start-here.md` (includes current build status). Build/test: `swift build && swift test`; app bundle: `scripts/bundle.sh`. MIT licensed.

## Hard rules
- **Observe only.** Never launch, prompt, proxy or control agents. Never write inside `~/.claude/projects`, `~/.claude/sessions` or `~/.codex/sessions`.
- **Never read `~/.claude/sessions/*.key`** or any auth/credential file (`~/.codex/auth.json`, etc.).
- **No network.** No `URLSession`, `Network` framework or telemetry in `BranchesKit`.
- **Never log or persist prompt text or tool inputs.** The only raw text kept in memory is the first line of the latest prompt (≤80 chars) and the file name a tool is working on.
- **No third-party packages** without an explicit decision recorded in `docs/`.
- Provider-format knowledge lives **only** in `Sources/BranchesKit/Providers/<Name>/`. The domain model and UI must stay provider-neutral.
- Parsers never throw on bad input: skip the input, count it and continue. Unknown record types and fields are ignored.
- Scope test for every feature: *"Open Branches and immediately understand what your coding agents are doing."* If a feature doesn't serve that, don't build it.

## Stack
Swift 6 (strict concurrency), SwiftUI + minimal AppKit, macOS 14+, SwiftPM only (`swift build`, `swift test`, `scripts/bundle.sh`). Not sandboxed; Developer ID + notarized.
