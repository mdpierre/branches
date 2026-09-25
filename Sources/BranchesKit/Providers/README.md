# Providers

A provider adapter turns one coding agent's local files into provider-neutral `SessionEvidence`. It is the **only** code that knows that agent's formats, so when Claude Code or Codex changes a format, the fix belongs here, together with a new fixture in `Tests/BranchesKitTests/`.

## Adding a provider

1. Add a case to `ProviderID` (`Domain/Models.swift`).
2. Create `Providers/<Name>/<Name>Adapter.swift`, a class conforming to `ProviderAdapter`:
   - `watchRoots`: the folders to watch with FSEvents (missing folders are fine).
   - `bootstrap(now:)`: discover sessions active in the last 12 h. Read only file tails (`JSONLTailReader(initialTail:)`).
   - `ingest(paths:now:)`: handle changed paths incrementally. `FileWatcher.rescanAll` means "rescan everything".
   - `sessions`: the current `SessionEvidence` for each session.
   - `diagnostics`: counters for the settings popover.
3. Register it in `SessionStore.init`.
4. Add fixture-based tests next to `ProviderAdapterTests.swift`.

## What to fill in on `SessionEvidence`

| Field | Meaning |
|---|---|
| `cwd` | The session's working directory (used for project grouping) |
| `customTitle` / `providerTitle` / `firstPrompt` / `lastPrompt` | Title candidates, in priority order. Pass prompts through `PromptText.clean`. |
| `activity` | A short present-tense line: "Editing Auth.swift", "Running a command". **Never include command text or file contents.** |
| `pid` + `pidNotAfter` | Set only if the provider tells you the PID. `pidNotAfter` guards against PID reuse. |
| `expectsProcess` | True if a live process should exist. If no process is found, the session is Ended. |
| `liveStatus` + `liveStatusAt` | Provider-reported busy/idle/waiting, if the provider has such a thing |
| `turn` + `turnReported` | Turn start/end. `turnReported = true` only when it comes from explicit provider events. |
| `pendingTool` | A tool call that hasn't produced output yet |
| `attention` | `.permission` when the provider says it's waiting for approval; `.error` when a turn failed |
| `resumeCommand` | A shell command that resumes the session |

`StatusEngine` turns this into the five status words. Adapters never decide the status themselves.

## Rules
- Never throw. Skip and count malformed lines; ignore unknown record types and fields.
- Never read credential files.
- Keep only what the UI shows.
