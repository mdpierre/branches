You are helping me design and prepare the implementation of a small native macOS developer utility currently codenamed **Branches**.

I want you to act as a senior product engineer, macOS architect, and technical product designer.

Your job in this phase is **not to immediately start coding the entire application**.

First, turn the product concept below into a rigorous but lean:

1. Product Requirements Document
2. Technical feasibility assessment
3. System architecture
4. Implementation specification
5. Data model
6. Agent-adapter specification
7. State/status model
8. macOS integration plan
9. UI/UX specification
10. MVP build plan
11. Testing strategy
12. Risks / unknowns / experiments
13. Suggested repository structure
14. Ordered implementation checklist

The application should remain intentionally small. Do not turn this into an IDE, terminal emulator, orchestration platform, task manager, or AI chat client.

# Product concept

Branches is a native macOS utility for people running multiple AI coding agents simultaneously.

The problem:

I regularly have Claude Code, OpenAI Codex, and terminals running across multiple projects.

The agents themselves are already good.

The terminals themselves are already good.

I do not want another interface for talking to them.

What is missing is a very simple visual layer above all of them that answers:

- What agents do I currently have running?
- What project is each agent working on?
- What is each agent doing?
- Is it actively working?
- Is it waiting for me?
- Did it finish?
- Where is that session running?
- How do I jump back to it?

Branches should behave more like a **live activity monitor / situational-awareness layer for coding agents** than an agent manager.

A good one-line description is:

> A live activity monitor for your coding agents.

Another framing:

> “Where are all my little guys?”

Branches should observe the tools I already use rather than trying to replace them.

# Core philosophy

The application is **observer-first**.

This is extremely important.

Branches should ideally:

- discover existing Claude Code sessions
- discover existing Codex sessions
- read their locally persisted state
- observe changes to their transcripts/session files
- detect or infer their live state
- correlate sessions with projects/directories/processes
- show them visually
- let me jump back to the relevant terminal/app

It should NOT require me to launch every Claude/Codex session from Branches.

It should NOT own my development workflow.

It should NOT proxy prompts.

It should NOT become another terminal.

It should NOT recreate Claude Code or Codex inside itself.

The ideal experience is:

I continue using Claude Code, Codex, Ghostty, Terminal, tmux, etc. normally.

Branches quietly watches and tells me what is happening.

# Working name / visual metaphor

The current codename is **Branches**.

The visual metaphor is deliberately based on trees/branches.

Potential conceptual hierarchy:

Project / repository = trunk

Agent session = branch

Subagent / child process = child branch

Current operation = growth or endpoint activity

Completed work = dormant/completed branch

Waiting for human input = branch ending at an attention node

This metaphor should be subtle rather than skeuomorphic.

Do NOT design a literal cartoon forest UI.

The aesthetic should feel like:

“a refined developer tool interpreted through forest materials.”

Possible palette:

- charcoal / near-black
- deep moss green
- muted forest green
- bark brown / warm taupe
- warm cream/off-white text
- brighter green used sparingly for live activity

Think restrained, premium, calm, native macOS.

Potential visual interaction:

- a working branch subtly pulses or appears to be growing
- idle branches are still
- completed branches dim
- waiting branches terminate in a visible attention node
- subagents may visually fork from their parent session

The branch visualization must remain readable and functional. Visual metaphor must never overpower information density.

# Core MVP

The MVP should answer four questions exceptionally well:

1. What is running?
2. Where is it running?
3. What is it doing?
4. Does it need me?

A session might display:

Project:
personal-ai

Agent:
Claude Code

Current activity:
Implementing authentication flow

Status:
Working

Elapsed / recency:
Working · 1m 42s

Terminal:
Ghostty / tmux

Possible actions:

- click session
- reveal/focus corresponding terminal if technically possible
- open project directory
- possibly copy/resume session identifier if direct focusing is impossible

Do not add features merely because they are technically possible.

# Initial supported tools

MVP priority:

1. Claude Code
2. OpenAI Codex CLI

Architecture should make later adapters possible for:

- Gemini CLI
- OpenCode
- other terminal-based coding agents

But those are explicitly not required for v1.

Use an adapter/protocol abstraction rather than hardcoding every concept throughout the app.

For example, conceptually:

AgentSource / ThreadSource

- ClaudeAdapter
- CodexAdapter
- ProcessAdapter

Do not assume this exact naming is optimal. Propose the cleanest Swift architecture.

# Known Claude Code observation approach

Claude Code persists conversation/session data locally under its user configuration/state directories.

Investigate and verify the CURRENT Claude Code implementation rather than relying blindly on these paths, but conversation transcripts are known to exist in locations similar to:

~/.claude/projects/<encoded-project-path>/<session-id>.jsonl

Claude Code also supports hooks.

Hooks can expose useful lifecycle information including concepts such as:

- SessionStart
- UserPromptSubmit
- PreToolUse
- PostToolUse
- Stop
- SubagentStop

Hook payloads may include:

- session_id
- cwd
- transcript_path
- hook event type

This potentially gives Branches a reliable live event source.

One possible approach:

UserPromptSubmit → working
PreToolUse → usingTool
PostToolUse → working
Stop → idle / completed / waiting depending on context

Branches could install an optional lightweight Claude Code hook that sends local events into the macOS app through:

- localhost
- Unix domain socket
- another minimal local IPC mechanism

Research which option is simplest and most robust.

Important:

The application should still be able to discover/read Claude sessions even if the optional hook is unavailable.

Therefore distinguish:

1. observed historical/session state
2. inferred live state
3. authoritative live hook state

# Known Codex observation approach

Codex persists session rollouts locally in paths similar to:

~/.codex/sessions/YYYY/MM/DD/rollout-*.jsonl

These rollouts can include:

- conversation events
- user prompts
- assistant messages
- tool calls
- tool outputs
- errors
- session metadata

Again, verify the current implementation before coding against undocumented assumptions.

Codex internally has richer live events/status concepts such as:

- turn started
- item started
- item completed
- turn completed
- active
- idle

However, Branches may not have access to authoritative state for arbitrary already-running Codex processes.

Determine the best current observation strategy.

Possibilities include:

- file activity
- rollout event parsing
- process state
- Codex notifications
- app-server APIs if realistically attachable
- combination of signals

Do not architect the entire app around an API unless we can reliably connect to already-existing sessions.

# Process discovery

Branches should potentially correlate session metadata with running macOS processes.

Example:

Ghostty
  └── zsh
       └── tmux
            └── claude

or

Terminal
  └── zsh
       └── codex

Potential information:

- PID
- parent PID
- executable
- working directory
- parent terminal application
- tmux session/window/pane if discoverable
- project path

Investigate which information macOS allows a normal native app to inspect and what permissions/sandboxing implications exist.

The app should not require excessive system permissions if they can be avoided.

Explicitly discuss Mac App Store sandbox implications versus direct distribution/notarization.

# Unified domain model

Design a minimal unified model representing an observed agent session.

Conceptually it may include:

Thread / AgentSession

- id
- provider
- providerSessionID
- projectName
- repositoryPath
- cwd
- title
- summary
- status
- statusConfidence
- currentActivity
- createdAt
- lastActivityAt
- pid
- parentPID
- terminalApplication
- parentSessionID
- children
- transcriptPath

Do NOT simply copy this structure.

Decide what belongs in:

- persistent domain state
- ephemeral observation state
- provider-specific metadata

Avoid leaking Claude/Codex-specific concepts into the shared domain model unless necessary.

# Status model

This is one of the most important parts of the product.

The UI should expose a tiny understandable state vocabulary, likely something around:

- Working
- Waiting
- Done
- Idle / Stale
- Error

But internally the application needs a more nuanced model.

For example:

AUTHORITATIVE
A provider event or hook explicitly says the agent is currently working/stopped.

INFERRED
Transcript activity, process activity, or recent file writes strongly imply activity.

STALE / UNKNOWN
There is insufficient evidence to know the exact state.

Explore whether the application needs separate:

status
and
statusConfidence

Potential internal activity states might include:

- thinking
- generating
- toolUse
- waitingForTool
- waitingForHuman
- completed
- stopped
- errored
- unknown

The UI should simplify these.

Never present inferred status as authoritative internally.

Design explicit state-transition rules.

Also deal with failure modes:

- app launches halfway through an existing session
- transcript exists but process died
- process exists but transcript stopped updating
- session ended without clean completion event
- laptop sleeps
- Branches restarts
- hook message is missed
- multiple sessions share the same cwd
- same project has multiple agents
- tmux detaches
- Codex/Claude changes transcript format

# Session summary

Branches should display a very short human-readable indication of what the session is doing.

Examples:

“Implementing authentication flow”

“Fixing Gmail parsing”

“Refactoring dashboard navigation”

For MVP, determine the least complicated way to derive this.

Prioritize deterministic/local strategies.

Possible inputs:

- latest user prompt
- most recent assistant planning statement
- current tool call
- file paths being modified

Do not add another expensive LLM call unless there is a compelling reason.

If a lightweight heuristic can generate a useful title, prefer that.

# UI

Native macOS.

Strong preference for Swift + SwiftUI unless research reveals a compelling reason otherwise.

Primary surface should probably be a compact dashboard/window rather than a full IDE-style application.

Possible hierarchy:

BRANCHES

personal-ai
│
├─ Claude
│  Building auth flow
│  ● Working · 1m 42s
│
├─ Codex
│  Fix Gmail parser
│  ✓ Done · 3m ago
│
└─ Claude
   Waiting for input
   ◐ 42s

portfolio
│
└─ Codex
   Fix responsive nav
   ● Working

This is illustrative, not a UI mandate.

Explore:

- grouped-by-project list
- subtle branch-line visualization
- status nodes
- compact typography
- native hover/selection
- keyboard navigation
- menu bar companion later

The first release should not require a complicated canvas/graph renderer if standard SwiftUI layout can convincingly communicate the branch metaphor.

Use animation sparingly.

Working:
subtle living pulse/growth

Waiting:
attention node

Done:
quiet/dimmed

Error:
clear but non-alarming indication

# Native integration

Explore how clicking a session could return the user to its existing environment.

Potential terminal targets:

- Terminal.app
- iTerm2
- Ghostty
- Warp
- tmux

Determine realistic v1 support.

If focusing an exact terminal pane is not reliably possible for every terminal, create graceful tiers:

Level 1:
focus exact pane/session

Level 2:
focus terminal application

Level 3:
open working directory

Level 4:
copy resume/session command

Do not let universal terminal-control complexity block MVP.

# File observation

The app should monitor relevant session directories efficiently.

Research suitable native mechanisms:

- FSEvents
- DispatchSource
- targeted file monitoring
- combination

Requirements:

- low idle CPU
- no aggressive polling
- incremental parsing where possible
- tolerate partially written JSONL lines
- recover after app restart
- handle log rotation/new session files
- avoid reparsing entire large transcripts every time one line is appended

Design a cursor/checkpoint strategy for incremental JSONL ingestion.

# Persistence

Determine whether Branches actually needs a database for v1.

Preference:

Use the least complex persistence mechanism that is robust.

Possibilities:

- no persistent DB; reconstruct from provider state
- lightweight SQLite
- SwiftData
- simple cache/index

Separate source of truth from cache.

Claude/Codex transcripts remain provider-owned source data.

Branches should never mutate those transcripts.

# Privacy

Branches should be local-first.

Default behavior:

- no cloud backend
- no account
- no telemetry required
- no transcript upload
- no agent prompt proxy
- no code upload

Because transcripts may contain source code, secrets, paths, and private conversations, minimize how much raw content Branches stores.

Prefer derived metadata.

Document:

- what is read
- what is cached
- how long it is retained
- where it is stored

# Architecture philosophy

Keep this aggressively simple.

Avoid:

- microservices
- backend servers unless genuinely required
- Electron unless Swift proves unsuitable
- embedded browser stacks
- MCP unless there is a real need
- remote orchestration
- cloud infrastructure
- accounts/auth
- collaboration
- workspace management
- worktree creation
- Git hosting features
- code review
- diff viewers
- terminal emulation
- task queues

Those are separate products.

Branches is the layer ABOVE the user's existing agent workflow.

# Competitive context

There are already products in the broader space that include combinations of:

- multi-agent terminals
- worktrees
- orchestration
- diffs
- launching agents
- integrated coding environments
- status dashboards

Examples currently include tools such as Tegment, Canopy, Treebar, Commander, Pragma, DevHQ, Hypr Code, and Parallel Code.

Do not respond to these products by adding features.

Instead explicitly define Branches' wedge:

**Branches observes the agent workflow you already have.**

It should be able to provide value even to someone who refuses to change:

- their terminal
- their agent CLI
- their tmux setup
- how sessions are launched
- how repositories are structured

Think “Activity Monitor for agents,” not “IDE for agents.”

# Naming

“Branches” is only a working codename.

There are existing software products using similar/exact naming and potentially relevant trademarks.

Do not spend implementation time on final branding.

Use Branches throughout technical artifacts as the project codename.

Keep product identifiers/package naming easy to change later.

# What I want from you now

Before implementing, create the complete planning package.

## Deliverable 1 — Executive product definition

Give me:

- one-sentence description
- problem
- target user
- core job-to-be-done
- core product principles
- explicit non-goals
- what makes this different from agent orchestrators

## Deliverable 2 — PRD

Write a lean but concrete PRD including:

- user stories
- MVP features
- acceptance criteria
- interaction model
- edge cases
- v1 non-goals
- future possibilities clearly separated from MVP

## Deliverable 3 — Technical feasibility report

Verify the CURRENT behavior of:

- Claude Code session persistence
- Claude Code hooks
- Codex session persistence
- Codex available status/event interfaces
- macOS process inspection
- terminal application focusing
- tmux discovery

Prefer primary sources:
- official docs
- official GitHub repositories
- actual source code

For every integration, label the mechanism:

- documented/stable
- undocumented but observable
- heuristic
- optional enhancement

Call out anything likely to break when Claude Code or Codex update.

## Deliverable 4 — Architecture

Design the smallest sensible native architecture.

Include components such as, if appropriate:

- session discovery
- provider adapters
- transcript parser
- filesystem observer
- process correlator
- status engine
- session summarizer
- local cache
- UI store/view model
- terminal focus/open service
- optional Claude hook receiver

Show data flow.

Explain which parts run continuously versus event-driven.

## Deliverable 5 — Provider adapter contract

Define a clean Swift protocol/interface allowing Claude and Codex to produce a common internal session representation.

Include error handling and capabilities.

A provider may support different capability levels such as:

- sessionDiscovery
- transcriptReading
- liveEvents
- toolActivity
- waitingDetection
- processCorrelation
- resumeCommand

Avoid pretending every provider supports the same information.

## Deliverable 6 — Status engine

Define:

- raw provider signals
- normalized internal states
- confidence
- transition rules
- timeout behavior
- stale behavior
- crash recovery

Provide a state-transition table.

This needs special attention.

## Deliverable 7 — Data model

Propose the Swift models.

Separate:

- normalized domain model
- provider metadata
- runtime/process state
- persisted cache

Explain ownership/source-of-truth rules.

## Deliverable 8 — UI specification

Describe the first macOS interface precisely enough to build.

Include:

- main window layout
- project grouping
- session rows
- status nodes
- branch connectors
- selected state
- hover state
- animations
- empty state
- onboarding/permissions
- stale sessions
- keyboard behavior
- visual hierarchy

Keep it small and refined.

Do not create unnecessary screens.

## Deliverable 9 — Visual design system

Create a minimal forest-inspired system:

- semantic colors
- typography
- spacing
- corner radius
- borders
- states
- animation principles
- icon direction

Prefer macOS-native materials/behaviors where appropriate.

Avoid cartoon nature imagery.

## Deliverable 10 — Implementation specification

Give exact implementation recommendations including:

- target macOS version
- Swift version
- SwiftUI/AppKit usage
- packages if any
- directory structure
- major Swift types
- concurrency model
- file watching implementation
- JSONL ingestion
- IPC for Claude hooks
- process enumeration
- persistence/cache
- app lifecycle
- error logging
- sandbox/notarization considerations

## Deliverable 11 — Repository structure

Give me a concrete proposed file/folder tree.

Example only:

Branches/
  App/
  Core/
  Domain/
  Providers/
    Claude/
    Codex/
  Observation/
  Processes/
  Persistence/
  UI/
  DesignSystem/
  Tests/

Choose the actual structure you believe is best.

## Deliverable 12 — Vertical-slice build strategy

I want to reach visible usefulness extremely quickly.

Define the smallest first vertical slice, such as:

1. launch native app
2. discover Claude transcript files
3. parse active sessions
4. display project + latest prompt + last activity
5. live-update when JSONL changes

Then progressively add:

- Claude authoritative hook state
- Codex
- process correlation
- terminal focusing
- branch visualization polish

Give me ordered milestones where EACH milestone leaves behind a runnable product.

## Deliverable 13 — Experiments before architecture lock-in

Identify technical uncertainties that should be answered by tiny prototypes rather than debate.

For each experiment provide:

- hypothesis
- implementation
- expected result
- pass/fail criterion

Examples:

“Can an already-running Claude session reliably be associated with its PID?”

“Can Codex JSONL activity distinguish active generation from idle?”

“Can Ghostty be focused to a specific existing surface?”

## Deliverable 14 — Testing

Cover:

- fixture transcripts
- malformed JSONL
- partially written lines
- filesystem changes
- process disappearance
- sleep/wake
- app restart
- simultaneous sessions
- huge transcripts
- provider format changes

Avoid tests that provide little practical confidence.

## Deliverable 15 — Build checklist

End with a highly actionable build checklist I can hand directly to Claude Code.

Every task should be narrow enough to implement and verify independently.

Order dependencies correctly.

Prefer:

Phase 0 — technical probes
Phase 1 — skeleton
Phase 2 — Claude observer
Phase 3 — status
Phase 4 — Codex
Phase 5 — process correlation
Phase 6 — navigation
Phase 7 — visual polish
Phase 8 — packaging

# Decision rules

When making architecture decisions:

1. Prefer direct observation over taking control of the workflow.
2. Prefer native macOS APIs over dependencies.
3. Prefer event-driven observation over polling.
4. Prefer derived metadata over storing full transcripts.
5. Prefer graceful degradation when authoritative state is unavailable.
6. Prefer shipping a useful approximation over solving universal agent orchestration.
7. Do not over-engineer for hypothetical future providers.
8. Preserve enough abstraction that a third provider is not painful.
9. Keep the app understandable by one developer.
10. Optimize for getting a genuinely usable v0 running quickly.

# Important working style

Do not assume my proposed implementation is correct.

Challenge implementation details when necessary while preserving the product philosophy.

If there is a much simpler way to achieve the same user outcome, choose it.

Distinguish:

- facts verified from current implementations
- architectural recommendations
- assumptions
- unresolved questions

Do not hide uncertainty.

At the end, include a section titled:

**“What I would build first tomorrow morning”**

That section should contain the smallest possible concrete implementation sequence that gets a real Claude Code session appearing live inside a native Branches window.