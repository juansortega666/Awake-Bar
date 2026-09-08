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

### Git worktrees

Run one agent per worktree — with [Orca](https://orca.computer), `git worktree` by hand, or any other orchestrator — and `basename(cwd)` stops being the project. It's the worktree slug, and the project name disappears from the bar entirely. Awake resolves the real project and shows both:

```
│  my-project ⑂ payments-refactor · V1.4.0 ●
```

Left of `⑂` is the project (from the main checkout), right of it is the worktree you're standing in.

When the branch is just the worktree name behind a namespace — the default for orchestrator-generated branches like `you/payments-refactor` — the branch token is dropped, because it repeats what you're already reading. Status flags stay. When the branch says something the worktree name doesn't, it stays:

```
│  my-project ⑂ mint-rule · V1.4.0 · ⎇ …/disable-mint-condition ●
```

Long branch names truncate from the *front*, keeping the part that identifies them. `you/some-long-feature-name` renders as `…/some-long-feature-name`, not `you/some-long-fea…`.

In a normal checkout none of this fires — the row renders exactly as it always has.

### Fleet awareness

The 5-hour and 7-day numbers are account-wide, but the bar used to present them as if this session were the only thing spending them. Run several agents and the window climbs for reasons you can't see. Awake counts the live sessions and puts the count next to the quota it explains:

```
│  25% used ↻ 3h · 5 sessions · 2 active · ▓▓░░░░░ 18%
```

`5 sessions` is how many Claude Code sessions are alive on this machine. `2 active` is how many are actually mid-turn — the rest are tabs sitting at a prompt, spending nothing. Idle tabs heartbeat exactly like working ones, so counting sessions alone would blame the wrong thing; the split comes from each session's transcript mtime, which goes quiet between turns.

Alone, the segment doesn't render at all. All idle, you get `5 sessions` with no `active` half.

It works for any multi-session setup — an orchestrator, `git worktree` by hand, or just extra tabs. There's no daemon and no IPC: each render drops a heartbeat file, each bar counts the fresh ones. Two knobs:

- `AWAKE_NO_FLEET=1` turns it off completely — nothing rendered, nothing written to disk.
- `AWAKE_FLEET_DIR=/some/path` moves the heartbeat directory off `/tmp/awake-agents-<uid>`.

Sessions on other machines don't appear. `/tmp` is local, and this is deliberately not networked.

### The block never goes blank

The Context Management block is a hard invariant: it always renders, and no row is ever left empty.

The model and identity rows normally come from `claude-powerline`, which runs through `npx`. If that call comes back with nothing — offline, not installed, starved under load — Awake first reuses its last good render (up to 60s), and if there isn't one, rebuilds both rows from what it already knows locally: the model name off the status payload, and the identity from the working directory, the worktree, `package.json`, and git. Plainer than the normal render, but it still answers where you are.

The one thing that can't be rebuilt is the 5-hour window — `claude-powerline` computes it from usage history rather than reading it from the payload. That row collapses to the memory gauge, which is its documented behavior anyway.

This is verified against a broken `npx`, `git`, `jq`, `awk`, `stat`, `sed`, and `date`, a bare `PATH`, an unset `HOME`, and malformed or empty input.

Awake also sweeps its own `/tmp/gsd-*` caches once they're more than a day stale. A live session rewrites them every few seconds, so anything that old belongs to a terminal that closed. The sweep is restricted to Awake's own filename prefixes and to the top level of `/tmp`.

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
git clone https://github.com/juansortega666/Awake-bar.git ~/.awake
```

Wire it into Claude Code via `~/.claude/settings.json`:

```json
{
  "statusLine": {
    "type": "command",
    "command": "bash ~/.awake/statusline-gsd.sh"
  },
  "subagentStatusLine": {
    "type": "command",
    "command": "bash ~/.awake/subagent-statusline.sh"
  },
  "hooks": {
    "UserPromptExpansion": [{
      "hooks": [{
        "type": "command",
        "command": "bash ~/.awake/hooks/track-gsd.sh"
      }]
    }],
    "Stop": [{
      "hooks": [{
        "type": "command",
        "command": "bash ~/.awake/hooks/track-stop.sh"
      }]
    }],
    "SessionStart": [{
      "hooks": [{
        "type": "command",
        "command": "bash ~/.awake/hooks/prewarm-powerline.sh",
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

The ship-gate covers rendering correctness, palette lock, performance budget (<600ms median), per-state regressions, worktree identity, and the powerline stale-fallback contract. Everything except the consumer-smoke block builds its own fixtures in `/tmp` — including real `git worktree` and submodule trees — so it runs anywhere with no host setup.

A handful of tests need a real GSD project to point at. Without one they're skipped and the rest of the suite still runs. To include them:

```bash
AWAKE_FIXTURE_PROJECT=/path/to/your/gsd-project bash tests/v1-ship-gate.sh
```

## Acknowledgements

Built on:
- [@owloops/claude-powerline](https://github.com/Owloops/claude-powerline) — the powerline renderer for the Context Management block
- [gsd-pi](https://github.com/open-gsd/gsd-pi) — the GSD framework Awake's GSD block is designed for
- The Claude Code team for shipping `statusLine` + `subagentStatusLine` config hooks

## License

MIT — see [LICENSE](./LICENSE).
