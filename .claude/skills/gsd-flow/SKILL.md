---
name: gsd-flow
description: GSD framework happy path reference — what each command does, in what order they connect, and which subagents each one spawns. Read this BEFORE making decisions about what the GSD Status Bar should display. The bar's `(cur/tot)` subagent counter, the stage labels, the `Next:` indicator, and the adaptive modes all depend on this mapping being correct.
---

# GSD Flow Reference — Happy Path & Subagents

This document is the **single source of truth** for "what is the GSD framework doing right now?" Every visualization decision in the GSD Status Bar (stage glyphs, gerund labels, `Next:` arrows, the `(cur/tot)` counter, alert thresholds) traces back to this mapping.

## 1. The Happy Path (milestone lifecycle)

```
┌─────────────────────────────────────────────────────────────────┐
│ NEW PROJECT (one-time)                                          │
│   /gsd-new-project                                              │
│      → bootstraps PROJECT.md + REQUIREMENTS.md + ROADMAP.md     │
│      → first milestone is born                                  │
└─────────────────────────────────────────────────────────────────┘
                          ↓
┌─────────────────────────────────────────────────────────────────┐
│ MILESTONE CYCLE (repeated every release)                        │
│   /gsd-new-milestone  (skip on the first milestone)             │
│      → re-discusses domain, rewrites ROADMAP for next vN.M      │
│   ↓                                                             │
│   ┌─── FOR EACH PHASE IN ROADMAP ────────────────────────────┐  │
│   │                                                          │  │
│   │   /gsd-discuss-phase N    → writes CONTEXT.md            │  │
│   │       ↓                                                  │  │
│   │   /gsd-plan-phase N       → writes PLAN.md (xN plans)    │  │
│   │       ↓                                                  │  │
│   │   /gsd-execute-phase N    → writes SUMMARY.md + commits  │  │
│   │       ↓                                                  │  │
│   │   /gsd-verify-work N      → writes VERIFICATION.md       │  │
│   │       ↓                                                  │  │
│   │   (if gaps found: loops back to /gsd-plan-phase N --gaps)│  │
│   │                                                          │  │
│   └──────────────────────────────────────────────────────────┘  │
│   ↓                                                             │
│   /gsd-complete-milestone                                       │
│      → archives ROADMAP to .planning/milestones/v<N>-ROADMAP.md │
│      → bumps version, tags git                                  │
│   ↓                                                             │
│   /gsd-ship  (optional)                                         │
│      → opens PR, runs review, merges                            │
└─────────────────────────────────────────────────────────────────┘
                          ↓
                    (next milestone)
```

## 2. Side Channels (off the main path)

These run **in parallel** with the milestone lifecycle. They do NOT advance phase state and the bar should show them distinctly:

| Command | What it does | When the bar should show it |
|---------|--------------|----------------------------|
| `/gsd-quick` | Small tracked task — runs its own mini plan→execute→commit cycle. Slug lives in `.planning/quick/<id>-<slug>/` | Whenever active, even between milestones. Glyph: ⚡ |
| `/gsd-fast` | Trivial one-shot inline edit. No subagents. No tracked artifacts. | Whenever active. Glyph: » |
| `/gsd-debug` | Investigation session. Can pause mid-phase. | Whenever active. Glyph: TBD (Phase 2 decision) |

## 3. Stage Transitions — what `Next:` shows

The bar's `Next:` field is derived from the current stage:

| Current stage | Trigger event | Next: shows |
|--------------|---------------|-------------|
| (idle) | Milestone roadmapped, phase 1 not started | `Discuss` |
| `Roadmap` (running) | gsd-roadmapper writing ROADMAP.md | `Discuss` |
| `Discuss` (running) | gsd-discuss-phase active | `Plan` |
| `Plan` (running) | gsd-plan-phase active | `Execute` |
| `Execute` (running) | gsd-execute-phase active | `Verify` |
| `Verify` (running) | gsd-verifier or gsd-verify-work active | `Discuss` (next phase) OR `Ship` (last phase) |
| `CodeReview` / `UIReview` / `EvalReview` / `Validate` / `Secure` (any flavor) | Specialty review running | Same as `Verify` — these are sub-stages of Verify |
| `Ship` (running) | gsd-complete-milestone OR gsd-ship | (none — terminal) |
| `Quick` / `Fast` / `Debug` | Side-channel command running | (no Next: — they don't advance the milestone) |

## 4. Subagents Per Command (what `(cur/tot)` measures)

The bar's `(cur/tot)` counter tracks **subagents spawned by the current command**, in order. Below is the canonical list per command. Numbers in parens are the typical total — the actual `tot` will adjust to what the workflow decides to spawn (some agents are optional and config-gated).

### `/gsd-new-project` (up to 6 agents)

| # | Subagent | Purpose | Optional? |
|---|----------|---------|-----------|
| 1-4 | `gsd-project-researcher` × 4 in PARALLEL | One per dimension: stack, features, architecture, pitfalls | Yes (research_enabled) |
| 5 | `gsd-research-synthesizer` | Combines the 4 RESEARCH.md outputs into SUMMARY.md | Yes (only if research ran) |
| 6 | `gsd-roadmapper` | Writes ROADMAP.md | Always |

**Bar view:** During parallel phase 1-4: `(cur/4)` where cur = how many have started. Then `5/6`, `6/6`.

### `/gsd-new-milestone` (same as new-project)

Same shape as `/gsd-new-project` — 4 parallel researchers, synthesizer, roadmapper. Up to 6 agents.

### `/gsd-discuss-phase N` (0 agents in normal mode)

**Normal mode: 0 subagents.** This command is fully interactive — questions only. The bar will see no `(cur/tot)` counter during a normal discuss.

Special modes:
- `--mode=advisor` (USER-PROFILE.md present): spawns 1× `gsd-advisor-researcher` per selected gray area, in parallel. Total depends on how many areas the user selects (1-4).
- `--mode=assumptions`: spawns 1× `gsd-assumptions-analyzer` upfront, then back to interactive.

### `/gsd-plan-phase N` (1-7 agents depending on config)

| # | Subagent | Purpose | Optional? |
|---|----------|---------|-----------|
| 1 | `gsd-phase-researcher` | Writes RESEARCH.md for the phase | Yes (workflow.research) |
| 2 | `gsd-pattern-mapper` | Writes PATTERNS.md mapping new files to closest analogs | Yes (workflow.pattern_mapper) |
| 3 | `gsd-planner` | Writes the PLAN.md files | Always |
| 4 | `gsd-plan-checker` | Verifies plans achieve phase goal | Yes (workflow.plan_check) |
| 5-7 | `gsd-planner` + `gsd-plan-checker` revision loop | If checker found issues, replan + recheck (max 3 iterations) | Conditional |

**Bar view:** Typical run shows `(cur/4)` through the happy path. If revision triggers, `tot` grows to 6 or 8.

### `/gsd-execute-phase N` (1 + N agents per wave, then 1 verifier)

| # | Subagent | Purpose | Optional? |
|---|----------|---------|-----------|
| 1..K | `gsd-executor` × K | One per plan. In parallel within a wave (worktrees), then between waves. | Always (1 per plan) |
| K+1 | `gsd-verifier` | Verifies phase goal achievement against ROADMAP success criteria | Yes (workflow.verifier) |

Plus optional non-counted side-spawns:
- `gsd-code-reviewer` via `/gsd-code-review` skill (workflow.code_review)
- `gsd-integration-checker` for cross-phase E2E (rare)

**Bar view:** During wave 1 of a 3-plan phase: `(cur/3)`. Verifier appears at the end as the +1.

### `/gsd-verify-work N` (2-4 agents)

| # | Subagent | Purpose | Optional? |
|---|----------|---------|-----------|
| 1 | `gsd-planner` | Creates gap-closure plans | Always |
| 2 | `gsd-plan-checker` | Verifies the gap plans | Yes |
| 3-4 | Revision loop if needed | | Conditional |

### `/gsd-complete-milestone` (0 agents)

Pure orchestration — archives ROADMAP, bumps version, tags. The bar shows `Ship` stage but `(cur/tot)` is hidden (no subagents).

### `/gsd-ship` (0 agents)

Pure git/gh orchestration — creates PR, may invoke `/gsd-ultrareview` externally.

### `/gsd-quick` (3-5 agents)

Same shape as `plan-phase` + execute in one flow:

| # | Subagent | Purpose |
|---|----------|---------|
| 1 | `gsd-phase-researcher` | (optional, usually skipped for quick) |
| 2 | `gsd-planner` | One plan for the quick task |
| 3 | `gsd-plan-checker` | (optional) |
| 4-5 | Revision loop | Conditional |
| (then) | `gsd-executor` | Executes the plan inline (not always counted as separate subagent in the panel) |

### `/gsd-fast` (0 agents)

Fully inline. No subagent spawning. The bar should show `Fast` stage but no counter.

### `/gsd-debug` (1 manager + N debuggers)

| # | Subagent | Purpose |
|---|----------|---------|
| 1 | `gsd-debug-session-manager` | Orchestrates a multi-cycle debug loop |
| 1.1..N | `gsd-debugger` × N | Spawned by the manager, one per investigation cycle |

The manager-then-debugger pattern is **2 levels deep** — the bar's `(cur/tot)` only sees the top-level (the manager). The nested debuggers are invisible to the panel.

## 5. What the Bar Tracks vs What It Doesn't

The GSD Status Bar reads two live signals:

- **`/tmp/gsd-cmd-<sid>`** — Written by the `track-gsd.sh` hook on every `/gsd-*` invocation. Carries: `<epoch> <token> <phase> <slug>`. Tells the bar WHICH command is running and (for quick/fast) what slug.
- **`/tmp/gsd-live-<sid>`** — Written by `subagent-statusline.sh` from the running-agents JSON Claude Code exposes. Carries: `<epoch> <stage> <cur> <tot>`. Tells the bar HOW MANY subagents have started and how many total.

**Counted in `(cur/tot)`:**
- Every subagent listed in `.tasks[]` of the subagentStatusLine JSON payload
- This is whatever Claude Code surfaces — typically every Task(...) spawn

**NOT counted:**
- Nested subagents (e.g. gsd-debug-session-manager spawns gsd-debugger — only the manager shows in the panel)
- Skills invoked via `Skill(...)` — those run inline, not as panel agents
- Workflow steps that don't spawn agents (parse args, load context, write files, etc.)

This is why the bar's `(cur/tot)` measures **subagent activity**, not "workflow progress" — they're different things. A `/gsd-discuss-phase` in normal mode has 0 subagents but plenty of workflow steps; the bar will correctly show "Discussing" without a counter.

## 6. State Files That Drive the Bar

Files the bar reads to know where you are:

| File | Drives | Cache strategy |
|------|--------|----------------|
| `.planning/STATE.md` (frontmatter) | Milestone, phase number, plan, progress percent, stage | mtime-based (Phase 1 P-D-11) |
| `.planning/ROADMAP.md` | Total phases, phase names, depends-on | (read once per state change) |
| `/tmp/gsd-cmd-<sid>` | Live command, live phase, quick/fast slug | TTL 30 min (Phase 1 D-08) |
| `/tmp/gsd-live-<sid>` | Live stage, subagent cur/tot counts | TTL 10 s (Phase 1 D-08) |

## 7. Edge Cases the Bar Must Handle Correctly

- **Idle (no /gsd-* command running, but milestone in progress):** Bar shows milestone position from STATE.md. No live stage. `Next:` shows the next phase's stage.
- **Mid-discuss-phase:** Token = `Discuss`. No subagent counter. The bar should NOT show `(0/0)` — it should hide the counter when `tot == 0`.
- **Milestone archived, quick task running:** STATE.md says milestone complete; `/tmp/gsd-cmd-<sid>` says Quick is active. Bar shows the GSD block ONLY because Quick is live (Phase 1 D-15: per-session keying).
- **Parallel /gsd-* commands across sessions:** Each session has its own `<sid>`. Bar reads only this session's `/tmp/gsd-cmd-<sid>`. Other sessions invisible (D-15 again).
- **Verifier running after execute completes:** Token transitions from `Execute` to `Verify` (subagent label drives the live stage per `subagent-statusline.sh`). The bar should NOT bounce — once the executor wave is done and the verifier starts, it's "Verify" until verification finishes.
- **Revision loop in plan-phase:** Subagent panel re-fills with planner+checker. `cur/tot` may go from 4/4 down to a new count when a new wave of subagents spawns. This is expected; the bar shouldn't try to "remember" the highest count.

## 8. What's NOT in this skill (deferred to future v1 work)

This skill covers the **subagent-level visibility** the current bar mechanism supports. The following are explicitly out of scope here and will be decided in Phase 3 (Content Rendering) and Phase 4 (Adaptive Composition):

- Glyph choice per stage (`◔`, `◑`, `▸`, `✓`, etc.)
- Gerund labels (`Discussing`, `Code-reviewing`, ...)
- Color choices per stage (palette is locked: see PALETTE-01)
- Adaptive mode transitions (Idle / Active / Alert thresholds)
- Plan-within-phase counter format (`P27.2/4 · M3/8` — decided in CONTEXT.md but exact rendering TBD)
- Pending counter format (`⚠ 3 todo · 2 uat`)

When working on those phases, **read this skill first** to understand what data is available and what the bar can actually know.

## 9. Bar Modes

This section defines the 3 adaptive modes of the GSD Status Bar, the visibility rules that govern what segments render in each mode, ASCII mockups of every interesting state, and the color glossary. It is the **runtime companion** to §1-§8: §1-§8 describe the framework; §9 describes how the bar reflects it.

### 9.1 Quick Mode Reference

The bar has **3 adaptive modes** — they are NOT mutually exclusive. Alert is **orthogonal**: it appends a row on top of Idle or Active.

- **Idle** — the default fall-through. No `/gsd-*` command is running and milestone is active. Bar shows `Version: v1.7 · M3/8 · Ph27  <bar>  ⇒ Next: Discuss`. No `Now:` segment (that's reserved for live activity).
- **Active** — entered when EITHER live signal is fresh: `/tmp/gsd-cmd-<sid>` (30-min TTL — a `/gsd-*` command is running) OR `/tmp/gsd-live-<sid>` (10-s TTL — subagents are running). Bar shows `Now: <glyph> <gerund> <cascade>  <bar>  ⇒ Next: <stage>`. Spinner glyph rotates per second. `(cur/tot)` counter glues to the gerund when subagents are present.
- **Alert** — ORTHOGONAL row. When `parse_alerts` reports any non-zero count (todo / uat / blocker from STATE.md), `    ⚠ <severity-ordered counts>` is appended to whatever base mode is rendering. Red glyph + counts if any blocker, amber otherwise.

**Hierarchical cascade counter** — the position segment is `M<done>/<total> · Ph<n> · W<cur>/<tot> · Pl<cur>/<tot>` (Milestone > Phase > Wave > Plan, top-down address). All 4 segments appear ONLY during `/gsd-execute-phase`. Other stages drop W and Pl per §9.2.

**Scope note:** the "Alert when context > 70%" trigger was descoped 2026-05-30 — the Context Management block already owns context-usage display.

### 9.2 Visibility Rules

The base render depends on `done` (milestone archived?), `livestage` (any live command?), `is_quickfast`, and `has_alerts`. The 5 rules from Phase 3:

| # | Condition | Render |
|---|-----------|--------|
| 1 | Active milestone, no live, no alerts | `Version · M·Ph  <bar>  ⇒ Next:` (Idle base) |
| 2 | Archived milestone, no quick/fast, no alerts | **Hide entire GSD block** (only Context Management shows) |
| 3 | Archived milestone, no quick/fast, alerts > 0 | `◎ GSD Status / ⚠ <counts>` (alert-only, no Now:) |
| 4 | Archived milestone, quick/fast running, no alerts | `◎ GSD Status / ⚡ Quick: <slug>` (side-channel-only) |
| 5 | Archived milestone, quick/fast running, alerts > 0 | `◎ GSD Status / ⚡ Quick: <slug>    ⚠ <counts>` (both) |

The cascade segment visibility per stage (Phase 4 D-15):

| Stage active | M | Ph | W | Pl |
|--------------|:---:|:---:|:---:|:---:|
| Idle (no command) | ✓ | ✓ | — | — |
| Discussing / Specifying / Researching / UI design | ✓ | ✓ | — | — |
| Planning | ✓ | ✓ | — | — |
| **Executing** | ✓ | ✓ | ✓ | ✓ |
| Verifying / Code-reviewing / UI-reviewing / Eval-reviewing / Validating / Securing | ✓ | ✓ | — | — |
| Roadmapping | ✓ | — | — | — |
| Closing milestone / Shipping | ✓ | ✓ | — | — |
| Quick / Fast / Debug | ✓ | ✓ | — | — |

Decimal phase edge (e.g. `Ph72.1`): Pl is dropped even during Execute. Decimal phases imply a sub-level already; nesting Pl reads as 3 levels.

### 9.3 ASCII Mockups (10 cases)

These are the canonical render targets. Each uses the cascade format (D-14) and the visibility rules above.

**Mockup 1 — Idle (active milestone, no live, no alerts):**

```
✳ Context Management
 <powerline>  ▓▓▓▓▓░░░░ 67% Restante

◎ GSD Status
 Version: v1.7 · M3/8 · Ph27  ▓▓▓░░░░░  ⇒ Next: Discuss
```

**Mockup 2 — Active: Discussing:**

```
◎ GSD Status
 Version: v1.7 · Now: ◔ Discussing M3/8 · Ph27  ▓▓▓░░░░░  ⇒ Next: Plan
```

**Mockup 3 — Active: Planning (no plans-in-execute yet):**

```
◎ GSD Status
 Version: v1.7 · Now: ◑ Planning M3/8 · Ph27  ▓▓▓░░░░░  ⇒ Next: Execute
```

**Mockup 4 — Active: Executing Wave 1 of 3, Plan 2 of 4 (FULL CASCADE):**

```
◎ GSD Status
 Version: v1.7 · Now: ▸ Executing (3/5) M3/8 · Ph27 · W1/3 · Pl2/4  ▓▓▓░░░░░  ⇒ Next: Verify
```

**Mockup 5 — Active: Verifying (post-execute, Pl/W drop):**

```
◎ GSD Status
 Version: v1.7 · Now: ✓ Verifying M3/8 · Ph27  ▓▓▓░░░░░  ⇒ Next: Ship
```

**Mockup 6 — Active: Quick (side channel, only M·Ph in cascade):**

```
◎ GSD Status
 Version: v1.7 · Now: ⚡ Quick: foo M3/8 · Ph27  ▓▓▓░░░░░
```

**Mockup 7 — Active + Alert overlay (cascade + ⚠):**

```
◎ GSD Status
 Version: v1.7 · Now: ▸ Executing M3/8 · Ph27 · W2/3 · Pl3/4  ▓▓▓░░░░░  ⇒ Next: Verify    ⚠ 30 uat · 1 todo
```

**Mockup 8 — Idle + Alert overlay (red glyph for blocker):**

```
◎ GSD Status
 Version: v1.7 · M3/8 · Ph27  ▓▓▓░░░░░  ⇒ Next: Discuss    ⚠ 1 blocker · 30 uat · 3 todo
```

**Mockup 9 — Archived + Quick (Phase 3 D-17):**

```
◎ GSD Status
 ⚡ Quick: foo
```

**Mockup 10 — Archived + Quick + Alerts (Phase 3 D-18):**

```
◎ GSD Status
 ⚡ Quick: foo    ⚠ 30 uat
```

### 9.4 What Color Means Where

The locked 7-color palette (PALETTE-01), with semantic meaning. The ship-gate test (`tests/v1-ship-gate.sh`) greps `38;5;[0-9]+` against this exact set.

| ANSI code | Color | Used for |
|-----------|-------|----------|
| `38;5;231` | Pure white (bold) | Block titles only (`✳ Context Management`, `◎ GSD Status`) — never used for status content |
| `38;5;252` | Light gray | Active / current values — version string, gerund label, cascade values |
| `38;5;240` | Dark gray | Structure — separator middots `·`, empty bar cells `░`, dotted track, parens around `(cur/tot)` |
| `38;5;141` | Purple | GSD progress bar fill `▓` + active step number inside `(cur/tot)` |
| `38;5;114` | Green | LIVE signal — current git branch, running subagents (bold), live stage gerund (bold). Also context gauge zone 1 (healthy). |
| `38;5;178` | Amber | Context gauge zone 2 (caution) + Alert row when only `uat`/`todo` present (no blocker) |
| `38;5;203` | Red | Context gauge zone 3 (nearly full) + Alert row when any blocker present + `% Restante` text when context red zone |

### 9.5 Producer Contracts (consumed by the bar)

The bar is a pure consumer of state files and labels. Producers must conform to these contracts:

- **`/tmp/gsd-cmd-<sid>`** — written by `hooks/track-gsd.sh` on every `/gsd-*` invocation. Schema: `<epoch> <token> <phase> <slug>` (4 positional fields). Slug is `-` when absent. TTL: 30 min. Cleared by `hooks/track-stop.sh` at turn end.
- **`/tmp/gsd-live-<sid>`** — written by `subagent-statusline.sh` on every subagent-panel refresh. Schema: `<epoch> <stage> <cur> <tot>`. TTL: 10 s (self-managed). NOT cleared by Stop hook.
- **`/tmp/gsd-wave-<sid>`** — written by `subagent-statusline.sh` when a running task label matches `^Wave (\d+)/(\d+):` (e.g. `"Wave 1/3: Execute plan 04-01 of phase 4"`). Schema: `<epoch> <wave_cur> <wave_tot>` (3 positional fields). TTL: 10 s. Cleared by `hooks/track-stop.sh` at turn end. **Producer contract for the `/gsd-execute-phase` orchestrator:** label executor subagents with `Wave N/M:` prefix to surface wave info in the bar. Without this prefix, the W segment simply doesn't render (Pl-only fallback).
- **`.planning/STATE.md`** — authoritative slow source. Bar reads frontmatter (`milestone`, `progress.percent`, `progress.completed_phases`, `progress.total_phases`) + body (`Phase: <n>`, `Plan: <n> of <m>`) + alert sections (`### Blockers`, `### TODOs`, "Deferred Items" rows with `N pending`). Cached via mtime in `/tmp/gsd-alerts-<sid>`.
