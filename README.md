# Awake

> **wake up. read the bar.**

A status bar for [Claude Code](https://claude.com/claude-code) that actually tells you where you are.

**Designed for [gsd-pi](https://github.com/open-gsd/gsd-pi)** — the GSD framework. The Context Management block works in any Claude Code project; the GSD Status block lights up when you're inside a gsd-pi project.

Two blocks, four lines, no decoding.

```
✳ Context Management
│  Opus 4.7 (1M context)
│  my-project · V1.0.0 · ⎇ main ●
│  25% used ↻ 3h · ▓▓░░░░░ 18%
│  47% used ↻ 4d 3h

◎ GSD Status
│  Milestone: v1.2 Context Management Redesign
│  Phase: GSD Block Redesign · Phase 3/7
│  Stage: ◓ Executing · Plan 2/5  ⇒  Verify
```

## What you see

**Context Management** — your work context at a glance:
- Active Claude model with capacity tier
- Project directory · package.json version · git branch + state (behind, conflict, detached, rebasing, no-remote)
- 5-hour rate-limit window + conversation memory gauge (3-zone color: green / amber / red)
- 7-day rate-limit window (Max plan only — auto-hides on Pro)

**GSD Status** — your workflow position when you use the [GSD framework (gsd-pi)](https://github.com/open-gsd/gsd-pi). Awake's GSD block is purpose-built for the GSD project structure (milestones, phases, stages, plans, side-channels):
- Current milestone name
- Current phase + position (`Phase 3/7`)
- Current stage with rotating spinner when active, ⚠ when hung >60s
- Side-channels (Quick / Fast / Debug) replace the Stage row when active
- Collapses to a one-liner when ready to ship or between milestones

## Why

You opened a Claude Code tab. You used to ask Claude "where am I?" and burn tokens waiting for a recap. That's the failure mode this bar fixes.

The bar answers four questions in <1 second of glancing:

1. **Where am I?** — project · milestone · phase
2. **Is something running?** — spinner glyph + green vs static + red
3. **What's left?** — phase counter · plan counter (when executing)
4. **What's next?** — `⇒ <next stage>` or `⇒ <next command>`

No notification spam. No alerts row. No decoding required.

## Install

```bash
# Clone wherever you want — the bar is relocatable, no hardcoded paths.
git clone https://github.com/<your-handle>/awake-bar.git ~/.awake-bar
```

Wire it into Claude Code via `~/.claude/settings.json`:

```json
{
  "statusLine": {
    "type": "command",
    "command": "bash ~/.awake-bar/statusline-gsd.sh"
  },
  "subagentStatusLine": {
    "type": "command",
    "command": "bash ~/.awake-bar/subagent-statusline.sh"
  },
  "hooks": {
    "UserPromptExpansion": [{
      "hooks": [{
        "type": "command",
        "command": "bash ~/.awake-bar/hooks/track-gsd.sh"
      }]
    }],
    "Stop": [{
      "hooks": [{
        "type": "command",
        "command": "bash ~/.awake-bar/hooks/track-stop.sh"
      }]
    }],
    "SessionStart": [{
      "hooks": [{
        "type": "command",
        "command": "bash ~/.awake-bar/hooks/prewarm-powerline.sh",
        "timeout": 5
      }]
    }]
  }
}
```

The SessionStart hook is optional — it pre-warms `@owloops/claude-powerline` in the background so the first render of a fresh tab is fast (~600ms instead of ~2.6s).

## Requirements

- **macOS** (bash 3.2 — the system bash works fine; no need to upgrade)
- **Node.js** + npx (for [@owloops/claude-powerline](https://github.com/Owloops/claude-powerline))
- **jq** (for parsing Claude Code's input JSON)
- **git** (for branch state)

Linux compatibility is likely but untested — feel free to file an issue.

## States reference

### Context Management

| State | What renders |
|---|---|
| Normal | model · dir · version · branch · 5h · memory · weekly |
| Pro plan | Weekly row hidden (no `seven_day` quota data) |
| Non-Node project | Version segment omitted |
| Cold-start | First render warm via SessionStart hook |

### GSD Status

| State | Trigger | Shape |
|---|---|---|
| Active mid-phase | live signal fresh | 3 rows, ◓ spinner green |
| Hung | live signal >60s stale | 3 rows, ⚠ static red |
| Transition | phase verified, next not started | 3 rows, `⇒ Discuss (next phase)` |
| Side-channel | /gsd-quick / /gsd-fast / /gsd-debug running | Stage row replaced |
| Ready to ship | last phase verified, milestone not closed | 1 row, `⇒ /gsd-complete-milestone` |
| Last shipped | milestone archived, no new one started | 1 row, `⇒ /gsd-new-milestone` |
| Mid-roadmapping | /gsd-new-milestone running | 2 rows (Milestone + Stage), no Phase |
| Non-GSD project | no `.planning/` directory | Block hidden |

## Colors

| ANSI | Purpose |
|---|---|
| 231 | Block titles (rare — most titles colored now) |
| 173 | `✳ Context Management` title (Anthropic orange) |
| 117 | `◎ GSD Status` title (GSD blue) |
| 252 | Active values (model name, branch, percentages) |
| 240 | Structure (labels, separators, rail glyph `│`) |
| 141 | GSD progress bar fill, active step |
| 114 | Live signals: branch healthy, active spinner |
| 178 | `⚡ Quick` glyph, branch warning, amber gauge zone |
| 203 | `⚠` hung glyph, branch danger, red gauge zone |
| 209 | `⌖ Debug` glyph (red-orange) |

## Testing

```bash
bash tests/v1-ship-gate.sh
```

The ship-gate runs ~60 tests covering rendering correctness, palette lock, performance budget (<600ms median), and per-state regressions.

To run smoke tests against your own GSD project as a fixture:

```bash
AWAKE_FIXTURE_PROJECT=/path/to/your/gsd-project bash tests/v1-ship-gate.sh
```

To skip the fixture-dependent tests entirely:

```bash
AWAKE_FIXTURE_PROJECT="" bash tests/v1-ship-gate.sh
```

## Acknowledgements

Built on:
- [@owloops/claude-powerline](https://github.com/Owloops/claude-powerline) — the powerline renderer for the Context Management block
- [gsd-pi](https://github.com/open-gsd/gsd-pi) — the GSD framework Awake's GSD block is designed for
- The Claude Code team for shipping `statusLine` + `subagentStatusLine` config hooks

## License

MIT — see [LICENSE](./LICENSE).
