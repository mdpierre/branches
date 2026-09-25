# Open-source project philosophy

Branches is intended to be a **free, open-source macOS utility**.

This is not a startup or SaaS product and should not be architected as one.

There is currently no intention to monetize it.

Optimize for:

- immediate usefulness
- simple installation
- local-first operation
- understandable code
- easy community contribution
- minimal maintenance burden
- minimal dependencies
- zero required accounts
- zero required cloud infrastructure
- zero required API keys where possible
- zero telemetry by default
- zero subscriptions, licensing servers, or payment infrastructure

The ideal experience is:

1. User downloads Branches.
2. User opens Branches.
3. Branches automatically discovers supported coding-agent sessions already present on the Mac.
4. Useful information appears immediately.
5. Optional integrations, such as a Claude Code hook, can be enabled to improve status accuracy.

Treat **zero-config operation** as an important product goal.

If basic session observation can work without modifying Claude Code, Codex, terminal configuration, shell configuration, or tmux configuration, prefer that approach.

Optional configuration should only unlock better capabilities rather than being required for the product to function.

# Distribution

Assume the project will be publicly hosted on GitHub.

Design the project so it can eventually be distributed through mechanisms such as:

- GitHub Releases
- signed/notarized DMG
- Homebrew Cask

Do not make Mac App Store distribution a prerequisite.

Direct distribution may actually be preferable if App Sandbox restrictions materially interfere with:

- reading Claude/Codex state directories
- process inspection
- terminal integration
- local hooks
- Unix sockets
- tmux integration

Analyze this explicitly before choosing sandbox constraints.

# Open-source architecture principles

Because this is OSS, optimize the codebase for a developer being able to clone the repository and understand it.

Prefer:

- boring architecture
- explicit data flow
- small modules
- native APIs
- documented provider adapters
- fixture-based tests
- minimal hidden magic

Avoid unnecessary abstraction solely because Branches might theoretically support dozens of providers someday.

Supporting Claude Code and Codex cleanly is enough to establish the abstraction.

A future contributor should be able to add another provider by implementing a clearly documented provider adapter without understanding the entire application.

# Provider resilience

Claude Code and Codex may change undocumented local formats.

Because Branches is open source and depends partly on observable implementation details, design adapters to fail gracefully.

Provider parsing should be isolated from the rest of the application.

A provider update should ideally require changing:

Providers/Claude/

or

Providers/Codex/

rather than modifying the domain model and UI throughout the application.

Include:

- version-tolerant parsing where sensible
- unknown-field tolerance
- fixture transcripts
- useful diagnostics
- graceful "unsupported/unknown" states

Do not crash because an upstream JSONL structure gained or changed a field.

# Privacy promise

The intended default privacy model should be explainable in approximately one sentence:

> Branches watches your local coding-agent sessions locally and does not send their contents anywhere.

Architect around preserving that promise.

Avoid introducing network access unless a future feature explicitly requires it.

# Scope discipline

The fact that Branches is open source is **not** justification for turning it into a giant developer platform.

In fact, the opposite is preferred.

A successful v1 can be extremely small.

The core product remains:

> Open Branches and immediately understand what your coding agents are doing.

Everything should be evaluated against that sentence.