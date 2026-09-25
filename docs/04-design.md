# Branches — UI Specification & Visual Design System

Deliverables 8 and 9. The goal: *a refined developer tool interpreted through forest materials*. The design is calm, native and dense. It is **not** a cartoon forest.

---

## 8. UI specification

### Window
- A single window, default **380 × 560 pt**, min 320 × 280, resizable, remembers its frame.
- Hidden title bar (`.windowStyle(.hiddenTitleBar)`) with a `.sidebar`-style `NSVisualEffectView` material behind a charcoal tint.
- Top strip (28 pt): the wordmark `BRANCHES` in small caps, tracking +8%, `text.secondary`. On the right, a summary chip such as **`2 need you · 3 working`** (click it to cycle the selection through "Needs you" rows).
- Body: a scrolling list of **project groups**.
- There is no sidebar, no tabs, no toolbar and no second screen. Settings = a small popover from a `⋯` button (hook install/remove, show ended sessions, diagnostics).

### Project group
```
personal-ai                               ~/code/personal-ai
│
├─●  Claude   Building auth flow                 Working · 1m 42s
│    Editing Auth.swift
│
├─◎  Codex    Fix Gmail parser                   Needs you · 12s
│    Waiting for approval
│
└─○  Claude   Refactor settings                  Done · 3m ago
```
- Header: the project name in `title` style. The shortened path (`~/…`) is right-aligned in `caption`, `text.tertiary`, and appears on hover only.
- Group order: any Needs you → any Working → most recent activity. Within a group, the same order, then by start time.
- A group whose sessions have all Ended collapses into a single line: `portfolio · 2 ended` (click to expand). Hidden entirely if "Show ended" is off.

### Session row (two lines, 44 pt tall)
| Slot | Content |
|---|---|
| Branch connector | 1 pt vertical `bark` line down the left of the group, with a 10 pt horizontal elbow into each row's node (`├` / `└`). Drawn with a `Path` in the row's leading 20 pt, not a canvas. |
| Status node | 10 pt, at the end of the elbow (see node table). |
| Provider | `Claude` / `Codex` in `caption.emphasized`, `text.secondary`. A 60 pt fixed column. |
| Title | `body`, `text.primary`, 1 line, truncates at the tail. |
| Status + time | Right-aligned. `Working · 1m 42s` / `Done · 3m ago`. Monospaced digits. |
| Line 2 | Activity (`caption`, `text.secondary`). Falls back to the host app (`Terminal · ttys003`) when there is no activity. |
| Subagents | Indented 16 pt under the parent, with their own smaller elbow (the "fork"). Only shown while Working or Needs you. Otherwise shown as a `+2 subagents` suffix. |

### Status nodes
| Status | Node | Row treatment |
|---|---|---|
| Working | filled `leaf` dot + a slow 2.4 s "breathing" glow (opacity 0.35→0.8) | normal |
| Needs you | 10 pt `amber` ring with a 4 pt filled center; no animation after a single 0.3 s scale-in | title in `text.primary`; status text in `amber` |
| Needs you (error) | same ring in `rust` with a small `!` | status text `rust` |
| Done | hollow `cream` ring | normal |
| Idle | 6 pt `moss` dot | title `text.secondary` |
| Unknown / no recent activity | dotted ring, `text.tertiary` | "No recent activity" |
| Ended | none (the elbow ends in a short cap) | row at 45% opacity |

### States
- **Hover:** row background `surface.hover` (cream at 4%). Right edge shows a `↩︎` jump affordance and a `⋯` menu.
- **Selected:** background `moss` at 22% plus a 2 pt `leaf` bar on the left. Keyboard focus ring follows the system accent only when full keyboard access is on.
- **Pressed / jumping:** a 150 ms flash of the selection color, then the target app comes forward. If the jump fell back to L3/L4, a small toast appears at the bottom: "Opened folder — exact tab not available for Warp" / "Copied `claude --resume …`".

### Animations
- Only three animations exist: the Working breathe, the Needs-you scale-in, and row insert/remove (`.opacity.combined(with: .move(edge: .top))`, 200 ms).
- Status changes crossfade the node (150 ms). No bouncing, no growing vines.
- All animation respects **Reduce Motion**: the breathe becomes a static bright dot.

### Empty & first-run states
- **Nothing found:** centered, `text.secondary`: "No coding agents running." Below it: "Branches watches Claude Code and Codex automatically. Start one in any terminal." Plus a small line listing the watched folders and whether each exists (✓ / not found).
- **First run:** no modal wizard. The list simply appears. A one-time, dismissible footer card reads: "Want exact 'Needs you' detection for Claude? Install the optional hook →", which opens the popover.
- **Automation permission:** requested only on the **first click on a Terminal session**, never at launch. If denied, fall back to L2 silently and show the tip once in the popover.

### Keyboard
| Key | Action |
|---|---|
| ↑ / ↓ | move selection |
| Return | jump to session |
| ⌘O | open project folder |
| ⌘C | copy resume command |
| ⌘1…9 | jump to the Nth "Needs you" session |
| Tab | cycle Needs-you sessions |
| typing | filter by project/title (a filter field appears in the top strip) |
| Esc | clear the filter |
| ⌘, | settings popover |

### Visual hierarchy (most → least prominent)
Needs-you node and status text → project names → session titles → Working node → times → activity line → paths and ended rows.

---

## 9. Visual design system

### Semantic colors (dark is the primary theme; light is supported)
| Token | Dark | Light | Use |
|---|---|---|---|
| `bg.window` | `#141613` (charcoal-moss) | `#F4F1EA` | window tint over the material |
| `surface.hover` | cream 4% | bark 6% | row hover |
| `surface.selected` | `#2F4A34` @ 22% | `#3D6B45` @ 14% | selection |
| `text.primary` | `#ECE6D8` (warm cream) | `#1E211C` | titles |
| `text.secondary` | `#A9A391` | `#5C5A50` | provider, activity |
| `text.tertiary` | `#6E6A5E` | `#8E8A7E` | paths, ended |
| `bark` | `#5A4E42` | `#A89684` | branch connectors |
| `moss` | `#3F5A43` | `#6F8F6F` | idle node, selection base |
| `leaf` (live) | `#7FCF7A` | `#2F8F3A` | Working node — **the only saturated green, used sparingly** |
| `amber` (attention) | `#E0A94A` | `#B7791F` | Needs you |
| `rust` (error) | `#C8664A` | `#A4472E` | error variant |
| `cream` | `#ECE6D8` | `#3C3A33` | Done ring |

Put all of these in `DesignSystem/Palette.swift` as `Color` extensions backed by an asset-free dynamic `NSColor(name:dynamicProvider:)`, so no asset catalog is needed.

### Typography (SF Pro, system sizes)
- `title`: 13 pt semibold (project names)
- `body`: 13 pt regular (session titles)
- `caption`: 11 pt regular, and `caption.emphasized` 11 pt medium
- Times use `.monospacedDigit()`. Paths use SF Mono 11 pt.
- The wordmark is 11 pt semibold, small caps, tracking +8%.

### Spacing & shape
- 4 pt grid. Row padding 8 pt vertical, 12 pt horizontal. Group spacing 16 pt. Connector column 20 pt.
- Corner radius: rows 6 pt, popover 10 pt, toast 8 pt.
- Borders: none, except a 0.5 pt `bark` @ 40% separator under the top strip.

### Animation principles
Living, not busy. There is one ambient motion (the breathe) and everything else is a transition under 200 ms. Nothing animates while idle. This keeps CPU near zero.

### Icon direction
The app icon is an abstract single stroke that forks once and ends in a small bright node, drawn in cream on deep moss. No leaves, no trees, no wood grain. In-app glyphs use SF Symbols only (`arrow.turn.down.left`, `ellipsis`, `folder`, `doc.on.doc`, `exclamationmark`).
