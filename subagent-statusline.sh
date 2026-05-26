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
session_id="$(printf '%s' "$input" | jq -r '.session_id // "default"' 2>/dev/null)"
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
printf '%s %s %s %s\n' "$(date +%s)" "$livestage" "$sub_cur" "$sub_tot" > "/tmp/gsd-live-${session_id}" 2>/dev/null || true
