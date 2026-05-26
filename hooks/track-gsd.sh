#!/usr/bin/env bash
# UserPromptExpansion hook. When a /gsd-<verb> slash command is invoked, record the
# live GSD stage so statusline-gsd.sh can show + blink it during INLINE execution
# (STATE.md only updates after the command finishes, so it lags mid-command).
# Side-effect only: writes "<epoch> <Stage>" to /tmp/gsd-cmd-<session_id>. The Stop
# hook clears it at turn end. Always exits 0 so it never blocks/alters the prompt.
set -uo pipefail

input="$(cat)"
sid="$(printf '%s' "$input" | jq -r '.session_id // "default"' 2>/dev/null)"
cmd="$(printf '%s' "$input" | jq -r '.command_name // ""' 2>/dev/null | tr '[:upper:]' '[:lower:]')"

stage=""
case "$cmd" in
  *execut*)                                stage="Execute" ;;
  *verif*|*review*)                        stage="Verify"  ;;
  *discuss*|*spec*)                        stage="Discuss" ;;
  *roadmap*|*new-milestone*|*new-project*) stage="Roadmap" ;;
  *plan*)                                  stage="Plan"    ;;
esac

# Phase number from the command args (e.g. /gsd-discuss-phase 20 → "20"), so the
# bar can show the live phase before STATE.md catches up. Empty if no number.
args="$(printf '%s' "$input" | jq -r '.command_args // ""' 2>/dev/null)"
phase="$(printf '%s' "$args" | grep -oE '[0-9]+(\.[0-9]+)?' | head -1)"

[ -n "$stage" ] && printf '%s %s %s\n' "$(date +%s)" "$stage" "$phase" > "/tmp/gsd-cmd-${sid}" 2>/dev/null
exit 0
