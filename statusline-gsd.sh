#!/usr/bin/env bash
# Two titled, grayscale statusline blocks (title → content → gap):
#
#   ✳ Context Management      ← bold white title
#    <claude-powerline>        ← directory · V version · git / model · session · <ctx gauge>
#                              ← zero-width-space spacer
#   ◎ GSD Status              ← bold white title
#      <milestone row>            ← rail-aligned labeled rows (v1.2 redesign)
#      <phase row>
#      <stage row>                 ← glyph + gerund + ⇒ next (no label)
#                              ← trailing spacer (blank line above "accept edits")
#
# The GSD line is read from the current project's .planning/STATE.md. It shows from
# the moment a milestone is in progress and PERSISTS until /gsd-complete-milestone
# formally archives it (100% of phases is NOT completion); hidden after that archive
# and in any non-GSD directory (Context Management still shows). Running agents are
# restyled separately by subagent-statusline.sh (wired via the subagentStatusLine setting).
#
# Palette: white 231 (titles) · light gray 252 (active values) · dark gray 240
# (structure / dotted track) · purple 141 (GSD bar fill) · green 114 (live: current
# branch, running agents, live stage pulse) · context gauge green 114 / amber 178 / red 203.

set -uo pipefail

input="$(cat)"

# Directory this script lives in — used to locate sibling config (claude-powerline.json)
# so the whole bar repo is relocatable: no hardcoded ~/.claude path. Works because
# Claude Code invokes us as `bash <abs-path>/statusline-gsd.sh`, so BASH_SOURCE[0] is
# that absolute path.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ---- palette (semantic, ANSI 256) ----
# RULE:
#   W   (white) ....... TITLES ONLY — label + icon, never any status feedback
#   LG  (light gray) .. active / current values (version, current process, total step)
#   DG  (dark gray) ... quiet structure (labels, separators, dotted empty track)
#   PUR (purple) ...... GSD progress-bar fill + active step number
#   green #87d787 ..... LIVE feedback — powerline (current branch) + subagent panel
#                       (running agents) + the active GSD stage's per-second pulse.
#                       Context gauge fill: green 114/amber/red.
R=$'\033[0m'; B=$'\033[1m'
W=$'\033[38;5;231m'    # pure white — titles only
LG=$'\033[38;5;252m'   # light gray (closest to white) — active values
DG=$'\033[38;5;240m'   # dark gray  (farthest from white) — structure / dotted track
PUR=$'\033[38;5;141m'  # purple — GSD progress-bar fill + active step
GRNc=$'\033[38;5;114m'   # green 114 — branch healthy + context-gauge zone 1
YELc=$'\033[38;5;178m'   # ámbar 178 — branch warning + counters + zone 2
REDc=$'\033[38;5;203m'   # rojo 203  — branch danger + zone 3
# v1.2 title colors (extend PALETTE-01 with two title-only hues):
ORG=$'\033[38;5;173m'  # Anthropic-brand orange (#d7875f) — Context Management title
BLU=$'\033[38;5;117m'  # GSD-brand blue (#87d7ff)        — GSD Status title
# v1.2 GSD-block redesign (quick-260613-hlq T1): red-orange for /gsd-debug ⌖ glyph.
# Brand-hue convention follows YELc/GRNc for Quick/Fast — glyph-only, never used
# for labels or values. PALETTE lock now 10 colors (38;5;209 added in tests/v1-ship-gate.sh).
ORG_DBG=$'\033[38;5;209m'  # red-orange — /gsd-debug glyph

# Block title: bold + per-block color (label + icon). No status feedback.
# Takes optional 2nd arg = SGR color (default white).
title() { printf '%s%s%s%s\n' "$B" "${2:-$W}" "$1" "$R"; }
# U+200B (zero-width space) spacer line — survives Claude Code's blank-line trim,
# producing a real vertical gap between blocks.
SP=$'\xe2\x80\x8b'

# ---- session id + clock (computed once; reused by the powerline cache, the live-
# signal freshness checks, the spinner glyph, and the colour pulse) ----
session_id="$(printf '%s' "$input" | jq -r '.session_id // "default"' 2>/dev/null)"
now_epoch="$(date +%s)"

# ---- cwd resolution (shared by version walk below + GSD project walk later) ----
cwd="$(printf '%s' "$input" | jq -r '.workspace.current_dir // .cwd // .workspace.project_dir // empty' 2>/dev/null)"
[ -z "$cwd" ] && cwd="$PWD"

# ---- project version (read package.json with 4s cache, PERF-01) ----
# Walks up from cwd looking for the nearest package.json. Rendered as "V<pkgver>"
# spliced between directory and git segments in the powerline (Context Management
# block). Independent of GSD STATE.md walk so the version still shows in non-GSD
# directories. Empty when no package.json found upward — splice below is skipped.
pkgver=""
_d="$cwd"
while [ "$_d" != "/" ] && [ -n "$_d" ]; do
  if [ -f "$_d/package.json" ]; then
    pkgcache="/tmp/gsd-pkgver-${session_id}"
    if [ -f "$pkgcache" ]; then
      pkmtime="$(stat -f %m "$pkgcache" 2>/dev/null || stat -c %Y "$pkgcache" 2>/dev/null)"
      [ -n "$pkmtime" ] && [ "$(( now_epoch - pkmtime ))" -le 4 ] && pkgver="$(cat "$pkgcache")"
    fi
    if [ -z "$pkgver" ]; then
      pkgver="$(jq -r '.version // empty' "$_d/package.json" 2>/dev/null)"
      [ -n "$pkgver" ] && printf '%s' "$pkgver" > "$pkgcache" 2>/dev/null || true
    fi
    break
  fi
  _d="$(dirname "$_d")"
done
unset _d

# ---- git_with_timeout: portable 2s timeout wrapper (CONTEXT.md item 5) ----
# CONTEXT.md Silent fallback policy locked: "Use `timeout 2 <cmd>` wrapper for
# all new git commands." Default macOS does not ship GNU `timeout` (would break
# COMPAT-01), so we implement the same semantics with background pid +
# watchdog. Returns the wrapped command's exit code, or 137 (SIGKILL) when the
# watchdog killed it. All stderr suppressed.
#
# IMPORTANT (v1.1 polish — cold-start fix): the watchdog subshell MUST have its
# stdin/stdout/stderr redirected to /dev/null. Without this, the watchdog
# inherits the file descriptors of the calling context. When this function is
# called inside command substitution (`bc="$(git_with_timeout git ...)"`), the
# `$(...)` capture-pipe stays open as long as any process holds a reference to
# it — INCLUDING the backgrounded watchdog. Result: the command substitution
# blocks for the FULL 2s `sleep` of every watchdog, even though the wrapped git
# command finished in milliseconds. Detaching the watchdog's fds lets `$(...)`
# return as soon as the foreground wait completes.
#
# Usage: git_with_timeout git -C "$cwd" rev-list --count HEAD..@{u}
git_with_timeout() {
  local pid watchdog result
  ( "$@" 2>/dev/null ) &
  pid=$!
  # Detach watchdog fds — prevents $() command substitution from blocking on its stdout.
  ( sleep 2; kill -9 "$pid" 2>/dev/null ) </dev/null >/dev/null 2>&1 &
  watchdog=$!
  # `disown` removes the watchdog from the shell's job table, so when we kill
  # it later bash won't print "Terminated: 15" to stderr. Disown is the bash
  # way to fully detach a background job from job-control notifications.
  disown "$watchdog" 2>/dev/null || true
  wait "$pid" 2>/dev/null
  result=$?
  kill "$watchdog" 2>/dev/null || true
  # No `wait $watchdog` — with fds detached + disowned, no blocker, no notify.
  return "$result"
}

# ---- git state detection (6 states, 4s hot cache + 60s stale fallback) ----
# Reads behind-count, conflict, detached HEAD, no-upstream+ahead, rebasing, merging
# in one cached pass. All git commands routed through git_with_timeout (CONTEXT.md
# Silent fallback policy item 5). Cache layout:
#   /tmp/gsd-git-<session_id>: behind:N conflict:0|1 detached:SHA|"" no_upstream:0|1 rebasing:0|1 merging:0|1
# Cache TTL semantics (CONTEXT.md Silent fallback policy items 4-5):
#   age ≤ 4s            → hot cache, return immediately (no git calls)
#   age > 4s, fresh ok  → re-query, refresh cache
#   age > 4s, query fail, age ≤ 60s → reuse stale values (do NOT blank)
#   age > 60s, query fail OR no cache → return zero-state defaults
# Populates 6 globals: gs_behind gs_conflict gs_detached gs_no_upstream gs_rebasing gs_merging
gs_behind=0; gs_conflict=0; gs_detached=""; gs_no_upstream=0; gs_rebasing=0; gs_merging=0

# Parse a cache line into the 6 gs_* globals. Defensive — bad cache won't crash.
_load_git_cache() {
  local line="$1"
  gs_behind="${line#*behind:}"; gs_behind="${gs_behind%% *}"
  gs_conflict="${line#*conflict:}"; gs_conflict="${gs_conflict%% *}"
  gs_detached="${line#*detached:}"; gs_detached="${gs_detached%% *}"
  gs_no_upstream="${line#*no_upstream:}"; gs_no_upstream="${gs_no_upstream%% *}"
  gs_rebasing="${line#*rebasing:}"; gs_rebasing="${gs_rebasing%% *}"
  gs_merging="${line#*merging:}"; gs_merging="${gs_merging%% *}"
  gs_behind="${gs_behind//[^0-9]/}"; [ -z "$gs_behind" ] && gs_behind=0
  gs_conflict="${gs_conflict//[^01]/}"; [ -z "$gs_conflict" ] && gs_conflict=0
  gs_no_upstream="${gs_no_upstream//[^01]/}"; [ -z "$gs_no_upstream" ] && gs_no_upstream=0
  gs_rebasing="${gs_rebasing//[^01]/}"; [ -z "$gs_rebasing" ] && gs_rebasing=0
  gs_merging="${gs_merging//[^01]/}"; [ -z "$gs_merging" ] && gs_merging=0
}

# Try a fresh query. Returns 0 on success (gs_* populated), non-zero on failure.
# Sets the 6 globals from real git state. Locates .git from $cwd.
_query_git_state() {
  local gd="" _gd="$cwd"
  while [ "$_gd" != "/" ] && [ -n "$_gd" ]; do
    if [ -d "$_gd/.git" ] || [ -f "$_gd/.git" ]; then gd="$_gd/.git"; break; fi
    _gd="$(dirname "$_gd")"
  done
  if [ -z "$gd" ]; then
    # Not a git repo — zero-state is a successful "query"
    gs_behind=0; gs_conflict=0; gs_detached=""; gs_no_upstream=0; gs_rebasing=0; gs_merging=0
    return 0
  fi

  # Resolve worktree pointer file (.git as file, not dir)
  if [ -f "$gd" ]; then
    local gdptr
    gdptr="$(sed -n 's/^gitdir: //p' "$gd" 2>/dev/null)"
    [ -n "$gdptr" ] && gd="$gdptr"
  fi

  # Access check: if .git is a directory but unreadable (e.g. chmod 000), all
  # subsequent git calls would silently fail and yield false-zero state. Detect
  # this here and signal query failure so Branch 3 (stale-cache <=60s) can reuse
  # the prior value instead of clobbering it. `ls` of the dir is the cheapest
  # portable readability probe (test -r is unreliable on some filesystems).
  if [ -d "$gd" ] && ! ls "$gd" >/dev/null 2>&1; then
    return 1
  fi

  # Reset accumulators
  gs_behind=0; gs_conflict=0; gs_detached=""; gs_no_upstream=0; gs_rebasing=0; gs_merging=0

  # State 1: detached HEAD — symbolic-ref HEAD non-zero exit = detached
  if ! git_with_timeout git -C "$cwd" symbolic-ref --quiet HEAD >/dev/null; then
    gs_detached="$(git_with_timeout git -C "$cwd" rev-parse --short=7 HEAD 2>/dev/null || true)"
  fi

  # State 2: no-upstream (ahead>0 gate happens at render time in Plan 02)
  if ! git_with_timeout git -C "$cwd" rev-parse --abbrev-ref --symbolic-full-name '@{u}' >/dev/null; then
    gs_no_upstream=1
  fi

  # State 3: behind count (HEAD..@{u}). Only meaningful with upstream + attached HEAD.
  if [ "$gs_no_upstream" = "0" ] && [ -z "$gs_detached" ]; then
    local bc
    bc="$(git_with_timeout git -C "$cwd" rev-list --count 'HEAD..@{u}' 2>/dev/null || echo 0)"
    bc="${bc//[^0-9]/}"; [ -z "$bc" ] && bc=0
    gs_behind="$bc"
  fi

  # State 4 & 5: rebasing — .git/rebase-merge/ OR .git/rebase-apply/
  if [ -d "${gd}/rebase-merge" ] || [ -d "${gd}/rebase-apply" ]; then
    gs_rebasing=1
  fi

  # State 6: merging vs conflict — both check MERGE_HEAD; conflict if unmerged files exist
  if [ -f "${gd}/MERGE_HEAD" ]; then
    local unmerged
    unmerged="$(git_with_timeout git -C "$cwd" diff --name-only --diff-filter=U 2>/dev/null | head -1)"
    if [ -n "$unmerged" ]; then
      gs_conflict=1
    else
      gs_merging=1
    fi
  fi

  return 0
}

# Write current gs_* values to the cache file. Silent on failure.
_write_git_cache() {
  local cache="$1"
  printf 'behind:%s conflict:%s detached:%s no_upstream:%s rebasing:%s merging:%s' \
    "$gs_behind" "$gs_conflict" "$gs_detached" "$gs_no_upstream" "$gs_rebasing" "$gs_merging" \
    > "$cache" 2>/dev/null || true
}

# Main entry: hot cache → fresh query → stale-cache-≤60s fallback → zero-state defaults.
read_git_state() {
  local cache="/tmp/gsd-git-${session_id}"
  local age=999999
  local cmtime
  if [ -f "$cache" ]; then
    cmtime="$(stat -f %m "$cache" 2>/dev/null || stat -c %Y "$cache" 2>/dev/null)"
    [ -n "$cmtime" ] && age=$(( now_epoch - cmtime ))
  fi

  # Branch 1: hot cache (≤4s) — skip git entirely
  if [ "$age" -le 4 ]; then
    local line
    line="$(cat "$cache" 2>/dev/null)" && _load_git_cache "$line"
    return 0
  fi

  # Branch 2: fresh query (with 2s per-call timeout). On success, refresh cache.
  if _query_git_state; then
    _write_git_cache "$cache"
    return 0
  fi

  # Branch 3: query failed — use stale cache up to 60s old (CONTEXT.md item 4)
  if [ -f "$cache" ] && [ "$age" -le 60 ]; then
    local line
    line="$(cat "$cache" 2>/dev/null)" && _load_git_cache "$line"
    return 0
  fi

  # Branch 4: no usable cache, query failed → zero-state defaults already set
  # by the top-level declarations. Leave them; do not crash.
  return 0
}

# Call once on every render
read_git_state

# ---- 20-char truncation helper (LAYOUT-02) ----
# Bash 3.2-safe substring truncation with U+2026 ellipsis (3-byte UTF-8).
# Returns the input unchanged when ≤20 chars; otherwise first 19 chars + …
# Final string is ≤20 visible chars total INCLUDING the ellipsis
# (i.e. 19 visible chars + 1 ellipsis glyph = 20). ANSI codes are NOT counted
# because this helper operates on raw text BEFORE any ANSI splice.
# Used to truncate branch names and dir basenames before they hit the bar
# render. Model name is NEVER truncated (info-critical).
truncate20() {
  local s="$1"
  if [ "${#s}" -gt 20 ]; then
    printf '%s…' "${s:0:19}"
  else
    printf '%s' "$s"
  fi
}

# ---- 30-char truncation helper (TRUNC-30) ----
# Identical shape to truncate20 but with a 30/29 threshold. Used by the v1.2
# GSD-block redesign (emit_gsd_block) to clip milestone_name + phase_name before
# rendering — the locked design caps both at 30 visible chars + … (see
# .planning/notes/v1.2-gsd-block-redesign-MINIMAL.md §Truncation).
truncate30() {
  local s="$1"
  if [ "${#s}" -gt 30 ]; then
    printf '%s…' "${s:0:29}"
  else
    printf '%s' "$s"
  fi
}

# ---- 3-zone color helper (COLOR-02 enabler — single source of truth for thresholds) ----
# Returns the SGR escape sequence appropriate for a 0-100 USED percentage,
# using the canonical 3-zone thresholds locked by CONTEXT.md:
#   0-33  → light gray  (LG, 252)         — base text color, "healthy"
#   34-66 → ámbar       (YELc, 178)       — caution
#   67+   → bold rojo   (B + REDc, 203)   — danger
#
# Both gauges (Memory + Current session) call this helper with their respective
# USED percentages so the two metrics share identical zone semantics
# (CONTEXT.md C-06: "Single mental model — same color = same urgency").
#
# Defensive on non-numeric input: empty / non-digit pct collapses to 0 → light gray.
# bash 3.2 safe — pure parameter expansion + integer arithmetic, no associative arrays.
zone_color() {
  local pct="${1:-0}"
  # Strip anything non-digit, fall back to 0 if empty.
  pct="${pct//[^0-9]/}"
  [ -z "$pct" ] && pct=0
  if [ "$pct" -ge 67 ]; then
    printf '%s%s' "$B" "$REDc"
  elif [ "$pct" -ge 34 ]; then
    printf '%s' "$YELc"
  else
    printf '%s' "$LG"
  fi
}

# ---- line 1: existing powerline, stdin forwarded untouched ----
# The powerline call spawns node via npx — too heavy to run on every render once
# refreshInterval:1 is enabled (it would fire ~60×/min). Cache its RAW output per
# session for a few seconds: the dir·git·model·session segments change slowly, while
# the cheap bash below (context gauge + the GSD line's spinner/pulse) still recomputes
# every render so the animation stays smooth. TTL 4s keeps git/model reasonably fresh.
plcache="/tmp/gsd-powerline-${session_id}"
line1=""
if [ -f "$plcache" ]; then
  pmtime="$(stat -f %m "$plcache" 2>/dev/null || stat -c %Y "$plcache" 2>/dev/null)"
  [ -n "$pmtime" ] && [ "$(( now_epoch - pmtime ))" -le 4 ] && line1="$(cat "$plcache")"
fi
if [ -z "$line1" ]; then
  line1="$(printf '%s' "$input" \
    | npx -y @owloops/claude-powerline@latest --config="$SCRIPT_DIR/claude-powerline.json" 2>/dev/null)"
  printf '%s' "$line1" > "$plcache" 2>/dev/null || true
fi

# ---- splice "V <pkgver>" between directory and git segments (SPLICE-01) ----
# claude-powerline doesn't support custom segments (only its predefined set: directory,
# git, model, session, context, agent, today, weekly, block). The version we want to
# surface is the PROJECT's package.json semver — so we splice it ourselves AFTER the
# powerline call but BEFORE the separator transform on the next block.
#
# v1.2 SPLICE-01 fix: the splice still requires a triple-bg-reset downstream
# (the awk walks forward from the basename to find one). The dir-basename
# pre-anchor was added to make the splice unambiguous when the dir SGR opener
# doesn't match the old sed pattern — without it, mid-dir prefix matches could
# splice into the wrong column. If powerline ever drops the triple entirely,
# the splice no-ops gracefully (V<pkgver> just doesn't render).
# Idempotency guard: skip if V<pkgver> is already present — the awk would
# otherwise inject a second V if re-run on already-spliced input.
esc=$'\033'
if [ -n "$pkgver" ] && ! printf '%s' "$line1" | grep -q "V${pkgver}"; then
  dir_base="$(basename "$cwd")"
  if [ -n "$dir_base" ]; then
    # Splice " <triple> V<pkgver>" right BEFORE the existing dir/git triple-bg-reset boundary.
    # Strategy:
    #   - Find the first occurrence of $dir_base in $line1
    #   - Walk forward to the FIRST triple-bg-reset marker after it (the existing dir|git boundary)
    #   - Insert "<our-triple> V<pkgver>" BEFORE the existing triple
    # Final layout: `<dir> <our-triple> V<pkgver> <existing-triple> <git>`. The downstream
    # separator transform converts each triple into `·`, yielding:
    #   `<dir> · V<pkgver> · <git>`
    # If we only added ONE triple (either before or after V), V would glue against dir
    # or against git. If we added two (ours + kept the original) without subtracting the
    # one already present, we'd get `· ·` doubled separators. Net: one triple in $ver,
    # placed BEFORE the existing one.
    triple="${esc}[49m${esc}[49m${esc}[49m"
    line1="$(printf '%s' "$line1" | awk -v base="$dir_base" -v triple="$triple" -v ver="${triple} ${LG}V${pkgver}${R} " '
      !done {
        p = index($0, base)
        if (p > 0) {
          rest = substr($0, p + length(base))
          t = index(rest, triple)
          if (t > 0) {
            # Insert ver RIGHT BEFORE the existing triple-bg-reset. The existing
            # triple stays in place (becomes the V|git separator). Our injected
            # triple at the head of $ver becomes the dir|V separator.
            abs_t = p + length(base) + t - 1
            printf "%s%s%s\n", substr($0, 1, abs_t - 1), ver, substr($0, abs_t)
            done = 1
            next
          }
        }
      }
      { print }
    ')"
  fi
fi

# ---- Block + Weekly segments — extract data, build $blockseg / $weeklyseg vars ----
# Powerline emits `◱ N% (Xh Ym)` (5-hour, block) and `◑ N% (Xd Yh)` (7-day, weekly,
# Max only) on physical line 2 of $line1. We extract pct + reset into bash vars used
# by the emit_context_block reflow below. Each segment is glyph-anchored so the
# patterns stay disjoint; when a segment is absent its var stays empty and its row
# is omitted at emit time (ROBUST-02 silent-fallback).

# Normalize powerline's raw countdown payload (string inside the parens) to
# one of: "Nd Mh" / "Nd" / "Nh" / "Nm". Single sed pass with branch-on-match.
# Floors `Nh Mm` to `Nh` (drop the minutes); falls back to `0m` for "0h".
_normalize_reset() {
  printf '%s' "$1" | sed -nE '
    s/^[[:space:]]+//
    s/[[:space:]]+$//
    s/^([0-9]+d)[[:space:]]+0+h$/\1/
    t out
    s/^([0-9]+d)[[:space:]]+([0-9]+h).*/\1 \2/
    t out
    s/^([0-9]+d).*/\1/
    t out
    s/^0+h[[:space:]]+([0-9]+m).*/\1/
    t out
    s/^0+h$/0m/
    t out
    s/^([0-9]+h).*/\1/
    t out
    s/^([0-9]+m).*/\1/
    :out
    p
  '
}

# --- Weekly segment extraction (anchored on ◑) ---
# Pattern: ◑ <pct>% (<reset_raw>) where reset_raw can be "4d 3h" / "12h 30m" / "47m".
weekly_pct=""
weekly_reset=""
weekly_match="$(printf '%s' "$line1" | sed -nE 's/.*◑[[:space:]]*([0-9]+)%[[:space:]]*\(([^)]+)\).*/\1|\2/p' | head -1)"
if [ -n "$weekly_match" ]; then
  weekly_pct="${weekly_match%%|*}"
  weekly_reset="$(_normalize_reset "${weekly_match#*|}")"
fi

# --- Block segment extraction (anchored on ◱) ---
# Pattern: ◱ <pct>% (<reset_raw>) where reset_raw is "Xh Ym" / "Xh" / "Ym".
block_pct=""
block_reset=""
block_match="$(printf '%s' "$line1" | sed -nE 's/.*◱[[:space:]]*([0-9]+)%[[:space:]]*\(([^)]+)\).*/\1|\2/p' | head -1)"
if [ -n "$block_match" ]; then
  block_pct="${block_match%%|*}"
  block_reset="$(_normalize_reset "${block_match#*|}")"
fi

# --- Build $blockseg variable (G2-03: no `§` glyph, no `used` label between pct and ↻) ---
# Spec: `<pct>% used ↻ <reset>` — N% colored by zone_color, the rest in light gray.
# We wrap `↻` in its OWN LG SGR (separate from the trailing `used` SGR) so the
# C-07 invariant "countdown stays LG regardless of zone" is enforceable via the
# pattern `\e[38;5;252m↻` (used by ship-gate P6.2b and L10).
blockseg=""
[ -n "$block_pct" ] && \
  blockseg="$(zone_color "$block_pct")${block_pct}%${R} ${LG}used${R} ${LG}↻ ${block_reset}${R}"

# --- Build $weeklyseg variable (G2-04: no `⊞` glyph) ---
# Spec: `<pct>% used ↻ <reset>` — N% colored by zone_color (F2-06), reset in LG (F2-07).
# Same SGR-around-`↻` discipline as blockseg above.
weeklyseg=""
[ -n "$weekly_pct" ] && \
  weeklyseg="$(zone_color "$weekly_pct")${weekly_pct}%${R} ${LG}used${R} ${LG}↻ ${weekly_reset}${R}"
# ---- end Block + Weekly segment extraction ----

# ---- Model text extraction (G2-02: drop `✱` leading glyph, F2-01: full model string) ----
# Physical line 2 of $line1 is the model+block+weekly line. We need to extract just
# the model text with its color SGR intact, but strip the `✱ ` prefix and any trailing
# block/weekly segments. Strategy:
#   1. Grab physical line 2 as a string
#   2. Trim everything from the first segment glyph (◱ or ◑) onward
#   3. Strip the `✱ ` prefix (powerline's native model icon — G2-02 drops it)
# Result: $model_text contains just the model name with its color SGR ready to render
# at column 4 of the reflow. Examples:
#   "✱ Claude" → "Claude"
#   "✱ Opus 4.7 (1M context)" → "Opus 4.7 (1M context)"
# When powerline truncates the model badge (rare — only at very narrow widths) the
# string still renders verbatim. F2-01: NO ad-hoc truncation here (model is info-critical).
# All four transforms in one sed: grab line 2, trim from first ◱/◑ segment
# boundary onward, drop the `✱ ` glyph (G2-02), strip trailing whitespace.
model_text="$(printf '%s' "$line1" | sed -nE '2{ s/[◱◑].*$//; s/✱ //; s/[[:space:]]*$//; p; }')"

# claude-powerline's "minimal" style has no separator option, so splice a dark-gray
# "·" between segments. Boundaries are marked by a TRIPLE bg-reset (\e[49m ×3); the
# first segment and the line-end use a single \e[49m, so spaces inside a value like
# "Opus 4.7 (1M context)" stay untouched. $esc was declared in the version-splice
# block above. v1.2 changed separator from `-` to `·` per layout spec (DISCUSS §1).
# ---- 20-char dir-basename truncation (LAYOUT-02) ----
# The directory is the first plain-text run in line1, ending at the first
# segment boundary. Powerline emits "\e[<...>m\e[49m\e[<color>m DIR \e[0m\e[49m\e[49m\e[49m..."
# so the dir text appears between an opening `\e[<color>m` SGR and the next `\e`.
# Extract by skipping all leading ANSI escape sequences and the opening dir-color
# SGR (which contains digits — the prior regex `[^A-Za-z0-9_]*` skip was halted
# by those digits, causing it to only capture "0m"), then capture chars up to the
# next `\e`. The explicit anchor on `\e\[[^m]*m ` (any SGR followed by space)
# is the most robust way to land at the dir's leading space.
# IMPORTANT: must run BEFORE the separator transform below — that transform
# inserts a `-\e[49m\e[49m\e[49m` boundary marker which would shadow our
# extraction anchor on subsequent boundaries.
raw_dir="$(printf '%s' "$line1" | sed -n "s|.*${esc}\[38[^m]*m \([A-Za-z0-9._/-][A-Za-z0-9._ /-]*[A-Za-z0-9._/-]\) ${esc}.*|\1|p" | head -1)"
if [ -n "$raw_dir" ] && [ "${#raw_dir}" -gt 20 ]; then
  trunc_dir="$(truncate20 "$raw_dir")"
  # Use | as delimiter — paths can contain slashes.
  line1="$(printf '%s' "$line1" | sed "s|${raw_dir}|${trunc_dir}|")"
fi

line1="$(printf '%s' "$line1" | sed "s/${esc}\[49m${esc}\[49m${esc}\[49m/${DG}·${R}${esc}[49m${esc}[49m${esc}[49m/g")"

# ---- State-aware branch color (COLOR-01) ----
# Determines the branch color from the gs_* flags populated by read_git_state.
# Priority is danger > warning > healthy. NOTE: ROBUST-01 says we do NOT drop
# flags — all trailing flags still render — but the BRANCH itself can only be
# one color, so we pick danger when any danger flag is set.
#
# Detect ahead>0 by scanning $line1 for the powerline-emitted ↑ glyph inside
# the git segment. The pattern `↑[0-9]` is unambiguous — only the git ahead
# counter uses ↑ followed by a digit anywhere in the bar.
branch_ahead=0
case "$line1" in *↑[0-9]*) branch_ahead=1 ;; esac

# Color decision (PALETTE-01 only):
#   danger  → rojo 203 bold  (gs_conflict OR gs_detached non-empty)
#   warning → ámbar 178 bold (gs_rebasing OR gs_merging OR (gs_no_upstream AND ahead>0))
#   healthy → green 114 bold (default — current v1.0 behavior, palette-compliant)
branch_color="$GRNc"  # default = green 114 (already 38;5;114) — hoisted to top palette
if [ "$gs_conflict" = "1" ] || [ -n "$gs_detached" ]; then
  branch_color="$REDc"  # rojo 203
elif [ "$gs_rebasing" = "1" ] || [ "$gs_merging" = "1" ]; then
  branch_color="$YELc"  # ámbar 178
elif [ "$gs_no_upstream" = "1" ] && [ "$branch_ahead" = "1" ]; then
  branch_color="$YELc"  # ámbar 178
fi

# Swap powerline's native truecolor (38;2;135;215;135) for our palette color.
# Stripping the truecolor open code and inserting our 256-color code preserves
# the segment's trailing \e[0m reset, so existing bold splice logic still works.
# When branch_color = $GRNc, this still replaces the truecolor open with the
# 256-color green 114 — visually nearly identical, palette-compliant, and the
# downstream ship-gate (expected_palette in tests/v1-ship-gate.sh) stays happy
# because 38;2;... is not in the 7-color set anyway.
line1="$(printf '%s' "$line1" | sed "s/${esc}\[38;2;135;215;135m/${branch_color}/g")"

# Now apply bold (REPLACES the v1.0 line 148 behavior, but anchored on our PALETTE color).
# We bold AFTER our color swap so the bold SGR follows whatever color we picked.
# The branch segment's trailing \e[0m (powerline-emitted) resets bold + color.
# No `/g` flag — bold only the FIRST occurrence (the branch token open). Without this,
# if our PALETTE color appeared elsewhere (e.g. ámbar gauge cells below) we'd bold
# those too — which we don't want.
# IMPORTANT: $branch_color contains "\e[<N>m" — the `[` would be interpreted by sed
# as a bracket-expression open, breaking the regex. Escape it for the pattern side.
branch_color_re="$(printf '%s' "$branch_color" | sed 's/\[/\\[/g')"
line1="$(printf '%s' "$line1" | sed "s/${branch_color_re}/&${esc}[1m/")"

# ---- Branch-token replacement for transition states (GIT-03/05/06) ----
# When detached/rebasing/merging fires, the branch token AND its counters are
# replaced. The replacement text inherits the state color set above.
# Precedence among the three replacement states (only one can fire — they are
# mutually exclusive in real git states):
#   detached > rebasing > merging
# Match pattern: from "⎇ " up to (but not including) "\e[0m" or counters (↑/↓/●).
# The powerline emits "⎇ <name>" followed by either " ↑N", " ↓N", " ●", or "\e[0m".
# We replace the whole run.
if [ -n "$gs_detached" ]; then
  # Replace "⎇ <anything until \e[0m or ↑/↓/●>" with "detached <sha>"
  line1="$(printf '%s' "$line1" | sed "s/⎇ [^${esc}↑↓●]*/detached ${gs_detached} /")"
elif [ "$gs_rebasing" = "1" ]; then
  line1="$(printf '%s' "$line1" | sed "s/⎇ [^${esc}↑↓●]*/rebasing /")"
elif [ "$gs_merging" = "1" ] && [ "$gs_conflict" = "0" ]; then
  line1="$(printf '%s' "$line1" | sed "s/⎇ [^${esc}↑↓●]*/merging /")"
fi

# ---- 20-char branch-name truncation (LAYOUT-02, normal-branch case only) ----
# When the branch name (the token after "⎇ ") exceeds 20 chars, truncate to
# 19 + U+2026. Skip when a transition-state replacement above is active —
# those replacements (`detached <sha>` ≤16, `rebasing` 8, `merging` 7) are
# already under 20.
if [ -z "$gs_detached" ] && [ "$gs_rebasing" != "1" ] && [ "$gs_merging" != "1" ]; then
  # Extract the branch name from $line1 (between "⎇ " and the next " " or symbol)
  raw_branch="$(printf '%s' "$line1" | sed -n 's/.*⎇ \([^ ↑↓●'"$esc"']*\).*/\1/p' | head -1)"
  if [ -n "$raw_branch" ] && [ "${#raw_branch}" -gt 20 ]; then
    trunc_branch="$(truncate20 "$raw_branch")"
    # Use | as delimiter — branch names can contain slashes (feat/foo, fix/bar).
    line1="$(printf '%s' "$line1" | sed "s|⎇ ${raw_branch}|⎇ ${trunc_branch}|")"
  fi
fi

# ---- Trailing-flag accumulation (GIT-01, GIT-04, ROBUST-01) ----
# Splices ↓N + conflict + no-remote into the git segment, BEFORE its closing
# \e[0m, in deterministic order (ROBUST-01: no precedence, all applicable
# flags shown). Skipped entirely for transition states (detached/rebasing/
# merging) which don't carry these counters.
#
# Order built here matches CONTEXT.md "Display rules":
#   <branch-pos> ↑N ↓N ● conflict no-remote
# ↑N comes from powerline natively. ↓N is spliced after it when present,
# OR directly after the branch token when ↑N is absent (behind-only case).
# Dirty ● is native too. "conflict" and "no-remote" tail-append.
if [ -z "$gs_detached" ] && [ "$gs_rebasing" != "1" ] && [ "$gs_merging" != "1" ]; then
  # Build the ↓N segment (only when behind>0). Color: ámbar 178 (counters
  # convention per CONTEXT.md C-03). The trailing space matches powerline's
  # spacing convention. After the count, restore the branch color+bold so the
  # rest of the segment (dirty marker, anything before \e[0m) stays styled.
  behind_seg=""
  if [ "$gs_behind" -gt 0 ] 2>/dev/null; then
    behind_seg="${YELc}↓${gs_behind}${R}${branch_color}${B} "
  fi

  # Build the conflict + no-remote tail. These appear AFTER ● (which is part
  # of the powerline-native segment). To inject them BEFORE the segment's
  # closing \e[0m, we splice just before that reset. Order is locked by the
  # build sequence: conflict first, then no-remote.
  tail_seg=""
  if [ "$gs_conflict" = "1" ]; then
    tail_seg="${tail_seg} ${REDc}${B}conflict${R}"
  fi
  if [ "$gs_no_upstream" = "1" ] && [ "$branch_ahead" = "1" ]; then
    tail_seg="${tail_seg} ${YELc}no-remote${R}"
  fi

  if [ -n "$behind_seg" ] || [ -n "$tail_seg" ]; then
    # --- ↓N insertion ---
    # Path A (ahead+behind common case): splice ↓N immediately after the
    # powerline-native ↑N digit run. Uses sed because `↑N ` is a stable
    # pattern with a digit run + trailing space.
    if [ -n "$behind_seg" ]; then
      ahead_pre="$line1"
      line1="$(printf '%s' "$line1" | sed "s/↑\([0-9][0-9]*\) /↑\1 ${behind_seg}/")"

      # Path B (behind-only fallback): if Path A's splice did NOT fire (no
      # `↑N ` anchor — common when branch is freshly checked out and upstream
      # advanced), insert ↓N directly after the `⎇ <branch>` token. Detect
      # "splice did not fire" by string-equality of line1 pre/post Path A.
      if [ "$line1" = "$ahead_pre" ]; then
        # behind-only: inject ↓N right after the ⎇-token (first ⎇ <name> run).
        line1="$(printf '%s' "$line1" | awk -v behind="$behind_seg" -v esc="$esc" '
          !done && match($0, "⎇ [^ ↑↓●" esc "]+") {
            t = substr($0, RSTART, RLENGTH)
            printf "%s%s %s%s\n", substr($0, 1, RSTART - 1), t, behind, substr($0, RSTART + RLENGTH)
            done = 1
            next
          }
          { print }
        ')"
      fi
    fi

    # --- conflict + no-remote tail-splice ---
    # tail_seg goes before the git segment's CLOSING boundary — the
    # powerline-emitted "\e[0m\e[49m" pattern that marks "end of styled
    # segment + bg-reset". We anchor on this 2-code pair (not a bare \e[0m)
    # because Path A's behind_seg above contains a mid-segment \e[0m when
    # restoring branch_color after ↓N — a bare-\e[0m search would splice
    # tail_seg BEFORE the powerline-native ● dirty marker.
    #
    # Powerline emits the closing as: "\e[0m\e[49m" (segment fg-reset + bg-reset).
    # This pair appears exactly ONCE per segment, at its true end. We further
    # gate on the line containing branch_color to avoid splicing into line 2/3.
    if [ -n "$tail_seg" ]; then
      line1="$(printf '%s' "$line1" | awk -v marker="$branch_color" -v segend="${esc}[0m${esc}[49m" -v tail="$tail_seg" '
        !done && index($0, marker) {
          # Powerline emits the segment close as "\e[0m\e[49m" (fg-reset + bg-reset).
          # Anchor on this 2-code pair rather than a bare \e[0m because Path A
          # above emits a mid-segment \e[0m when restoring branch_color after ↓N
          # — a bare-\e[0m search would splice tail_seg BEFORE the powerline-
          # native ● dirty marker.
          # Strategy: find branch_color marker, then find the next "segend" AFTER it.
          # NOTE: "close" is a reserved name in awk (close() function), so we use "segend".
          m = index($0, marker)
          rest = substr($0, m + length(marker))
          c = index(rest, segend)
          if (c > 0) {
            abs_c = m + length(marker) + c - 1
            printf "%s%s%s\n", substr($0, 1, abs_c - 1), tail, substr($0, abs_c)
            done = 1
            next
          }
        }
        { print }
      ')"
    fi
  fi
fi

# ---- context-usage gauge (replaces powerline's context segment) ----
# 9-cell gauge that fills with the context window's used_percentage. Filled cells
# (▓) take their zone colour — cells 1-3 green, 4-6 amber, 7-9 red — so only the
# reached zones light up; empty cells (░) are a dark-gray dotted track. Green =
# plenty of room, red = nearly full.
ctxpct="$(printf '%s' "$input" | jq -r '.context_window.used_percentage // 0' 2>/dev/null)"
ctxpct="${ctxpct%%.*}"; ctxpct="${ctxpct//[^0-9]/}"; [ -z "$ctxpct" ] && ctxpct=0
ccells=9
cfill=$(( (ctxpct * ccells + 50) / 100 ))
[ "$cfill" -gt "$ccells" ] && cfill=$ccells
[ "$cfill" -lt 0 ] && cfill=0
# GRNc/YELc/REDc hoisted to top palette block (~line 45) so the branch-coloring
# block at ~line 138 can reference them under `set -uo pipefail` without
# unbound-variable crashes. Same variable names — context-gauge below uses them.
# Filled cell = its zone colour (only the reached zones light up). Empty cell =
# dark-gray dotted texture (░) — the inactive zones stay gray, no colour shown.
ctxbar=""; ci=1
while [ "$ci" -le "$ccells" ]; do
  if [ "$ci" -le "$cfill" ]; then
    if   [ "$ci" -le 3 ]; then ctxbar="${ctxbar}${GRNc}▓"
    elif [ "$ci" -le 6 ]; then ctxbar="${ctxbar}${YELc}▓"
    else                       ctxbar="${ctxbar}${REDc}▓"; fi
  else
    ctxbar="${ctxbar}${DG}░"
  fi
  ci=$((ci + 1))
done
ctxbar="${ctxbar}${R}"
# Color the gauge number using the canonical 3-zone helper (COLOR-02 — single
# source of truth, shared with Plan 06-02's Current session % rendering).
# Drives off ctxpct (USED percentage) — same input as the gauge bar fill.
# Intentional shift from v1.0's `cfill >= 7` (~72%) inline heuristic to the
# canonical 67% threshold locked by CONTEXT.md C-06 (no drift between gauges).
numcol="$(zone_color "$ctxpct")"
# Build $ctxseg as a standalone variable (no splice into $line1). v1.2 reflow uses
# it directly at the emit point: row 3 = blockseg + ctxseg (or ctxseg alone when
# block absent). Separator changed from `-` to `·` per L5 spec; gauge bar then `%`,
# NO `used` label adjacent (L6).
# ctxseg has two forms:
#   ctxseg_full     = " · ▓░░░ N%"  → appended to blockseg with leading separator
#   ctxseg_standalone = "▓░░░ N%"   → row 3 standalone when block absent
ctxseg_full="${DG}·${R} ${ctxbar} ${numcol}${ctxpct}%${R}"
ctxseg_standalone="${ctxbar} ${numcol}${ctxpct}%${R}"

# ---- Context Management 4-line reflow emitter (v1.2) ----
# Emits: title + 3 (or 4) indented content rows. Each row is prefixed with a reset
# SGR + 3 literal spaces (Claude Code trims leading literal whitespace, but a space
# that follows an SGR survives — same pattern the legacy GSD row uses for its
# 1-space indent at the bottom of this script).
#
# Row layout (per v1.2 DISCUSS §1 + L2-01..L2-05):
#   Row 1: full model string (e.g. "Opus 4.7 (1M context)") — F2-01
#   Row 2: <dir> · V<pkgver> · ⎇ <branch> <git-flags>     — physical line 1 of $line1
#   Row 3: <block%> used ↻ Nh · ▓░░░ <ctx%>               — blockseg + ctxseg (or ctxseg alone)
#   Row 4: <weekly%> used ↻ Nd Nh                          — weeklyseg, omitted if empty
#
# Silent-fallback contract: when blockseg is empty (non-Pro / no rate_limits data),
# row 3 = ctxseg alone. When weeklyseg is empty (Pro plan / no seven_day data),
# row 4 is omitted entirely. The Memory gauge (ctxseg) is always rendered.
#
# T2 (quick-260613-hlq, v1.2 GSD-block redesign): _row + nbsp + indent hoisted to
# module scope so the new emit_gsd_block emitter can reuse the SAME rail primitive
# (single source of truth — the rail glyph + indent shape must stay identical
# across both blocks for the visual "one coherent system" property to hold).
nbsp=$'\xc2\xa0'
indent=" ${R}${nbsp}"
# Per-row prefix: `│` (DG) at col 0 + ASCII space + reset SGR + NBSP + LG.
# The reset→LG state change around the NBSP is what keeps it from being
# collapsed by Claude Code's whitespace renderer. Content lands at col 3.
_row() { printf '%s%s│%s%s%s\n' "$R" "$DG" "$indent" "$LG" "$1"; }
emit_context_block() {
  title "✳ Context Management" "$ORG"
  # Strip powerline's embedded leading space so all rows align at the same column.
  local model_clean line_a strip="s/^((${esc}\[[0-9;]*m)+) /\\1/"
  model_clean="$(printf '%s' "$model_text" | sed -E "$strip")"
  line_a="$(printf '%s' "$line1" | sed -nE "1{ $strip; p; }")"
  _row "$model_clean"
  _row "$line_a"
  if [ -n "$blockseg" ]; then
    _row "$blockseg $ctxseg_full"
  else
    _row "$ctxseg_standalone"
  fi
  [ -n "$weeklyseg" ] && _row "$weeklyseg"
}

# ---- locate the GSD project root (walk up from Claude's cwd) ----
# $cwd already resolved above (used by the version walk).
state=""
dir="$cwd"
while [ "$dir" != "/" ] && [ -n "$dir" ]; do
  if [ -f "$dir/.planning/STATE.md" ]; then state="$dir/.planning/STATE.md"; break; fi
  dir="$(dirname "$dir")"
done

# Not a GSD project → Context Management block only (4-line indented reflow).
# emit_context_block (defined above) renders title + 3 or 4 content rows.
if [ -z "$state" ]; then
  emit_context_block
  printf '%s' "$SP"
  exit 0
fi

# ---- parse STATE.md ----
fm()     { grep -m1 -E "^$1:"   "$state" | sed -E "s/^$1:[[:space:]]*//;   s/[[:space:]]*\$//; s/^\"//; s/\"\$//"; }
fmnest() { grep -m1 -E "^  $1:" "$state" | sed -E "s/^  $1:[[:space:]]*//; s/[[:space:]]*\$//"; }

# ---- STATE.md alert helpers (D-09..D-12) ----
# Echo the lines under "### <h>" up to (but not including) the next ##/### heading.
fmsection() {
  local h="$1" s="$2"
  awk -v h="### $h" '
    $0 == h        { inside=1; next }
    inside && /^##/{ exit }
    inside         { print }
  ' "$s" 2>/dev/null
}

# Count non-empty bullet lines ("- ..." or "* ...") under "### <h>".
# "None." and blank lines do NOT count. (D-12)
count_alert_bullets() {
  fmsection "$1" "$2" | grep -cE '^[[:space:]]*[-*][[:space:]]+' 2>/dev/null
}

# Sum the explicit integers before "pending" in the Deferred Items section. (D-10)
# Accepts both "### Deferred Items" and "## Deferred Items".
count_deferred_pending() {
  local s="$1"
  awk '
    /^##+[[:space:]]+Deferred Items/ { inside=1; next }
    inside && /^##/                  { exit }
    inside {
      # find every "<int> pending" occurrence on this line
      while (match($0, /[0-9]+[[:space:]]+pending/)) {
        n = substr($0, RSTART, RLENGTH)
        sub(/[[:space:]]+pending/, "", n)
        sum += n + 0
        $0 = substr($0, RSTART + RLENGTH)
      }
    }
    END { print sum + 0 }
  ' "$s" 2>/dev/null
}

# Public entrypoint. Echoes "<todo> <uat> <blocker>" with mtime cache (D-11).
# Safe on missing/malformed state — silently returns "0 0 0".
parse_alerts() {
  local s="$1"
  local cache="/tmp/gsd-alerts-${session_id}"
  if [ -z "$s" ] || [ ! -f "$s" ]; then
    printf '0 0 0\n'; return 0
  fi
  local smtime cmtime
  smtime="$(stat -f %m "$s" 2>/dev/null || stat -c %Y "$s" 2>/dev/null)"
  if [ -f "$cache" ]; then
    cmtime="$(stat -f %m "$cache" 2>/dev/null || stat -c %Y "$cache" 2>/dev/null)"
    if [ -n "$smtime" ] && [ -n "$cmtime" ] && [ "$cmtime" -ge "$smtime" ]; then
      cat "$cache" 2>/dev/null && return 0
    fi
  fi
  local todo uat blocker
  todo="$(count_alert_bullets "TODOs" "$s")"
  blocker="$(count_alert_bullets "Blockers" "$s")"
  uat="$(count_deferred_pending "$s")"
  todo="${todo:-0}"; uat="${uat:-0}"; blocker="${blocker:-0}"
  printf '%s %s %s\n' "$todo" "$uat" "$blocker" | tee "$cache" 2>/dev/null
}

milestone="$(fm milestone)"
# T1 (quick-260613-hlq, v1.2 GSD-block redesign): parse the human-readable
# milestone name from frontmatter. STATE.md schema since v1.1 includes
# `milestone_name:` (line 4 of project root). Falls back to $milestone (short id)
# when absent so older STATE.md schemas still render cleanly. Used by emit_gsd_block
# in T2 to render `Milestone: <milestone_name>` (NOT the short id).
milestone_name="$(fm milestone_name)"
[ -z "$milestone_name" ] && milestone_name="$milestone"
status="$(fm status)"
percent="$(fmnest percent)"
cdone="$(fmnest completed_phases)"
ctot="$(fmnest total_phases)"
# D-18: total_plans frontmatter is NO LONGER consumed by the counter (it pulled
# the milestone-wide total instead of plans-in-phase). The Pl segment now uses $pc
# (parsed from STATE.md body "Plan: N of M") in the cascade builder below.
# Variable kept defined for backward-compat / future non-counter consumers.
ptot="$(fmnest total_plans)"
ptot="${ptot//[^0-9]/}"; [ -z "$ptot" ] && ptot=0

phaseline="$(grep -m1 -E '^Phase:' "$state")"
planline="$(grep -m1 -E '^Plan:'  "$state")"
phasenum="$(printf '%s' "$phaseline" | sed -nE 's/^Phase:[^0-9]*([0-9]+(\.[0-9]+)?).*/\1/p')"
# T1 (quick-260613-hlq, v1.2 GSD-block redesign): parse the human-readable
# phase name from the body `Phase:` line. Pattern: `Phase: <num> — <name>` or
# `Phase: <num>: <name>` or `Phase: <num> - <name>`. Strip trailing status words
# (`COMPLETE`, `(in progress)`, `✓`, `**`) and surrounding whitespace. Empty when
# parse fails (T2 emit_gsd_block collapses to "Phase: Phase N/M" without name).
phasename="$(printf '%s' "$phaseline" | sed -nE 's/^Phase:[[:space:]]*[0-9]+(\.[0-9]+)?[[:space:]]*[—:\-][[:space:]]*(.*)$/\2/p' \
  | sed -E 's/[[:space:]]*\*+[[:space:]]*$//; s/[[:space:]]*✓[[:space:]]*$//; s/[[:space:]]*COMPLETE[[:space:]]*$//; s/[[:space:]]*\([^)]*\)[[:space:]]*$//; s/[[:space:]]*$//')"

# sanitize numerics
percent="${percent//[^0-9]/}"; cdone="${cdone//[^0-9]/}"; ctot="${ctot//[^0-9]/}"
[ -z "$milestone" ] && milestone="?"
[ -z "$percent" ] && percent=0
[ -z "$cdone" ] && cdone=0
[ -z "$ctot" ] && ctot=0

# $milestone (from STATE.md, e.g. "v1.8") drives planning lookups (archived check etc).
# Version display lives in Context Management now (V<pkgver> spliced into powerline
# above line ~110), so no $milestone_display variable is needed here anymore.

# ---- progress bar (8 cells) ----
cells=8
fill=$(( (percent * cells + 50) / 100 ))
[ "$fill" -gt "$cells" ] && fill=$cells
[ "$fill" -lt 0 ] && fill=0
barF=""; barE=""; i=0
while [ "$i" -lt "$fill" ];  do barF="${barF}▓"; i=$((i + 1)); done
while [ "$i" -lt "$cells" ]; do barE="${barE}░"; i=$((i + 1)); done

# ============================================================================
# Phase 4 D-01..D-05: BAR MODES — formal naming of the 3 adaptive states
# ============================================================================
# The bar has 3 modes. They are NOT mutually exclusive: Alert is ORTHOGONAL —
# it appends a row on top of Idle or Active.
#
#   Mode: Idle   — default fall-through. No live signal AND milestone active.
#                  (Pre-v1.2 cascade renderer — replaced by emit_gsd_block rows.)
#                  Entry: `$livestage` empty + `$done` -eq 0. See line ~621.
#
#   Mode: Active — EITHER live signal fresh: /tmp/gsd-cmd (30min TTL) OR
#                  /tmp/gsd-live (60s TTL). A /gsd-* command is running.
#                  (Pre-v1.2 single-line renderer — replaced by emit_gsd_block.)
#                  Entry: `$livestage` non-empty (any live token). See line ~280.
#
#   Mode: Alert  — ORTHOGONAL row. When parse_alerts reports any non-zero count,
#                  "    ⚠ <severity-ordered counts>" is appended to Idle OR Active.
#                  Base mode renders normally; Alert just adds the row.
#                  Entry: legacy alert-counter path — DROPPED in v1.2 (T2 quick-260613-hlq).
#
# Mode naming is English (D-04). No state machine / module constants — comments
# suffice (D-05 rejected adding variables that don't remove any code).
# Archived-milestone visibility (D-15..D-18 from Phase 3) is HANDLED separately
# in the `if [ "$done" -eq 1 ]` branch at line ~592 — no mode applies when the
# GSD block is hidden (D-05: when block is hidden, there is no mode).
# ============================================================================
# ---- live GSD signal (read BEFORE the finished-check) ----
# STATE.md lags while a GSD command runs (it only updates after). Two live signals
# reveal the true current stage AND, crucially, that GSD is ACTIVE even between
# milestones (e.g. /gsd-new-milestone running before STATE.md is rewritten — the old
# milestone is still archived, so the finished-check below would otherwise hide us):
#   /tmp/gsd-cmd-<session>  — set by the track-gsd.sh hook on a /gsd-<verb> command,
#                             cleared by the Stop hook at turn end (catches INLINE
#                             execution). Trusted up to 30 min as a safety net. Carries
#                             the phase arg.
#   /tmp/gsd-live-<session> — set by subagent-statusline.sh from running agents,
#                             trusted up to 60s. The subagentStatusLine hook fires
#                             on subagent state changes (not continuously), so during
#                             long executor runs the signal can age — 60s tolerates
#                             typical event gaps; if the run exceeds 60s with no
#                             activity, the bar falls back to Idle (correct).
#                             Also carries "<cur> <tot>" sub-step counts.
# (session_id + now_epoch are computed once at the top, before the powerline cache.)
livecol=""; livecoloff=""; livelabel=""; livestage=""; livephase=""; substep=""; livecmdslug=""

# T1 (quick-260613-hlq, v1.2 GSD-block redesign): hung-state threshold.
# When max(cts, lts) age exceeds HUNG_SECS, T2's emit_gsd_block swaps the rotating
# `◓` spinner for a STATIC `⚠` glyph + bold red 203 coloring to signal "live
# signal present, but no fresh heartbeat" (work is stalled). Threshold = 60s
# matches /tmp/gsd-live TTL exactly (locked design v1.2-gsd-block-redesign-MINIMAL.md
# §"Stage visual states": "Hung — last signal >60s ago").
HUNG_SECS=60

# Defensive top-level init — these are populated later but MAY be referenced
# by the finished-check (D-15 enhanced) before population. set -uo pipefail safety.
todo=0; uat=0; blocker=0
acol=""; aparts=""
# Phase 4 Task 1 (D-14): wave-segment vars are populated inside the cascade builder
# but defensive init mirrors the cts/cst/cph/csl pattern for set -uo pipefail safety.
wts=""; wcur=""; wtot=""
# T2 (quick-260613-hlq, v1.2 GSD-block redesign): cts/lts timestamps are read
# inside the `if [ -f "$cf" ]` / `if [ -f "$lf" ]` blocks below; defensive-init
# at module scope so emit_gsd_block's hung-detection arithmetic compare is safe
# under `set -uo pipefail` even when neither live file exists.
cts=""; lts=""

# Read the subagent-panel live file ONCE: "<epoch> <stage> <cur> <tot>" (60s fresh).
# <stage> is the fallback live stage; <cur>/<tot> drive the dynamic sub-step counter
# (Option A: cur = subagents started, tot = subagents spawned this command).
live_fresh=0; live_stage_f=""; live_cur=""; live_tot=""
lf="/tmp/gsd-live-${session_id}"
if [ -f "$lf" ]; then
  lts=""; lst=""; lcur=""; ltot=""
  read -r lts lst lcur ltot < "$lf" 2>/dev/null || true
  if [ -n "$lts" ] && [ "${lts//[^0-9]/}" = "$lts" ] && [ "$(( now_epoch - lts ))" -le 60 ]; then
    live_fresh=1; live_stage_f="$lst"
    live_cur="${lcur//[^0-9]/}"; live_tot="${ltot//[^0-9]/}"
  fi
fi

# Mode: Active — entry point. If either live signal is fresh, $livestage becomes
# non-empty below and triggers the Now: segment + spinner + (cur/tot) counter.
# Stage precedence: the /gsd-<verb> cmd record (track-gsd.sh, 30 min) wins — it
# carries the phase arg — then fall back to the subagent live stage (10s).
cf="/tmp/gsd-cmd-${session_id}"
if [ -f "$cf" ]; then
  cts=""; cst=""; cph=""; csl=""
  read -r cts cst cph csl < "$cf" 2>/dev/null || true
  if [ -n "$cts" ] && [ "${cts//[^0-9]/}" = "$cts" ] && [ -n "$cst" ] && [ "$(( now_epoch - cts ))" -le 1800 ]; then
    livestage="$cst"; livephase="$cph"
    # slug from the hook is "-" until subagent-statusline.sh promotes a real value (D-14).
    # Captured here for Phase 3 (QUICK-01) which will render "<glyph> Quick: <slug>".
    [ "$csl" != "-" ] && livecmdslug="$csl"
  fi
fi
[ -z "$livestage" ] && [ "$live_fresh" -eq 1 ] && [ -n "$live_stage_f" ] && livestage="$live_stage_f"

# ---- milestone finished? ----
# GSD is "active" from the first task until the milestone is FORMALLY completed by
# /gsd-complete-milestone — which archives it to .planning/milestones/<ms>-ROADMAP.md.
# Reaching 100% of phases (or a state helper prematurely writing status=milestone_
# complete) does NOT count: the bar must PERSIST until that archive command actually
# runs. A finished individual phase likewise keeps GSD active mid-milestone.
planning_dir="$(dirname "$state")"
done=0
if [ -n "$milestone" ] && [ "$milestone" != "?" ]; then
  for _ms in "$milestone" "v$milestone"; do
    if [ -f "$planning_dir/milestones/${_ms}-ROADMAP.md" ]; then done=1; break; fi
  done
fi

# T2 (quick-260613-hlq, v1.2 GSD-block redesign — DROP-ALERTS): the orthogonal
# alert-counter row is removed from the GSD path per locked design (locked design
# v1.2-gsd-block-redesign-MINIMAL.md §"Killed"). parse_alerts() the FUNCTION stays
# defined upstream (other future consumers may want it) — only the GSD-path
# consumption is removed. $todo/$uat/$blocker stay defensively-zeroed at top-level
# init (~line 936) so any leftover reference under `set -uo pipefail` is safe.
#
# DROP archived-hide branch (locked-design VISIBILITY-01): the bar is visible
# whenever .planning/STATE.md exists. Archived state now collapses to a single
# "Last shipped: <name>  ⇒  /gsd-new-milestone" row inside emit_gsd_block, not
# a hide. The block-hidden edge case is gone — solves PROJECT.md Now-Ambig #4.

# ---- GSD is active (milestone in progress) → build the GSD Status line ----
# Detect the current GSD stage, ordered along the GSD flow:
# Requirements → Roadmap → Discuss → Plan → Execute → Verify. Check the status
# field first (GSD's authoritative state), then the Phase line, so a phase NAME
# that happens to contain a keyword can't misread the stage.
glyph="·"; step=""; nextstep=""
for src in "$status" "$phaseline"; do
  [ -n "$step" ] && break
  case "$(printf '%s' "$src" | tr '[:upper:]' '[:lower:]')" in
    # "ready to ___" / past-participle TRANSITIONS: a stage just finished and the
    # named stage is NEXT — so "ready to execute" is Planned, NOT Executing.
    *"ready to execut"*|*"ready to run"*|*"plan ready"*|*planned*)
                                                glyph="○"; step="Planned";    nextstep="Execute" ;;
    *"ready to plan"*|*"roadmap ready"*|*"roadmap complete"*)
                                                glyph="○"; step="Roadmapped"; nextstep="Plan"    ;;
    *"ready to verif"*|*"ready to review"*|*executed*)
                                                glyph="○"; step="Executed";   nextstep="Verify"  ;;
    *"ready to ship"*|*verified*)
                                                glyph="○"; step="Verified";   nextstep="Ship"    ;;
    # active stages — infinitive verbs (match the GSD command names)
    *requirement*|*defining*)                   glyph="◔"; step="Define"   ;;
    *roadmap*)                                  glyph="◇"; step="Roadmap"  ;;
    *discuss*|*spec*)                           glyph="◔"; step="Discuss"  ;;
    *plan*)                                     glyph="◑"; step="Plan"     ;;
    *execut*|*"in progress"*|*wip*|*building*)  glyph="▸"; step="Execute"  ;;
    *verif*|*review*|*test*)                    glyph="✓"; step="Verify"   ;;
  esac
done

# All phases complete but the milestone is NOT yet archived (we got past the hide
# check, so done=0): show a clear "ready to close" state — phases done, next is the
# /gsd-complete-milestone (Ship) step — regardless of any premature status text.
if [ "$percent" -ge 100 ] || { [ "$ctot" -gt 0 ] && [ "$cdone" -ge "$ctot" ]; }; then
  glyph="○"; step="Done"; nextstep="Ship"
fi

# Live override application: a fresh live signal ($livestage) was detected above
# (BEFORE the finished-check), so a GSD command is running NOW. Show the stage in its
# GERUND form, with a rotating spinner glyph + steady LIVE-green label carrying the
# motion (see below), and a dynamic "(cur/tot)" counter of the command's internal
# agents glued after it. Resets Next to re-derive.
if [ -n "$livestage" ]; then
  step="$livestage"; nextstep=""
  case "$step" in
    # --- Meta-start (D-01) ---
    Roadmap)           glyph="◇"; livelabel="Roadmapping"        ;;
    # --- Pre-phase (D-02..D-05) ---
    Spec)              glyph="◔"; livelabel="Specifying"         ;;
    UIPhase)           glyph="◔"; livelabel="UI design"          ;;
    Discuss)           glyph="◔"; livelabel="Discussing"         ;;
    Research)          glyph="◎"; livelabel="Researching"        ;;
    # --- Impl (D-06, D-07) ---
    Plan)              glyph="◑"; livelabel="Planning"           ;;
    Execute)           glyph="▸"; livelabel="Executing"          ;;
    # --- Verify family — glyph ✓ LOCKED by STAGE-01 + D-19 (D-08..D-13) ---
    Verify)            glyph="✓"; livelabel="Verifying"          ;;
    CodeReview)        glyph="✓"; livelabel="Code-reviewing"     ;;
    UIReview)          glyph="✓"; livelabel="UI-reviewing"       ;;
    EvalReview)        glyph="✓"; livelabel="Eval-reviewing"     ;;
    Validate)          glyph="✓"; livelabel="Validating"         ;;
    Secure)            glyph="✓"; livelabel="Securing"           ;;
    # --- Meta-end (D-14, D-15) ---
    CompleteMilestone) glyph="↗"; livelabel="Closing milestone"  ;;
    Ship)              glyph="↗"; livelabel="Shipping"           ;;
    # --- Side channels (D-16, D-17, D-18) ---
    # Quick/Fast labels stay as nouns per PROJECT.md Key Decisions row 5;
    # Phase 3 (QUICK-01) will render "<glyph> Quick: <slug>" using $livecmdslug.
    Quick)             glyph="⚡"; livelabel="Quick"              ;;
    Fast)              glyph="»"; livelabel="Fast"               ;;
    # T2 (quick-260613-hlq, v1.2 GSD-block redesign): Debug glyph swapped
    # ◍ → ⌖. The ORG_DBG (209) brand color is applied inside emit_gsd_block
    # when building the side-channel row — case block stays glyph + label only.
    Debug)             glyph="⌖"; livelabel="Debugging"          ;;
    # --- Unknown non-empty token (D-22): render raw verbatim with neutral glyph ---
    # T2 (quick-260613-hlq) TODO: future-improvement fallback per locked design
    # §"Unknown stages" — render `Stage: <raw-token> ⇒ ?` instead of falling
    # through to the current state. Deferred to post-v1.2 — current behavior
    # (raw token rendered as livelabel) is preserved.
    *)                 glyph="·"; livelabel="$step"              ;;
  esac
  # D-06..D-09: Append ": <slug>" to Quick/Fast labels when subagent panel has
  # promoted the slug (livecmdslug non-empty). Pre-slug state (D-08): render the
  # bare noun unchanged ("⚡ Quick"). Same rules for Fast (D-09).
  # D-07: truncate slug to 20 chars + "…" (single-char ellipsis, U+2026).
  # NOTE: $livestage is the authoritative source for the active stage token here.
  # (Line ~354 sets `step="$livestage"`, so $step == $livestage at this point — but
  # we key off $livestage explicitly to avoid implicit dependency on the case block.)
  if [ "$livestage" = "Quick" ] || [ "$livestage" = "Fast" ]; then
    if [ -n "$livecmdslug" ]; then
      slugshown="$livecmdslug"
      if [ "${#slugshown}" -gt 20 ]; then
        slugshown="${slugshown:0:20}…"
      fi
      livelabel="${livelabel}: ${slugshown}"
    fi
  fi
  # Spinner: while live, the stage glyph rotates through 4 quadrant frames, one per
  # render — a "working now" signal. It advances only when the script re-runs, so it
  # needs refreshInterval:1 (settings.json) to keep spinning while the main session sits
  # idle waiting on subagents. 4 frames → a full turn every ~4s (snappier than 10).
  # Replaces the static stage glyph for the live duration.
  # B1: Side-channel stages (Quick / Fast) MUST keep their static ⚡ / » glyphs
  # per ROADMAP success criteria #2 + #3 — the spinner is reserved for "real work"
  # stages (Plan / Execute / Verify / etc.). Without this guard, the spinner block
  # below unconditionally overrides $glyph each render and the user sees ◐ ◓ ◑ ◒
  # instead of ⚡ / » for /gsd-quick and /gsd-fast invocations.
  if [ "$livestage" != "Quick" ] && [ "$livestage" != "Fast" ]; then
    spin=(◐ ◓ ◑ ◒)
    glyph="${spin[$(( now_epoch % ${#spin[@]} ))]}"
  fi
  # Live stage colour: steady bold green (114, the LIVE colour) — deliberately NOT a
  # blink. A 2-state colour blink can't beat a 2s cycle (refreshInterval floor is 1s),
  # which reads as sluggish; the spinner above carries the per-second motion instead.
  # livecoloff resets, then restores light gray for the rest of the Now: segment.
  livecol="${B}${GRNc}"
  livecoloff="${R}${LG}"
  # live phase number from the command args overrides the (stale) STATE.md phase
  [ -n "$livephase" ] && [ "${livephase//[^0-9.]/}" = "$livephase" ] && phasenum="$livephase"
  # Dynamic sub-step counter (Option A): "(cur/tot)" of the command's internal agents,
  # shown only while subagents are fresh (<=60s) and at least one is in the panel.
  # cur (started) bold purple; parens + "/" dark-gray structure; tot light gray.
  if [ -n "$live_tot" ] && [ "$live_fresh" -eq 1 ] && [ "$live_tot" -gt 0 ] 2>/dev/null; then
    [ -z "$live_cur" ] && live_cur=0
    substep=" ${DG}(${R}${B}${PUR}${live_cur}${R}${DG}/${R}${LG}${live_tot}${R}${DG})${R}"
  fi
fi

# D-19 regression: frontmatter `total_plans:` is milestone-wide, but the bar's
# Pl<cur>/<tot> denominator must be PHASE-LOCAL. Source of truth = body line
# "Plan: <cur> of <tot>" written by the executor. Without this fix, a phase with
# 2-3 plans in a milestone of 89 would render `Pl1/89` (wrong).
pc="$(printf '%s' "$planline" | sed -nE 's/.*[Pp]lan:[[:space:]]*([0-9]+)[[:space:]]+of[[:space:]]+([0-9]+).*/\1\/\2/p')"
pseg=""; [ -n "$pc" ] && pseg=" ${pc}"
prun="$(printf '%s' "$planline" | sed -nE 's/.*[Pp]lan:[[:space:]]*([0-9]+)[[:space:]]+of[[:space:]]+[0-9]+.*/\1/p')"
prun="${prun//[^0-9]/}"

# Plan-within-phase counter per PLAN-01 + Phase 4 D-14 (hierarchical cascade — OVERRIDES Phase 3 D-01):
#   New format: "M3/8 · Ph27 · W1/3 · Pl2/4"  (Milestone > Phase > Wave > Plan, top-down address)
#   Visibility per D-15:
#     - M (Milestone done/total)            → ALWAYS shown when milestone is active
#     - Ph (phase number)                   → shown for all stages EXCEPT Roadmap
#     - W (wave cur/tot)                    → shown ONLY during Execute (from /tmp/gsd-wave-<sid>, Task 3 plumbing)
#     - Pl (plan cur/tot from "Plan: N of M") → shown ONLY during Execute, AND only for non-decimal phases
#   Decimal phase (e.g. 72.1): Pl is dropped even during Execute (D-15 edge note).
#   D-18 bug fix: Pl denominator comes from $pc (parsed from "Plan: N of M"), NOT $ptot (frontmatter).
phaseplanseg=""
if [ -n "$milestone" ] && [ "$milestone" != "?" ] && [ "$ctot" -gt 0 ] 2>/dev/null; then
  cascade_parts=()
  # M segment — always shown when milestone is active
  cascade_parts+=( "M${cdone}/${ctot}" )

  # Ph segment — shown unless stage is Roadmap (D-15: Roadmapping row is M-only)
  if [ -n "$phasenum" ] && [ "$livestage" != "Roadmap" ]; then
    cascade_parts+=( "Ph${phasenum}" )
  fi

  # W and Pl segments — shown ONLY during Execute stage
  if [ "$livestage" = "Execute" ]; then
    # W segment from /tmp/gsd-wave-<sid> (Task 3 plumbing). 10s TTL like gsd-live.
    wf="/tmp/gsd-wave-${session_id}"
    if [ -f "$wf" ]; then
      wts=""; wcur=""; wtot=""
      read -r wts wcur wtot < "$wf" 2>/dev/null || true
      if [ -n "$wts" ] && [ "${wts//[^0-9]/}" = "$wts" ] && [ "$(( now_epoch - wts ))" -le 10 ]; then
        wcur="${wcur//[^0-9]/}"; wtot="${wtot//[^0-9]/}"
        if [ -n "$wcur" ] && [ -n "$wtot" ] && [ "$wtot" -gt 0 ] 2>/dev/null; then
          cascade_parts+=( "W${wcur}/${wtot}" )
        fi
      fi
    fi
    # Pl segment — D-18 fix: use $pc (from "Plan: N of M"), NOT $ptot (frontmatter).
    # Decimal phase edge (D-15): drop Pl for decimal phases (e.g. Ph72.1).
    if [ -n "$pc" ] && [[ "$phasenum" != *.* ]]; then
      cascade_parts+=( "Pl${pc}" )
    fi
  fi

  # Join with " · " (middot) using the DG separator color, with LG for the value text.
  # Build raw text first, then wrap once at consumption point.
  phaseplanseg=""
  for cp in "${cascade_parts[@]}"; do
    if [ -z "$phaseplanseg" ]; then
      phaseplanseg="${cp}"
    else
      phaseplanseg="${phaseplanseg} ${DG}·${R} ${LG}${cp}"
    fi
  done
fi
# NOTE: the legacy `pnum=""; [ -n "$phasenum" ] && pnum="P${phasenum} "` line
# is DELETED outright — the cascade above replaces all per-segment work.

# Detected stage, or fall back to the raw status text so it's never blank. While a
# GSD command is live, show the gerund label (set above) in steady LIVE green.
stage="${livelabel:-$step}"
[ -z "$stage" ] && stage="$(printf '%s' "$status" | cut -c1-24)"
[ -z "$stage" ] && stage="working"
# D-05: counter sits INSIDE Now: immediately after the stage label.
# Legacy pseg (sub-step "/<x>" from planline) is REMOVED — the new phaseplanseg covers it.
# Legacy pnum prefix is GONE — the counter no longer sits before the glyph.
now="${glyph} ${livecol}${stage}${livecoloff}${substep}"
[ -n "$phaseplanseg" ] && now="${now} ${LG}${phaseplanseg}${R}"

# D-04: old cdone/ctot counter REMOVED — phaseplanseg above carries M<done>/<total>.
# Keep variable defined as empty so the seg= line still references it without error.
counter=""

# Current: segment — always visible at start of GSD line (hybrid logic).
# Active mode: reuse $glyph (animated spinner) + $stage (gerund from livelabel)
#   + $substep ((cur/tot)). NOTE: do NOT reuse $now wholesale — $now also
#   includes $phaseplanseg (M·Ph·W·Pl), which lives separately after Version:.
# Idle mode: derive gerund from STATE.md $status field as a static label.
if [ -n "$livestage" ]; then
  currentseg="${DG}Now:${R} ${glyph} ${livecol}${stage}${livecoloff}${substep}"
else
  case "$status" in
    ready_to_plan|ready_to_execute|ready) current_label="Ready"      ;;
    planning|plan)                        current_label="Planning"   ;;
    executing|execute)                    current_label="Executing"  ;;
    verifying|verify)                     current_label="Verifying"  ;;
    verified)                             current_label="Verified"   ;;
    discussing|discuss)                   current_label="Discussing" ;;
    milestone_complete)                   current_label="Complete"   ;;
    milestone_ready)                      current_label="Closing"    ;;
    *)                                    current_label="${step:-Working}" ;;
  esac
  currentseg="${DG}Now:${R} ${LG}${current_label}${R}"
fi

# Upcoming GSD step — a transition state above may have set it, else derive
# it from the current stage. Hidden when there is nothing next. The arrow (⇒) into
# it is double-line, bold, lighter gray.
if [ -z "$nextstep" ]; then
  case "$step" in
    # --- Pre-phase chain ---
    Roadmap)           nextstep="Discuss" ;;
    Spec)              nextstep="Discuss" ;;
    UIPhase)           nextstep="Discuss" ;;
    Discuss)           nextstep="Plan"    ;;
    Research)          nextstep="Plan"    ;;
    # --- Impl ---
    Plan)              nextstep="Execute" ;;
    Execute)           nextstep="Verify"  ;;
    # --- Verify family: all 6 flavors map to Ship (terminal of milestone) ---
    # Per gsd-flow SKILL §3: Verify-family sub-stages share Verify's next-arrow.
    # We keep "Ship" (the existing default) as the conservative pick; Phase 4
    # may refine when adaptive composition lands.
    Verify)            nextstep="Ship"    ;;
    CodeReview)        nextstep="Ship"    ;;
    UIReview)          nextstep="Ship"    ;;
    EvalReview)        nextstep="Ship"    ;;
    Validate)          nextstep="Ship"    ;;
    Secure)            nextstep="Ship"    ;;
    # --- Meta-end: terminal stages have no next-stage arrow ---
    CompleteMilestone) nextstep=""        ;;
    Ship)              nextstep=""        ;;
    # --- Side channels: don't advance the milestone (gsd-flow SKILL §3) ---
    Quick)             nextstep=""        ;;
    Fast)              nextstep=""        ;;
    Debug)             nextstep=""        ;;
    # --- Legacy idle states (kept for backward-compat with the past-participle
    # case block at lines 317-339 which sets step="Define" via the "requirement"
    # pattern; D-23 forbids modifying that block, so we must still handle Define
    # here for the legacy code path) ---
    Define)            nextstep="Roadmap" ;;
    # --- Unknown / empty ---
    *)                 nextstep=""        ;;
  esac
fi
nextseg=""
# T2 (quick-260613-hlq, DROP-NEXT-LBL): the next-stage label token is REMOVED
# per locked design. The `⇒` arrow alone signals direction (two spaces of
# breathing room around it). The legacy nextseg is still built for
# backward-compat with any downstream consumer; emit_gsd_block ignores it and
# renders ⇒ inline.
[ -n "$nextstep" ] && nextseg=" ${B}${LG}⇒${R} ${LG}${nextstep}${R}"

# ---- emit_gsd_block — v1.2 GSD-block redesign (quick-260613-hlq T2) ----
# Replaces the legacy single `Now: <stuff>` line with a rail-aligned 3-row labeled
# layout that mirrors Context Management. State machine in priority order:
#   1. Mid-roadmapping       (livestage=Roadmap)         → 2 rows, no Phase
#   2. Last-shipped, archived (done=1 + no live)         → 1 row collapse
#   3. Ready-to-ship          (percent≥100, no live)     → 1 row collapse
#   4. Side-channel running   (Quick/Fast/Debug)         → 3 rows, Stage replaced
#   5. Transition / Normal mid-flow                       → 3 rows (Milestone/Phase/Stage)
#
# Locked design: .planning/notes/v1.2-gsd-block-redesign-MINIMAL.md
#
# Reads (all upstream-set): $milestone_name, $phasenum, $phasename, $cdone, $ctot,
# $livestage, $livelabel, $livecmdslug, $pc, $done, $percent, $step, $nextstep,
# $cts, $lts, $now_epoch, $HUNG_SECS, $glyph (current spinner/static), $current_label
# (idle gerund), $session_id.
emit_gsd_block() {
  title "◎ GSD Status" "$BLU"

  # Truncate names per locked design (TRUNC-30).
  local mname pname
  mname="$(truncate30 "$milestone_name")"
  pname="$(truncate30 "$phasename")"

  # ---- Hung detection (locked design §"Stage visual states") ----
  # Live signal is present iff $livestage non-empty. Hung when the freshest of
  # cts/lts is older than HUNG_SECS. When neither timestamp is numeric, treat
  # as "no recent heartbeat" → hung (defensive — a non-numeric stage token
  # means we shouldn't show a spinner that may be lying).
  local age_cts=99999 age_lts=99999 freshest_age=99999 is_hung=0
  if [ -n "$cts" ] && [ "${cts//[^0-9]/}" = "$cts" ]; then
    age_cts=$(( now_epoch - cts ))
    [ "$age_cts" -lt 0 ] && age_cts=99999
  fi
  if [ -n "$lts" ] && [ "${lts//[^0-9]/}" = "$lts" ]; then
    age_lts=$(( now_epoch - lts ))
    [ "$age_lts" -lt 0 ] && age_lts=99999
  fi
  if [ "$age_cts" -lt "$age_lts" ]; then freshest_age="$age_cts"; else freshest_age="$age_lts"; fi
  if [ -n "$livestage" ] && [ "$freshest_age" -gt "$HUNG_SECS" ]; then
    is_hung=1
  fi

  # ---- State 1: Mid-roadmapping ----
  # livestage=Roadmap → 2 rows: Milestone (creating…) + Stage. NO Phase row.
  if [ "$livestage" = "Roadmap" ]; then
    _row "${DG}Milestone:${R} ${LG}${mname}${R} ${DG}(creating…)${R}"
    # Stage row: Active treatment (rotating ◓ + green 114 bold).
    local stage_glyph stage_gerund
    if [ "$is_hung" -eq 1 ]; then
      stage_glyph="⚠"
      _row "${DG}Stage:${R} ${B}${REDc}${stage_glyph} Roadmapping${R}  ${B}${LG}⇒${R} ${LG}Discuss${R}"
    else
      stage_glyph="$glyph"  # already a spinner frame from the case block (override fired)
      _row "${DG}Stage:${R} ${B}${GRNc}${stage_glyph} Roadmapping${R}  ${B}${LG}⇒${R} ${LG}Discuss${R}"
    fi
    return 0
  fi

  # ---- State 2: Last-shipped, no new milestone ----
  # done=1 (archived ROADMAP exists) AND no fresh live signal → single-row collapse.
  if [ "$done" -eq 1 ] && [ -z "$livestage" ]; then
    _row "${DG}Last shipped:${R} ${LG}${mname}${R}  ${B}${LG}⇒${R} ${DG}/gsd-new-milestone${R}"
    return 0
  fi

  # ---- State 3: Ready-to-ship ----
  # percent ≥ 100 OR cdone ≥ ctot (all phases done) AND not yet archived AND no
  # fresh non-Roadmap live signal → single-row collapse.
  if { [ "$percent" -ge 100 ] 2>/dev/null || { [ "$ctot" -gt 0 ] 2>/dev/null && [ "$cdone" -ge "$ctot" ] 2>/dev/null; }; } \
     && [ "$done" -eq 0 ] && [ -z "$livestage" ]; then
    _row "${DG}Milestone:${R} ${LG}${mname}${R}  ${B}${LG}⇒${R} ${DG}/gsd-complete-milestone${R}"
    return 0
  fi

  # ---- States 4-6: 3-row layout (Milestone / Phase / Stage) ----
  # Row 1: Milestone
  _row "${DG}Milestone:${R} ${LG}${mname}${R}"

  # Row 2: Phase (with `Phase <cur>/<total>` counter — always shown).
  # When phasename empty (parse failed), collapse to "Phase: Phase N/M".
  local phase_counter=""
  if [ -n "$phasenum" ] && [ -n "$ctot" ] && [ "$ctot" != "0" ]; then
    phase_counter="Phase ${phasenum}/${ctot}"
  elif [ -n "$phasenum" ]; then
    phase_counter="Phase ${phasenum}"
  fi
  if [ -n "$pname" ] && [ -n "$phase_counter" ]; then
    _row "${DG}Phase:${R} ${LG}${pname}${R} ${DG}·${R} ${LG}${phase_counter}${R}"
  elif [ -n "$pname" ]; then
    _row "${DG}Phase:${R} ${LG}${pname}${R}"
  elif [ -n "$phase_counter" ]; then
    _row "${DG}Phase:${R} ${LG}${phase_counter}${R}"
  else
    _row "${DG}Phase:${R} ${LG}?${R}"
  fi

  # Row 3: Stage — branches on side-channel, hung, active, idle visual rules.

  # ---- State 4: Side-channel running (Quick / Fast / Debug) ----
  # Replaces the entire Stage row. Only the GLYPH carries the brand color;
  # labels and values follow normal labeled-row style (LG / DG).
  if [ "$livestage" = "Quick" ]; then
    if [ -n "$livecmdslug" ]; then
      _row "${YELc}⚡${R} ${DG}Quick:${R} ${LG}${livecmdslug}${R}"
    else
      _row "${YELc}⚡${R} ${LG}Quick${R}"
    fi
    return 0
  fi
  if [ "$livestage" = "Fast" ]; then
    _row "${GRNc}»${R} ${LG}Fast${R}"
    return 0
  fi
  if [ "$livestage" = "Debug" ]; then
    if [ -n "$livecmdslug" ]; then
      _row "${ORG_DBG}⌖${R} ${DG}Debug:${R} ${LG}${livecmdslug}${R}"
    else
      _row "${ORG_DBG}⌖${R} ${LG}Debug${R}"
    fi
    return 0
  fi

  # ---- States 5-6: Normal Stage row (Transition / Idle / Active / Hung) ----
  # Build Plan-counter suffix once (ONLY when livestage=Execute AND pc non-empty
  # AND phase NOT decimal — same gating as the legacy Pl cascade).
  local plan_suffix=""
  if [ "$livestage" = "Execute" ] && [ -n "$pc" ] && [[ "$phasenum" != *.* ]]; then
    plan_suffix=" ${DG}·${R} ${LG}Plan ${pc}${R}"
  fi

  # Build arrow + nextstep suffix (arrow alone, no label per DROP-NEXT-LBL).
  local next_suffix=""
  [ -n "$nextstep" ] && next_suffix="  ${B}${LG}⇒${R} ${LG}${nextstep}${R}"

  if [ -z "$livestage" ]; then
    # Idle visual state: no glyph, gerund from $current_label in LG.
    local idle_label="${current_label:-Working}"
    _row "${DG}Stage:${R} ${LG}${idle_label}${R}${plan_suffix}${next_suffix}"
  elif [ "$is_hung" -eq 1 ]; then
    # Hung visual state: STATIC ⚠ glyph + bold red 203 on glyph + gerund.
    _row "${DG}Stage:${R} ${B}${REDc}⚠ ${livelabel}${R}${plan_suffix}${next_suffix}"
  else
    # Active visual state: rotating spinner frame ($glyph already set by the
    # spinner override at ~line 1131) + bold green 114 on glyph + gerund.
    _row "${DG}Stage:${R} ${B}${GRNc}${glyph} ${livelabel}${R}${plan_suffix}${next_suffix}"
  fi
}

# ---- emit: two titled blocks separated by zero-width-space spacer rows ----
# Layout (title → content → gap):
#   ✳ Context Management
#      <model>                    ← 3-space indent (v1.2 reflow)
#      <dir · V · ⎇ branch>
#      <block% used ↻ Nh · ▓░░ ctx%>
#      <weekly% used ↻ Nd Nh>     ← row 4 omitted when weekly absent
#   <gap>
#   ◎ GSD Status
#      <milestone row>            ← rail-aligned, mirrors Context Management
#      <phase row>
#      <stage row>
#   <trailing gap>                ← blank line above the TUI's "accept edits" indicator
emit_context_block
printf '\n%s\n' "$SP"
emit_gsd_block
printf '%s' "$SP"
