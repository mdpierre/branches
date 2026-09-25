# Branches — UI Specification & Visual Design System

Deliverables 8 and 9. The goal: *a refined developer tool interpreted through forest materials*. The design is calm, native and dense. It is **not** a cartoon forest.

**Forest v1 (2026-09-24).** The look was made more themed: a treeline header, plant status glyphs, twig connectors and a dark forest-floor background. The rule that keeps it a developer tool: **every drawing carries information or sits behind the content**, and the status words stay literal next to every glyph. Everything is drawn in code. There are no image assets.

---

## 8. UI specification

### Window
- A single window, default **400 × 560 pt**, resizable, remembers its frame.
- Hidden title bar (`.windowStyle(.hiddenTitleBar)`). The content runs under the title bar (`.ignoresSafeArea()`).
- **Background:** the forest floor. It's a vertical gradient: `forest.top` behind the header, easing to `forest.mid`, then to `forest.bottom` near-black at the bottom. On top sit four soft, dappled-light patches and a fine grain (a tiled noise image in screen blend at 7%). All of it is subtle, and the text contrast is unchanged.
- **Treeline header** (`ForestHeader`, 128 pt at rest). A sky gradient sits behind three layers of pines (far, mid and near) drawn with a seeded generator, so the same width always gives the same forest. A wider window grows more trees rather than stretching them. The sky shows a moon and stars at dusk and night.
  - **Time of day:** Dawn / Day / Dusk / Night. Each is a palette only; the shapes never change. *Auto* (the default) follows fixed clock hours: 5–9 dawn, 9–17 day, 17–20 dusk, otherwise night. It uses no location. You can pin a time in Settings. Light mode uses one pale-morning palette.
  - **Fireflies:** one per "Needs you" session (oldest first, max 5), glowing in the treeline. An error is a rust firefly. They add no new information (the chip has the count); they make waiting sessions visible at a glance, even from across the room.
  - **Scroll-to-shrink:** as the list scrolls, the header shrinks from 128 pt to a 40 pt strip of treetops over the first 88 pt. The layers move at different rates (parallax: sky 30, far 70, mid 80, near 88), and a hairline appears under it. Windows shorter than 400 pt start shrunk. With Reduce Motion, it snaps instead of easing.
- **Top strip** (overlaid on the header): the wordmark `BRANCHES`, tracking +8%. On the right, a summary chip such as **`🏮 2 need you · 🌱 3 working`** (click it to cycle the selection through "Needs you" rows), plus a `⋯` settings button. Both sit on `chip` capsules so they read over the sky. Once the header shrinks, the strip moves beside the traffic lights.
- Body: a scrolling list of **project groups**.
- **Menu bar panel:** the same scene at a smaller size: a 60 pt strip of the treeline (the header shrunk most of the way, with the moon and fireflies nudged to stay in view), with the wordmark and summary chip on top. Below it is a flat list of sessions with their plant glyphs, over the forest background.
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
| Branch connector | A `trunk`-colored trunk down the left of the group that **tapers**: 2.6 pt at the first row to about 1.5 pt at the last (ended rows are 1.4 pt). Each row gets a **twig** that curves up from the trunk into its glyph, instead of a square elbow. Drawn with a `Path` in the row's leading 22 pt, not a canvas. |
| Status glyph | A 20 pt plant glyph at the end of the twig (see the glyph table). |
| Provider | `Claude` / `Codex` in `caption.emphasized`, `text.secondary`. A 60 pt fixed column. |
| Title | `body`, `text.primary`, 1 line, truncates at the tail. |
| Status + time | Right-aligned. `Working · 1m 42s` / `Done · 3m ago`. Monospaced digits. |
| Line 2 | Activity (`caption`, `text.secondary`). Falls back to the host app (`Terminal · ttys003`) when there is no activity. |
| Subagents | Indented 16 pt under the parent, with their own smaller elbow (the "fork"). Only shown while Working or Needs you. Otherwise shown as a `+2 subagents` suffix. |

### Status glyphs
Each status is a small plant, drawn in a 20 × 20 pt box (`StatusGlyphs.swift`). The status word beside it is always shown, so the glyph is never the only signal.

| Status | Glyph | Row treatment |
|---|---|---|
| Working | a **sprout** (stem + two leaves, `leaf` / `leaf.light`) that sways ±6° over 1.6 s | normal |
| Needs you | a lit **lantern**: an `amber` core in two soft halos. Still. | title in `text.primary`; status text in `amber` |
| Needs you (error) | an **ember**: a `rust` disc with a `!` | status text `rust` |
| Done | a full **leaf**, `cream` outline with a midrib | normal |
| Idle | a **seed**, `seed` green, tilted | title `text.secondary` |
| Unknown / no recent activity | dotted ring, `text.tertiary` | "No recent activity" |
| Ended | a **fallen leaf**, turned over, `text.tertiary` | row at 50% opacity |

### States
- **Hover:** row background `surface.hover` (cream at 4%). Right edge shows a `↩︎` jump affordance and a `⋯` menu.
- **Selected:** background `surface.selected` (the row's rounded fill, 8 pt corners, reaching back behind the glyph). No side bar. Keyboard focus ring follows the system accent only when full keyboard access is on.
- **Pressed / jumping:** a 150 ms flash of the selection color, then the target app comes forward. If the jump fell back to L3/L4, a small toast appears at the bottom: "Opened folder — exact tab not available for Warp" / "Copied `claude --resume …`".

### Animations
- **Ambient** motion (only two kinds): the Working sprout's sway, and the fireflies' flicker (opacity 0.45↔1, 1.5 s, staggered). Both are Core Animation layer animations, so they cost the app no CPU. Never use a SwiftUI `repeatForever` for them; it re-lays out every frame.
- **Transitions:** row insert/remove (`.opacity.combined(with: .move(edge: .top))`, 200 ms); the glyph crossfades on a status change (150 ms); the header shrinks with scroll (it follows the scroll position, with no timed animation).
- No bouncing, no growing vines, nothing that moves because time passed, except the sprout and the fireflies.
- All of it respects **Reduce Motion**: the sprout is still, the fireflies stop flickering and the header snaps between rest and shrunk.

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
| `forest.top` | `#17211A` | `#E9EDE2` | background under the header; the near treeline |
| `forest.mid` | `#111712` | `#F0EFE7` | background middle |
| `forest.bottom` | `#0B0D0B` | `#F4F1EA` | background bottom |
| `surface.hover` | cream 4% | bark 6% | row hover |
| `surface.selected` | `#2F4A34` @ 45% | `#3D6B45` @ 16% | selection |
| `text.primary` | `#ECE6D8` (warm cream) | `#1E211C` | titles |
| `text.secondary` | `#A9A391` | `#5C5A50` | provider, activity |
| `text.tertiary` | `#6E6A5E` | `#8E8A7E` | paths, ended |
| `bark` | `#5A4E42` | `#A89684` | hairlines |
| `trunk` | `#6A5A47` | `#A08A70` | trunk and twigs |
| `moss` | `#3F5A43` | `#6F8F6F` | selection base |
| `seed` | `#5E8062` | `#6F8F6F` | Idle seed |
| `leaf` (live) | `#7FCF7A` | `#2F8F3A` | Working sprout — **the only saturated green, used sparingly** |
| `leaf.light` | `#9BDB93` | `#55A95E` | the sprout's second leaf |
| `amber` (attention) | `#E0A94A` | `#B7791F` | Needs you: lantern halo, status text, fireflies |
| `lantern.core` | `#F0BE62` | `#C98A22` | the lantern's bright center |
| `rust` (error) | `#C8664A` | `#A4472E` | error variant: ember, error fireflies |
| `cream` | `#ECE6D8` | `#3C3A33` | Done leaf |
| `chip` | `#0B0E0C` @ 60% | white @ 65% | capsules over the header scene |

The header's sky and treeline colors are fixed per time of day, not light/dark tokens. They live in `ScenePalette` in `DesignSystem/Forest.swift`, which uses `Palette.hex`.

These live in `DesignSystem/Theme.swift` as `Color` extensions backed by an asset-free dynamic `NSColor(name:dynamicProvider:)`, so no asset catalog is needed.

### Typography (SF Pro, system sizes)
- `title`: 13 pt semibold (project names)
- `body`: 13 pt regular (session titles)
- `caption`: 11 pt regular, and `caption.emphasized` 11 pt medium
- Times use `.monospacedDigit()`. Paths use SF Mono 11 pt.
- The wordmark is 11 pt semibold, small caps, tracking +8%.

### Spacing & shape
- 4 pt grid. Row padding 8 pt vertical, 12 pt horizontal. Group spacing 14 pt. Connector column 22 pt, glyph column 20 pt.
- Corner radius: rows 8 pt, popover 10 pt, toast 8 pt; chips are capsules.
- Borders: none, except the hairline under the shrunk header (`bark` @ 50%).

### Animation principles
Living, not busy. Ambient motion only ever means something: a sprout sways because an agent is working, and a firefly glows because one is waiting. Everything else is a transition under 200 ms. With nothing working or waiting, nothing moves. Ambient motion runs in Core Animation, so CPU stays near zero.

### Icon direction
The app icon is an abstract single stroke that forks once and ends in a small bright node, drawn in cream on deep moss. The status glyphs and the header are drawn in code (see above). Everything else uses SF Symbols (`arrow.turn.down.left`, `ellipsis`, `folder`, `doc.on.doc`). Keep new drawings to the same rule: flat shapes, forest palette, no gradients on glyphs beyond soft halos, and no wood grain or cartoon faces.
