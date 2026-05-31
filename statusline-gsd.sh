#!/usr/bin/env bash
# Two titled, grayscale statusline blocks (title → content → gap):
#
#   ✳ Context Management      ← bold white title
#    <claude-powerline>        ← directory·git  /  model·session·<context gauge>
#                              ← zero-width-space spacer
#   ◎ GSD Status              ← bold white title
#    Version: <v> · Now: <glyph> <stage> <plan>  <bar> <step/total> ⇒ Next: <stage>
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

# A block title: bold pure-white (label + icon), on its own line. No status feedback.
title() { printf '%s%s%s%s\n' "$B" "$W" "$1" "$R"; }
# U+200B (zero-width space) spacer line — survives Claude Code's blank-line trim,
# producing a real vertical gap between blocks.
SP=$'\xe2\x80\x8b'

# ---- session id + clock (computed once; reused by the powerline cache, the live-
# signal freshness checks, the spinner glyph, and the colour pulse) ----
session_id="$(printf '%s' "$input" | jq -r '.session_id // "default"' 2>/dev/null)"
now_epoch="$(date +%s)"

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

# claude-powerline's "minimal" style has no separator option, so splice a dark-gray
# "-" between segments. Boundaries are marked by a TRIPLE bg-reset (\e[49m ×3); the
# first segment and the line-end use a single \e[49m, so spaces inside a value like
# "Opus 4.7 (1M context)" stay untouched.
esc=$'\033'
line1="$(printf '%s' "$line1" | sed "s/${esc}\[49m${esc}\[49m${esc}\[49m/${DG}-${R}${esc}[49m${esc}[49m${esc}[49m/g")"

# Bold the active git branch. powerline renders the whole git segment in green
# truecolor (#87d787 = 38;2;135;215;135) and that exact green appears ONLY on the git
# segment here (directory/model/session are gray 208;208;208), so appending a bold SGR
# after every occurrence of it bolds just the branch — and the segment's own trailing
# reset (\e[0m) turns bold back off. This matches the GSD live stage + the subagent
# "running" word so all green-active text shares one weight (terminal bold ≈ semibold).
# Done here, NOT in claude-powerline.json: its custom theme reads only per-segment fg,
# never a bold flag. Must run BEFORE the context-gauge splice below (the gauge reuses
# green 114 = 38;5;114, a different code, so the two never collide).
line1="$(printf '%s' "$line1" | sed "s/${esc}\[38;2;135;215;135m/&${esc}[1m/g")"

# ---- context-usage gauge (replaces powerline's context segment) ----
# 9-cell gauge that fills with the context window's used_percentage. Filled cells
# (▓) take their zone colour — cells 1-3 green, 4-6 amber, 7-9 red — so only the
# reached zones light up; empty cells (░) are a dark-gray dotted track. Green =
# plenty of room, red = nearly full.
ctxpct="$(printf '%s' "$input" | jq -r '.context_window.used_percentage // 0' 2>/dev/null)"
ctxpct="${ctxpct%%.*}"; ctxpct="${ctxpct//[^0-9]/}"; [ -z "$ctxpct" ] && ctxpct=0
ctxleft="$(printf '%s' "$input" | jq -r '.context_window.remaining_percentage // empty' 2>/dev/null)"
ctxleft="${ctxleft%%.*}"; ctxleft="${ctxleft//[^0-9]/}"; [ -z "$ctxleft" ] && ctxleft=$(( 100 - ctxpct ))
ccells=9
cfill=$(( (ctxpct * ccells + 50) / 100 ))
[ "$cfill" -gt "$ccells" ] && cfill=$ccells
[ "$cfill" -lt 0 ] && cfill=0
GRNc=$'\033[38;5;114m'   # green — zone 1 (healthy)
YELc=$'\033[38;5;178m'   # amber — zone 2 (caution)
REDc=$'\033[38;5;203m'   # red   — zone 3 (nearly full)
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
# "NN% Restante" = context still available — bold red once the gauge enters the
# red zone (cfill >= 7, i.e. ~72%+ used); light gray otherwise.
if [ "$cfill" -ge 7 ]; then numcol="${B}${REDc}"; else numcol="$LG"; fi
# splice "- <gauge> NN% Restante" onto the powerline session line (carries §);
# the session segment already ends with a space.
ctxseg="${DG}-${R} ${ctxbar} ${numcol}${ctxleft}% Restante${R}"
line1="$(printf '%s' "$line1" | sed "/§/s/\$/${ctxseg}/")"

# ---- locate the GSD project root (walk up from Claude's cwd) ----
cwd="$(printf '%s' "$input" | jq -r '.workspace.current_dir // .cwd // .workspace.project_dir // empty' 2>/dev/null)"
[ -z "$cwd" ] && cwd="$PWD"

state=""
dir="$cwd"
while [ "$dir" != "/" ] && [ -n "$dir" ]; do
  if [ -f "$dir/.planning/STATE.md" ]; then state="$dir/.planning/STATE.md"; break; fi
  dir="$(dirname "$dir")"
done

# Not a GSD project → Context Management block only (title + powerline).
# Powerline supplies its own 1-space leading padding, matching the GSD block.
if [ -z "$state" ]; then
  title "✳ Context Management"
  printf '%s' "$line1"
  printf '\n%s' "$SP"
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

# sanitize numerics
percent="${percent//[^0-9]/}"; cdone="${cdone//[^0-9]/}"; ctot="${ctot//[^0-9]/}"
[ -z "$milestone" ] && milestone="?"
[ -z "$percent" ] && percent=0
[ -z "$cdone" ] && cdone=0
[ -z "$ctot" ] && ctot=0

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
#                  Renders: "Version: v1.7 · M3/8 · Ph27  <bar>  ⇒ Next: Discuss"
#                  Entry: `$livestage` empty + `$done` -eq 0. See line ~621.
#
#   Mode: Active — EITHER live signal fresh: /tmp/gsd-cmd (30min TTL) OR
#                  /tmp/gsd-live (10s TTL). A /gsd-* command is running.
#                  Renders: "Now: <glyph> <gerund> <cascade>  <bar>  ⇒ Next:"
#                  Entry: `$livestage` non-empty (any live token). See line ~280.
#
#   Mode: Alert  — ORTHOGONAL row. When parse_alerts reports any non-zero count,
#                  "    ⚠ <severity-ordered counts>" is appended to Idle OR Active.
#                  Base mode renders normally; Alert just adds the row.
#                  Entry: `$has_alerts` -eq 1. See line ~549 (alertseg) + line ~571.
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
#                             trusted up to 10s (it refreshes constantly while live).
#                             Also carries "<cur> <tot>" sub-step counts.
# (session_id + now_epoch are computed once at the top, before the powerline cache.)
livecol=""; livecoloff=""; livelabel=""; livestage=""; livephase=""; substep=""; livecmdslug=""

# Defensive top-level init — these are populated later but MAY be referenced
# by the finished-check (D-15 enhanced) before population. set -uo pipefail safety.
todo=0; uat=0; blocker=0
acol=""; aparts=""
# Phase 4 Task 1 (D-14): wave-segment vars are populated inside the cascade builder
# but defensive init mirrors the cts/cst/cph/csl pattern for set -uo pipefail safety.
wts=""; wcur=""; wtot=""

# Read the subagent-panel live file ONCE: "<epoch> <stage> <cur> <tot>" (10s fresh).
# <stage> is the fallback live stage; <cur>/<tot> drive the dynamic sub-step counter
# (Option A: cur = subagents started, tot = subagents spawned this command).
live_fresh=0; live_stage_f=""; live_cur=""; live_tot=""
lf="/tmp/gsd-live-${session_id}"
if [ -f "$lf" ]; then
  lts=""; lst=""; lcur=""; ltot=""
  read -r lts lst lcur ltot < "$lf" 2>/dev/null || true
  if [ -n "$lts" ] && [ "${lts//[^0-9]/}" = "$lts" ] && [ "$(( now_epoch - lts ))" -le 10 ]; then
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

# D-10..D-13: Alert counter. parse_alerts is Phase 1's mtime-cached helper.
# Called BEFORE the finished-check so Task 4's enhanced D-15 condition (archived
# AND no quick/fast AND no alerts → hide GSD block) can read these counts.
# Defensive top-level init at line ~261 (Task 1) already set blocker/uat/todo=0,
# so a failed read leaves them at 0 (no set -uo pipefail trip).
read -r todo uat blocker < <(parse_alerts "$state") || true
todo="${todo:-0}"; uat="${uat:-0}"; blocker="${blocker:-0}"

# Hide the whole GSD block once the milestone is finished — only Context
# Management shows then (e.g. in completed or other-project tabs). EXCEPTION: a fresh
# live signal ($livestage, detected above) means a GSD command is running RIGHT NOW
# (e.g. /gsd-new-milestone between milestones, before STATE.md is rewritten) — keep the
# bar visible and let the live override below drive the pulsing stage.
# D-15: archived + no quick/fast + no alerts → hide entire GSD block.
# $blocker/$uat/$todo were populated by parse_alerts (above) — Task 1 defensive
# init ensures they exist as 0 even if parse_alerts failed (set -uo pipefail safe).
if [ "$done" -eq 1 ] && [ -z "$livestage" ] && [ "$blocker" -eq 0 ] 2>/dev/null && [ "$uat" -eq 0 ] 2>/dev/null && [ "$todo" -eq 0 ] 2>/dev/null; then
  title "✳ Context Management"
  printf '%s' "$line1"
  printf '\n%s' "$SP"
  exit 0
fi

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
    Debug)             glyph="◍"; livelabel="Debugging"          ;;
    # --- Unknown non-empty token (D-22): render raw verbatim with neutral glyph ---
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
    # D-08: livecmdslug empty → livelabel stays as bare "Quick" or "Fast" (no suffix, no "(loading)").
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
  # shown only while subagents are fresh (<=10s) and at least one is in the panel.
  # cur (started) bold purple; parens + "/" dark-gray structure; tot light gray.
  if [ -n "$live_tot" ] && [ "$live_fresh" -eq 1 ] && [ "$live_tot" -gt 0 ] 2>/dev/null; then
    [ -z "$live_cur" ] && live_cur=0
    substep=" ${DG}(${R}${B}${PUR}${live_cur}${R}${DG}/${R}${LG}${live_tot}${R}${DG})${R}"
  fi
fi

# D-19 regression target: TreSur STATE.md (phase 33 of milestone v1.7) has
# frontmatter total_plans: 89 (milestone-wide) but body "Plan: Not started"
# for phase 33. Pre-fix the bar showed "Ph33/89" (wrong — used $ptot).
# Post-fix the bar shows "M32/38 · Ph33" in idle (no Pl because no plan running).
# During Execute it would show "... · Pl<n>/<m>" with m from "Plan: N of M".
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

# Next: upcoming GSD step — a transition state above may have set it, else derive
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
    # --- Meta-end: terminal stages have no Next: ---
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
[ -n "$nextstep" ] && nextseg=" ${B}${LG}⇒${R} ${DG}Next:${R} ${LG}${nextstep}${R}"

# D-13: zero alerts → segment hidden entirely (no placeholder).
# D-10: severity-first order (blocker first, then uat, then todo).
# D-11: glyph + all counts share ONE color (red if blocker>0, else amber). Single SGR set, single reset.
# D-12: separator is middot " · ".
# NOTE: $acol and $aparts were defensively initialized to "" at line ~262 (Task 1)
# so they exist even if has_alerts is false — Task 4's D-16 branch can safely
# reuse $alertseg without re-computing them.
# ----- Mode: Alert (orthogonal row, D-03) -----
# When any of $blocker / $uat / $todo is > 0, build $alertseg as
# "    ⚠ <severity-ordered counts>" colored uniformly (red if blocker, else amber).
# This segment is APPENDED to whatever base mode (Idle or Active) is rendered
# below — it is NOT a separate mode that replaces them. Hence "orthogonal".
# Empty when no alerts → contributes nothing to the seg= line.
alertseg=""
if [ "$blocker" -gt 0 ] 2>/dev/null || [ "$uat" -gt 0 ] 2>/dev/null || [ "$todo" -gt 0 ] 2>/dev/null; then
  # D-11: severity color
  if [ "$blocker" -gt 0 ] 2>/dev/null; then
    acol="$REDc"
  else
    acol="$YELc"
  fi
  # D-10: severity-first build, dropping zero counts (D-13 corollary)
  aparts=""
  if [ "$blocker" -gt 0 ] 2>/dev/null; then
    aparts="${blocker} blocker"
  fi
  if [ "$uat" -gt 0 ] 2>/dev/null; then
    [ -n "$aparts" ] && aparts="${aparts} · "
    aparts="${aparts}${uat} uat"
  fi
  if [ "$todo" -gt 0 ] 2>/dev/null; then
    [ -n "$aparts" ] && aparts="${aparts} · "
    aparts="${aparts}${todo} todo"
  fi
  # Whole segment colored uniformly. Leading 4-space gap separates from Next:.
  alertseg="    ${acol}⚠ ${aparts}${R}"
fi

# ---- Visibility state flags (D-14..D-18) ----
# has_alerts: any alert count > 0 (D-13 inverse). $blocker/$uat/$todo were
# populated by Task 3's parse_alerts call (which runs BEFORE the finished-check).
has_alerts=0
if [ "$blocker" -gt 0 ] 2>/dev/null || [ "$uat" -gt 0 ] 2>/dev/null || [ "$todo" -gt 0 ] 2>/dev/null; then
  has_alerts=1
fi
# is_quickfast: $livestage is Quick or Fast specifically (drives D-17/D-18)
is_quickfast=0
if [ "$livestage" = "Quick" ] || [ "$livestage" = "Fast" ]; then
  is_quickfast=1
fi
# is_live: any live command running (drives D-14's "no Now: when idle" distinction)
is_live=0
[ -n "$livestage" ] && is_live=1

# ---- Visibility rules D-14..D-18 ----
# Build seg conditionally based on (done, is_live, is_quickfast, has_alerts).
if [ "$done" -eq 1 ]; then
  # Archived milestone — D-15 hide handled above (early exit).
  # Remaining archived cases: D-16 (alerts only), D-17 (quick/fast only), D-18 (both).
  if [ "$is_quickfast" -eq 1 ] && [ "$has_alerts" -eq 1 ]; then
    # D-18: archived + quick/fast + alerts — render kind+slug AND alert counter.
    # $alertseg already carries the leading 4-space gap + color SGR + reset — reuse it.
    seg="${glyph} ${livecol}${stage}${livecoloff}${alertseg}"
  elif [ "$is_quickfast" -eq 1 ]; then
    # D-17: archived + quick/fast only — render kind+slug only
    seg="${glyph} ${livecol}${stage}${livecoloff}"
  elif [ "$is_live" -eq 1 ]; then
    # Rare: archived + non-quick/fast live stage (e.g. /gsd-new-milestone running
    # between milestones BEFORE STATE.md rewrite). Fall through to full layout
    # so the user still sees the in-flight command — matches pre-Phase-3 behavior.
    seg="${DG}Version:${R} ${LG}${milestone}${R} ${DG}·${R} ${DG}Now:${R} ${LG}${now}${R}  ${PUR}${barF}${R}${DG}${barE}${R}${counter}${nextseg}${alertseg}"
  elif [ "$has_alerts" -eq 1 ]; then
    # D-16: archived + alerts only — render alert segment only (NO leading 4-space gap
    # since nothing precedes it). REUSE $alertseg (single source of truth for alert
    # formatting per B3 fix) and strip its leading 4-space padding.
    seg="${alertseg#    }"
  else
    # Defensive: should not reach here (D-15 handled above)
    seg=""
  fi
else
  # ----- Mode: Idle vs Mode: Active dispatch (active milestone) -----
  # D-14: when no live command, render Idle layout (no Now: segment).
  # When live signal present, render Active layout (Now: + cascade + spinner).
  # Alert row (if has_alerts) is appended in both branches via $alertseg.
  if [ "$is_live" -eq 1 ]; then
    # Live command running — full layout with Now: segment
    seg="${DG}Version:${R} ${LG}${milestone}${R} ${DG}·${R} ${DG}Now:${R} ${LG}${now}${R}  ${PUR}${barF}${R}${DG}${barE}${R}${counter}${nextseg}${alertseg}"
  else
    # D-14: active milestone idle — no Now: segment. Counter + bar + Next: + alerts only.
    # phaseplanseg sits directly after Version: (no Now: wrapper).
    # W5: guard $phaseplanseg interpolation to avoid double-space when empty.
    if [ -n "$phaseplanseg" ]; then
      seg="${DG}Version:${R} ${LG}${milestone}${R} ${DG}·${R} ${LG}${phaseplanseg}${R}  ${PUR}${barF}${R}${DG}${barE}${R}${counter}${nextseg}${alertseg}"
    else
      seg="${DG}Version:${R} ${LG}${milestone}${R}  ${PUR}${barF}${R}${DG}${barE}${R}${counter}${nextseg}${alertseg}"
    fi
  fi
fi

# ---- emit: two titled blocks separated by zero-width-space spacer rows ----
# Layout (title → content → gap):
#   Context Management
#    <powerline>
#   <gap>
#   GSD Status
#    <gsd line>
#   <trailing gap>   ← blank line above the TUI's "accept edits" indicator
title "✳ Context Management"
printf '%s' "$line1"
printf '\n%s\n' "$SP"
title "◎ GSD Status"
# Lead with a reset code BEFORE the indent space: Claude Code trims leading
# literal whitespace, but a space that follows an ANSI code survives (this is
# how the powerline keeps its indent). Keeps content indented like the other block.
printf '%s %s\n' "$R" "$seg"
printf '%s' "$SP"
