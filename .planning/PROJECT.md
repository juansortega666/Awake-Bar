# GSD Status Bar

## What This Is

GSD Status Bar is a Claude Code statusline system that reflects the real state of the GSD framework — what's running now, where the user is in the milestone, and what needs attention. It lives as a set of bash scripts (`statusline-gsd.sh` + `subagent-statusline.sh` + hooks `track-gsd.sh` / `track-stop.sh`) in `/Users/tresur/Documents/claude-tooling/`, wired through `~/.claude/settings.json`. It is consumed by every GSD project the user works in (currently TreSur Hope Lite at `/Users/tresur/Documents/TreSure-Hope-Lite/`), and renders two stacked blocks ("Context Management" + "GSD Status") above Claude Code's "accept edits" indicator.

## Core Value

**The bar must answer "Where am I in the milestone and what's left?" at a glance.**

Roadmap awareness is the priority. Live awareness (what's running this second) is secondary. If the bar is space-constrained, position-in-the-plan wins over live spinner. If everything else fails, the user must still know which phase they're on, how much of the milestone is done, and what comes next.

## Requirements

### Validated

(None yet — ship to validate)

### Active

<!-- v1 redesign hypotheses. All assume the existing bar already exists (368-line `statusline-gsd.sh`) and is being EXTENDED, not replaced from zero. -->

- [ ] **CORE-01**: Bar surfaces "where am I in the milestone" as the primary read — phase·plan position, milestone progress, next stage — visible at a glance even in idle mode
- [ ] **STAGE-01**: All 6 flavors of Verify (verify, code-review, ui-review, eval-review, validate, secure) render with the same `✓` glyph but distinct gerund labels (Verifying / Code-reviewing / UI-reviewing / Eval-reviewing / Validating / Securing) so the user can read what's running without learning a new symbol per flavor
- [ ] **STAGE-02**: All "happy-path" development commands of the framework are recognized live: `/gsd-discuss-phase`, `/gsd-plan-phase`, `/gsd-execute-phase`, `/gsd-verify-work`, `/gsd-code-review`, `/gsd-ui-review`, `/gsd-eval-review`, `/gsd-validate-phase`, `/gsd-secure-phase`, `/gsd-research-phase`, `/gsd-spec-phase`, `/gsd-ui-phase`, plus `/gsd-quick`, `/gsd-fast`, `/gsd-debug`, `/gsd-ship`, `/gsd-complete-milestone`
- [ ] **PLAN-01**: Plan progress within a phase is shown as a double counter `P27.2/4 · M3/8` (phase.plan-running / total-plans-in-phase · milestone-phase-done / total-phases) — text-based, no extra graphic
- [ ] **QUICK-01**: `/gsd-quick` and `/gsd-fast` work appear in the same GSD block (not a separate one) with dedicated glyphs (⚡ quick, » fast) and remain visible even when the milestone is archived between milestones — so quick/fast work between milestones is no longer invisible
- [ ] **ALERT-01**: Pending items render as a counter at the end of the GSD line: `⚠ 3 todo · 2 uat · 1 blocker` — zero counts hidden, severity color (amber for todo/uat, red for blocker)
- [ ] **MODE-01**: Bar has 3 adaptive modes — **Idle** (one line: milestone · position · next), **Active** (expands with gerund stage + spinner + cur/tot subagent counter), **Alert** (adds a row when blockers exist OR context usage > 70%)
- [ ] **PALETTE-01**: Bar keeps current palette — purple 141 (progress fill + active step), light gray 252 (active values), dark gray 240 (structure / dotted track), green 114 (live signal), amber 178 / red 203 (context gauge zones, alert severity). No new colors introduced in v1.
- [ ] **STATE-01**: Bar reads its data from `.planning/STATE.md` (phase, plan, percent, completed/total phases, milestone) PLUS the existing live signal files (`/tmp/gsd-cmd-<sid>`, `/tmp/gsd-live-<sid>`). New live signals MAY be added to surface stage flavors and quick/fast — but STATE.md remains the authoritative slow source.
- [ ] **HOOK-01**: The `track-gsd.sh` hook is rewritten to map all of STAGE-02's commands to distinct stage tokens (today it collapses to 5: Execute / Verify / Discuss / Roadmap / Plan)
- [ ] **PERF-01**: The redesigned bar must survive `refreshInterval: 1` (~60×/min). Any new STATE.md parsing or external command MUST be cached with a TTL of at least 4s (matching the powerline cache pattern).
- [ ] **COMPAT-01**: Bar continues to work on Claude Code's macOS TUI (256-color ANSI). No new runtime dependencies introduced (bash + jq + sed only in the main script; powerline remains the only `npx` call, already cached).

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
*Last updated: 2026-05-28 after initialization*
