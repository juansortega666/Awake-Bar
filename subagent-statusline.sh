#!/usr/bin/env bash
# Restyles the running-agents panel to match the main statusline's palette.
# Claude Code pipes one JSON object on stdin per refresh:
#   { columns, cwd, session_id, transcript_path,
#     tasks: [ { id, type, status, description, label, startTime, tokenCount, tokenSamples, cwd } ] }
# Notes learned from the live payload:
#   - tasks contains only SPAWNED subagents. The "main"/orchestrator row is native
#     Claude Code chrome and is NOT in tasks — it cannot be restyled or relabeled.
#   - there is no "name" field; the display text is .label (fallback .description).
#   - Claude Code renders its own row marker (●/○) before our content, so we do NOT
#     add our own bullet glyph (that caused a double "○ ●").
# We emit one {"id","content"} JSON line per task. Content leads with an ANSI code
# (not a literal space) so it survives Claude Code's leading-whitespace trim.
# Palette (mirrors statusline-gsd.sh): running row = light-gray 252 label + BOLD green
# 114 "running" word (bold = the terminal's "semibold", matching the GSD line's live
# stage so all green-active text shares one weight); dark gray 240 + strikethrough
# (SGR 9) = inactive (completed/pending/failed). The "· <elapsed>" meta stays non-bold
# (SGR 22 turns bold back off after the word).

set -uo pipefail

input="$(cat)"
now_s=$(date +%s)

printf '%s' "$input" | jq -c --arg E "$(printf '\033')" --argjson now "$now_s" '
  def g(n): $E + "[38;5;" + (n|tostring) + "m";
  def R:    $E + "[0m";
  def STK:  $E + "[9m";
  def B:    $E + "[1m";
  def NB:   $E + "[22m";
  (.tasks // [])[] |
  (.status // "")                        as $st |
  (.label // .description // .type // "task") as $nm |
  (.startTime // 0)                      as $start |
  (if $start > 0 then (($now - ($start / 1000)) | floor) else -1 end) as $s |
  (if $s < 0 then "" elif $s >= 60 then (($s / 60) | floor | tostring) + "m"
   else ($s | tostring) + "s" end)       as $el |
  ("· " + $st + (if $el == "" then "" else " " + $el end)) as $meta |
  {
    id: .id,
    content: (
      if $st == "running"
      then g(252) + $nm + R + "  " + g(240) + "· " + B + g(114) + $st + NB
           + (if $el == "" then "" else g(240) + " " + $el end) + R
      else g(240) + STK + $nm + "  " + $meta + R
      end )
  }
' 2>/dev/null || true

# Bridge the LIVE GSD activity to the main statusline (statusline-gsd.sh). STATE.md
# lags while a GSD command runs, so record which GSD stage is actively running
# (inferred from the running agents' labels) into a session-keyed temp file with a
# timestamp. Empty stage = no GSD agent running. The main statusline reads this and
# overrides the stale STATE.md stage when the record is fresh. The record also carries
# the sub-step counts ("<epoch> <stage> <cur> <tot>") for the live "(cur/tot)" counter.
# Normalized identically in statusline-gsd.sh (see the long note there): jq's `//`
# does not fire on an EMPTY string, which collapsed every cache path to a shared
# suffix-less filename. The sanitize keeps the id from steering a write out of /tmp.
# Writer and reader address the same files by name, so this must not diverge.
session_id="$(printf '%s' "$input" | jq -r '.session_id // empty' 2>/dev/null)"
session_id="${session_id//[^A-Za-z0-9_-]/}"
[ -z "$session_id" ] && session_id="default"
running="$(printf '%s' "$input" | jq -r '[.tasks[]? | select(.status=="running") | (.label // .description // .type // "")] | join(" ") | ascii_downcase' 2>/dev/null)"

# Sub-step progress (Option A, dynamic): count the spawned subagents in the panel.
# tot = all subagents that have appeared this command; cur = those that have STARTED
# (running/completed/failed — i.e. everything except still-pending). The main
# statusline renders this as a "(cur/tot)" counter glued to the live stage.
subcounts="$(printf '%s' "$input" | jq -r '
  (.tasks // []) as $t |
  ($t | length) as $tot |
  ([$t[] | select((.status // "") as $s | $s == "running" or $s == "completed" or $s == "failed")] | length) as $cur |
  "\($cur) \($tot)"' 2>/dev/null)"
sub_cur="${subcounts%% *}"; sub_tot="${subcounts##* }"
case "$sub_cur" in *[!0-9]*|"") sub_cur=0 ;; esac
case "$sub_tot" in *[!0-9]*|"") sub_tot=0 ;; esac

livestage=""
case "$running" in
  *execut*)         livestage="Execute" ;;
  *verif*|*review*) livestage="Verify"  ;;
  *discuss*)        livestage="Discuss" ;;
  *roadmap*)        livestage="Roadmap" ;;
  *plan*)           livestage="Plan"    ;;
esac
# WR-01 fix: gate the write on a non-empty livestage. Otherwise unmatched
# subagent labels (e.g. ad-hoc Task() calls outside the /gsd-* vocabulary)
# left the file with " · 0 0" which the consumer's default-IFS read collapses,
# rendering a bogus "Now: · 0" in the bar. Absent file → bar treats as no
# live signal (correct), same pattern as the wave file below.
if [ -n "$livestage" ]; then
  printf '%s %s %s %s\n' "$(date +%s)" "$livestage" "$sub_cur" "$sub_tot" > "/tmp/gsd-live-${session_id}" 2>/dev/null || true
fi

# ---- Slug promotion for Quick/Fast (D-14, D-15) ----
# The hook (track-gsd.sh) writes `/tmp/gsd-cmd-<sid>` with slug=`-` because it
# fires on UserPromptExpansion, before the Quick/Fast subagent's label exists.
# When a Quick:/Fast: subagent IS running, its label carries the real slug —
# promote it into the cmd file's 4th positional field so the bar can render
# "⚡ Quick: <slug>" in Phase 3 (QUICK-01).
#
# In-place rewrite preserves the 4-positional schema (`<epoch> <token> <phase> <slug>`).
# Idempotent: skip if cmd file is absent (no GSD command active), if no Quick/Fast
# label is running, or if the slug was already promoted.
cf="/tmp/gsd-cmd-${session_id}"
if [ -f "$cf" ]; then
  # Pull the running tasks' raw labels (NOT lowercased — slug case matters).
  qf_label="$(printf '%s' "$input" | jq -r '
    [.tasks[]?
      | select(.status == "running")
      | (.label // .description // "")
      | select(test("^(Quick|Fast): "))
    ] | first // ""
  ' 2>/dev/null)"

  if [ -n "$qf_label" ]; then
    # Extract everything after the "Quick: " or "Fast: " prefix.
    new_slug="$(printf '%s' "$qf_label" | sed -E 's/^(Quick|Fast):[[:space:]]+//' | tr -s '[:space:]' '-' | sed -E 's/^-+//; s/-+$//')"
    if [ -n "$new_slug" ]; then
      # Read the current 4-positional line; only rewrite if slug field is `-`.
      cts=""; cst=""; cph=""; csl=""
      read -r cts cst cph csl < "$cf" 2>/dev/null || true
      # Guards: token must be Quick or Fast (we don't overwrite Execute/Verify/... slugs);
      # slug must currently be `-` or empty (idempotency / don't re-write same value).
      case "$cst" in
        Quick|Fast)
          if [ "$csl" = "-" ] || [ -z "$csl" ]; then
            printf '%s %s %s %s\n' "$cts" "$cst" "$cph" "$new_slug" > "$cf" 2>/dev/null || true
          fi
          ;;
      esac
    fi
  fi
fi

# ---- Wave promotion for Execute (Phase 4 D-16, D-17) ----
# The /gsd-execute-phase orchestrator labels executor subagents with a `Wave N/M:`
# prefix (e.g. label "Wave 1/3: Execute plan 01-02 of phase 1"). Parse that prefix
# from the FIRST running task whose label starts with `Wave \d+/\d+:` and write it
# to /tmp/gsd-wave-<sid> as `<epoch> <wave_cur> <wave_tot>` (10s TTL pattern, mirrors
# /tmp/gsd-live-<sid>). statusline-gsd.sh reads this only when livestage=Execute
# (cascade builder, Task 1). Absent file or stale (>10s) = no W segment renders.
#
# Schema choice: parallel file (NOT extending the 4-positional /tmp/gsd-cmd schema).
# Rationale: preserves Phase 1 contract, mirrors /tmp/gsd-live pattern, simple cleanup.
wave_label="$(printf '%s' "$input" | jq -r '
  [.tasks[]?
    | select(.status == "running")
    | (.label // .description // "")
    | select(test("^Wave [0-9]+/[0-9]+:"))
  ] | first // ""
' 2>/dev/null)"

if [ -n "$wave_label" ]; then
  wave_cur="$(printf '%s' "$wave_label" | sed -nE 's/^Wave ([0-9]+)\/([0-9]+):.*/\1/p')"
  wave_tot="$(printf '%s' "$wave_label" | sed -nE 's/^Wave ([0-9]+)\/([0-9]+):.*/\2/p')"
  if [ -n "$wave_cur" ] && [ -n "$wave_tot" ] && [ "$wave_tot" -gt 0 ] 2>/dev/null; then
    printf '%s %s %s\n' "$(date +%s)" "$wave_cur" "$wave_tot" > "/tmp/gsd-wave-${session_id}" 2>/dev/null || true
  fi
fi
