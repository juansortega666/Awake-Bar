# GSD Status Bar

## What This Is

GSD Status Bar is a Claude Code statusline system that reflects the real state of the GSD framework — what's running now, where the user is in the milestone, and what needs attention. It lives as a set of bash scripts (`statusline-gsd.sh` + `subagent-statusline.sh` + hooks `track-gsd.sh` / `track-stop.sh`) in `/Users/tresur/Documents/claude-tooling/`, wired through `~/.claude/settings.json`. It is consumed by every GSD project the user works in (currently TreSur Hope Lite at `/Users/tresur/Documents/TreSure-Hope-Lite/`), and renders two stacked blocks ("Context Management" + "GSD Status") above Claude Code's "accept edits" indicator.

## Core Value

**The bar must answer "Where am I in the milestone and what's left?" at a glance.**

Roadmap awareness is the priority. Live awareness (what's running this second) is secondary. If the bar is space-constrained, position-in-the-plan wins over live spinner. If everything else fails, the user must still know which phase they're on, how much of the milestone is done, and what comes next.

## Current Milestone: v1.1 Context Management Refinements

**Goal:** Evolve the Context Management block to communicate git state, Claude.ai quota (Pro/Max), and conversation context using one unified 3-zone mental model (green/amber/red) and text labels (not glyphs) for rare states.

**Target features:**
- New git state indicators with text labels: `↓N` behind, `conflict`, `detached`, `no-remote`
- Current session usage + reset countdown via powerline `block` segment, compact format `§ N% used ↻ Nh`
- Unified 3-zone color rule applied to both Current session and Memory gauges
- Layout consolidation: 2 lines (drop empty agent line), English unification (`% used` not `Restante`), state-aware branch color
- Robustness: >20 char truncation, show-all-flags accumulation, silent fallback on data source failures

**Scope boundaries (explicit):**
- ✓ IN: Context Management block (first block of the bar)
- ✗ OUT: GSD Status block (second block, untouched in v1.1)
- ✗ OUT: Open-source readiness (license, README, contribution guide — deferred to v1.2+)
- ✗ OUT: Exotic command coverage (EXOT-01..04 moved to v1.2+ deferred)
- ✗ OUT: Aesthetic layer alternatives (AEST-01..02 moved to v1.2+ deferred)

**Source:** Full discussion spec lives in `.planning/notes/v1.1-context-management-DISCUSS.md` (300+ lines). REQUIREMENTS.md is derived from that spec; do not duplicate decisions here.

## Requirements

### Validated

<!-- All 12 v1 requirements validated 2026-05-31 across Phases 1-4. Ship-gate (tests/v1-ship-gate.sh) locks PERF + PALETTE + COMPAT. -->

- [x] **HOOK-01** (Phase 1) — `track-gsd.sh` rewritten to 17 PascalCase tokens + 4-positional schema
- [x] **STATE-01** (Phase 1) — STATE.md frontmatter parsing + 4-field cmd-signal + alert helper
- [x] **STAGE-01** (Phase 2) — All 6 Verify flavors render `✓` + distinct gerund labels
- [x] **STAGE-02** (Phase 2) — 18 happy-path commands recognized live (case block + Next: derivations)
- [x] **PLAN-01** (Phase 3) — Plan-within-phase counter `P27.2/4 · M3/8` (superseded by Phase 4 D-14 hierarchical cascade `M·Ph·W·Pl`)
- [x] **QUICK-01** (Phase 3) — Quick/Fast slug suffix + spinner guard + cross-milestone visibility
- [x] **ALERT-01** (Phase 3) — Inline alert counter with severity color (amber/red), zero counts hidden
- [x] **CORE-01** (Phase 4) — Roadmap awareness as primary read; M·Ph cascade visible in Idle
- [x] **MODE-01** (Phase 4) — 3 adaptive modes named (Idle / Active / Alert). *Descoped: context > 70% trigger moved to Context Management block per D-06.*
- [x] **PALETTE-01** (Phase 4) — 7-color authoritative set `{114, 141, 178, 203, 231, 240, 252}` locked by ship-gate (`231` added during Phase 3 finalization for block titles)
- [x] **PERF-01** (Phase 4) — Ship-gate verifies per-render median under 600ms noise-tolerant cap; 4s cache pattern preserved
- [x] **COMPAT-01** (Phase 4) — bash 3.2+ verified by ship-gate; no new runtime deps (bash + jq + sed only)

### Active

Active requirements live in `.planning/REQUIREMENTS.md` (formal v1.1 IDs). The discuss-doc at
`.planning/notes/v1.1-context-management-DISCUSS.md` is the authoritative spec for the v1.1 scope.

### Deferred to v1.2+

Surfaced during v1.0 close + v1.1 discuss, intentionally scoped OUT of v1.1.

**Now: ambiguity in GSD Status block** (user-raised at v1.0 close, 2026-06-01)
- `Now:` segment doesn't match framework reality across all states. Specifically: idle behavior shows STATE.md `status:` (last-completed action, not current intent), stale-live behavior keeps spinning during 60s+ gaps in subagent events, and unknown stages render raw without warnings. See ambiguity matrix in `statusline-gsd.sh:425-498`.
- Deferred to v1.2 because v1.1 scope is strictly Context Management block.

**Open-source readiness** (raised at v1.1 discuss, 2026-06-01)
- License selection, README, CONTRIBUTING.md, public repo setup
- Deferred because v1.1 is personal-use refinement; open-source is a separate concern requiring its own milestone

**Exotic command coverage**
- **EXOT-01**: Recognize `/gsd-autonomous` runs (autonomous-mode indicator)
- **EXOT-02**: Recognize `/gsd-workstreams` (active workstream)
- **EXOT-03**: Recognize `/gsd-new-workspace` (workspace vs main repo)
- **EXOT-04**: Recognize `/gsd-thread` (active thread)
- Deferred because user works single-flow on TreSur — no multi-stream / autonomous workflows today

**Aesthetic layer**
- **AEST-01**: Optional semantic color-per-stage (currently all stages share green-when-live)
- **AEST-02**: Alternative palette aligned with consumer project (e.g. TreSur indigo `#5B5FE6`)
- Deferred because v1.1 standardizes the unified 3-zone color rule first; palette variants come after

**Carry-forward fixes from v1.0**
- ROADMAP Phase 4 success criterion #5 (6→7 color palette wording) — cosmetic
- WR-02 bash 10+ regex future-proofing — cosmetic
- `phase.complete` SDK CLI overcount bug (M5/4 observed) — upstream framework issue
- Framework-side: `/gsd-execute-phase` orchestrator emit `Wave N/M:` Task labels — consumer plumbing dormant without it

### Out of Scope

<!-- Things explicitly NOT in v1. Each carries a reason so they're not re-added without revisiting. -->

- **Exotic GSD commands** (`/gsd-autonomous`, `/gsd-workstreams`, `/gsd-thread`, `/gsd-new-workspace`, `/gsd-ai-integration-phase`, `/gsd-spike`, `/gsd-sketch`, `/gsd-graphify`, `/gsd-set-profile`, `/gsd-settings`, `/gsd-help`, `/gsd-stats`, `/gsd-progress`, `/gsd-health`, `/gsd-forensics`) — user confirmed scope is "happy path of development commands" only; covering the long tail would require a 2× larger bar and more cognitive load per render
- **Aesthetic / palette redesign** — current palette is locked for v1 (PALETTE-01). Why: already optimized for terminals, familiar to the user, decouples logic from presentation. Can be revisited in a future milestone if needed.
- **Multi-workspace parallel cursors** — bar assumes one cursor per Claude Code session. Why: workspaces (`/gsd-new-workspace`) are themselves out of scope, and adding multi-cursor accounting compounds the live-signal complexity.
- **Velocity / duration / metrics display in the bar** — STATE.md captures velocity tables and Performance Metrics; those stay in STATE.md, not on the line. Why: they're pull-mode info ("how long did P22 take?"), not push-mode awareness.
- **Cross-IDE statusline** — only Claude Code's `statusLine` + `subagentStatusLine` are targeted. Why: each runtime (Codex, Gemini, OpenCode) has its own status mechanism; cross-IDE = different project.
- **Replacing the powerline (`@owloops/claude-powerline`)** — kept as the first-block engine. Why: it already handles dir·branch·model·session·context-gauge well; rewriting it = scope creep.

## Context

**Where this lives.** `/Users/tresur/Documents/claude-tooling/` is a small standalone git repo containing the live versions of `statusline-gsd.sh` (368 lines), `subagent-statusline.sh`, `hooks/track-gsd.sh`, `hooks/track-stop.sh`, and `claude-powerline.json`. The user's `~/.claude/settings.json` wires these via absolute paths:

```json
"statusLine": { "type": "command", "command": "bash /Users/tresur/Documents/claude-tooling/statusline-gsd.sh", "refreshInterval": 1 },
"subagentStatusLine": { "type": "command", "command": "bash /Users/tresur/Documents/claude-tooling/subagent-statusline.sh" },
"hooks": {
  "UserPromptExpansion": [{ "matcher": "gsd-", "hooks": [{ "type": "command", "command": "bash /Users/tresur/Documents/claude-tooling/hooks/track-gsd.sh", "timeout": 5 }] }],
  "Stop": [{ "hooks": [{ "type": "command", "command": "bash /Users/tresur/Documents/claude-tooling/hooks/track-stop.sh", "timeout": 5 }] }]
}
```

There is also a `~/.claude/statusline-gsd.sh` copy (and a `.bak-20260525-195015`) — those are legacy / backup; the live one is in `claude-tooling/`.

**How the bar gets its data today.**

1. **Slow source** — walks up from the session cwd to find `.planning/STATE.md` (= "this is a GSD project"). Reads frontmatter: `milestone`, `status`, `progress.percent`, `progress.completed_phases`, `progress.total_phases`. Reads `Phase:` and `Plan:` headers from the body. STATE.md only updates *after* a GSD command finishes, so it lags during inline command runs.
2. **Live signal — command** (`/tmp/gsd-cmd-<sid>`) — written by `track-gsd.sh` on every `/gsd-<verb>` invocation: `<epoch> <Stage> <phase>`. 30-min TTL. Catches inline execution. Cleared by `track-stop.sh` on turn end.
3. **Live signal — subagent** (`/tmp/gsd-live-<sid>`) — written by `subagent-statusline.sh` from the running-agents JSON: `<epoch> <stage> <cur> <tot>`. 10s TTL. Provides the `(cur/tot)` subagent counter.
4. **Powerline** — `npx -y @owloops/claude-powerline@latest` provides the first block (dir·branch·model·session). Output cached 4s per session. The script then splices in a context-usage gauge (9-cell, green/amber/red zones) at the end of powerline's session segment.

**Pre-analysis identified 4 concrete pain points the redesign must solve** (confirmed by user in questioning):

1. **Plan progress invisible** — STATE.md has `total_plans` / `completed_plans` but the bar only shows phases. A phase with 5 plans and 2 done doesn't move the bar at all.
2. **Verify/Review collapsed** — one "Verify" stage covers verify, code-review, ui-review, eval-review, validate (Nyquist), and secure. 6 flows in one bucket.
3. **Quick/fast invisible** — TreSur has 50+ completed quick tasks; none ever appeared in the bar while running. Two reasons: `track-gsd.sh` doesn't map quick/fast to any stage AND the entire GSD block is hidden when the milestone is archived (which is exactly when most quick tasks run).
4. **Blockers/TODOs/UAT pending ignored** — STATE.md has dedicated `### Blockers`, `### TODOs`, and "Deferred Items" sections with `human_needed` counts. The bar reads none of them.

**Existing GSD framework surface.** The user's `/Users/tresur/.claude/get-shit-done/` tooling exposes ~80 `/gsd-*` commands. The bar's `track-gsd.sh` recognizes only 5 stage buckets today (Execute / Verify / Discuss / Roadmap / Plan), collapsing many distinct flows into the same icon. The redesign explicitly targets the ~17 "development happy path" commands listed in STAGE-02, leaving the exotic long tail (autonomous, workstreams, threads, ai-integration, etc.) deliberately out of scope.

**The TreSur project as primary consumer.** TreSur (`v1.7 Color System` milestone, phase 27 in progress as of 2026-05-29) is the daily driver. Its STATE.md illustrates every condition the bar needs to handle: active phase + plan running, archived milestone + concurrent quick tasks, blockers section (currently None), human_needed verifications, KPI migration pending in deferred items. The bar should look right against TreSur's real STATE.md, not a synthetic one.

## Constraints

- **Tech stack — bash + jq + sed only in main script**: `statusline-gsd.sh` is invoked ~60×/min via `refreshInterval: 1`. Startup overhead matters. No node, no python in the main render path. — Why: cold-start cost of any other runtime would be visible as render lag.
- **Performance — anything expensive must cache with TTL**: powerline already caches 4s (`/tmp/gsd-powerline-<sid>`). New parsers (e.g. plan progress inside a phase) must follow the same pattern. — Why: 60×/min × per-render parsing = wasted CPU and slow renders.
- **Compatibility — ANSI 256-color, no truecolor required**: every color stays in the 256-color palette. Claude Code trims leading literal whitespace, so any indent must follow an ANSI code (current code uses `printf '%s %s\n' "$R" "$seg"` for the indent — the reset SGR carries the space through). — Why: portability across the user's tooling.
- **Aesthetic — palette locked for v1**: purple 141 / light gray 252 / dark gray 240 / green 114 / amber 178 / red 203. No new colors. — Why: already optimized and familiar; logic-first milestone.
- **Scope — only the statusline GSD block + hooks are target**: the powerline first block stays as-is; `claude-powerline.json` may be tuned but not rewritten. — Why: separation of concerns; rewriting powerline = different milestone.
- **Data sources — STATE.md is authoritative, /tmp is live overlay**: the bar must work from STATE.md alone (no /tmp signals) as the fallback when hooks haven't fired yet. /tmp signals are pure performance / freshness overlay. — Why: hooks may fail or be slow; STATE.md is always the source of truth.
- **Runtime detection — repo path is relocatable**: the live `statusline-gsd.sh` already uses `SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"` to find sibling config. Keep this. — Why: the script must work from any clone location without editing.
- **Backwards compatibility — existing STATE.md formats stay readable**: bar must continue to render correctly against current TreSur STATE.md and any older format already deployed. — Why: real consumers exist; no migration tax on users.

## Key Decisions

<!-- Decisions taken during questioning. These constrain v1 design choices. -->

| Decision | Rationale | Outcome |
|----------|-----------|---------|
| Core value = roadmap awareness (NOT live awareness) | User picked Q1 option 2: "Where are we in the milestone and what's left?" — this is the primary read; live state is secondary. Decides priority order when bar is space-constrained. | — Pending |
| Adaptive 3-mode bar (Idle · Active · Alert) | User picked Q2 option 1. Resolves the dense-vs-minimal conflict: minimal in idle, grows when something is happening, escalates when something needs attention. | — Pending |
| Verify flavors = same `✓` + distinct gerund label | User picked Q3 option 2. Minimizes symbol-memory load; user reads what's running without learning 6 new glyphs. Cost: label width varies, sometimes longer (e.g. "Code-reviewing"). | — Pending |
| Plan progress = text counter `P27.2/4 · M3/8` | User picked Q4 option 2. No extra graphic; phase.plan + total + milestone position. Simpler than nested progress bars. | — Pending |
| Quick/fast share the GSD block (not their own block) | User picked Q5 option 1. Single GSD area. Quick = ⚡ glyph + label `Quick: <slug>`; fast = » glyph. Block stays visible whenever any GSD activity exists, not just during milestones. | — Pending |
| Pending items = inline counter `⚠ N todo · N uat · N blocker` | User picked Q6 option 1. End of the GSD line. Zero counts hidden. Amber for todo/uat, red for blocker. No third block. | — Pending |
| Palette stays current (purple 141 / lg 252 / green 114 / amber/red) | User picked Q8 option 1. Familiar, optimized, lets v1 focus on logic. Aesthetic redesign deferred to a later milestone if needed. | — Pending |
| Project name = "GSD Status Bar" | User picked Q7 option 2. Specific to the artifact; future statusline-adjacent tooling can live alongside without renaming. | — Pending |
| Initialize GSD in `claude-tooling/` (not TreSur, not a workspace) | The bar is transversal to ALL GSD projects, so it deserves its own repo + planning. Workspaces add indirection without benefit here. | — Pending |

## Evolution

This document evolves at phase transitions and milestone boundaries.

**After each phase transition** (via `/gsd-transition`):
1. Requirements invalidated? → Move to Out of Scope with reason
2. Requirements validated? → Move to Validated with phase reference
3. New requirements emerged? → Add to Active
4. Decisions to log? → Add to Key Decisions
5. "What This Is" still accurate? → Update if drifted

**After each milestone** (via `/gsd-complete-milestone`):
1. Full review of all sections
2. Core Value check — still the right priority?
3. Audit Out of Scope — reasons still valid?
4. Update Context with current state

---
*Last updated: 2026-06-01 — v1.0 shipped + closed; v1.1 Context Management Refinements milestone started, discuss-doc captured in `.planning/notes/v1.1-context-management-DISCUSS.md`*
