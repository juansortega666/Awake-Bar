#!/usr/bin/env bash
# UserPromptExpansion hook. When a /gsd-<verb> slash command is invoked, record the
# live GSD stage so statusline-gsd.sh can show + blink it during INLINE execution
# (STATE.md only updates after the command finishes, so it lags mid-command).
# Side-effect only: writes "<epoch> <Token> <phase> <slug>" to /tmp/gsd-cmd-<session_id>.
# slug defaults to `-`; subagent-statusline.sh promotes the real slug for Quick/Fast.
# The Stop hook clears it at turn end. Always exits 0 so it never blocks/alters the prompt.
set -uo pipefail

input="$(cat)"
sid="$(printf '%s' "$input" | jq -r '.session_id // "default"' 2>/dev/null)"
cmd="$(printf '%s' "$input" | jq -r '.command_name // ""' 2>/dev/null | tr '[:upper:]' '[:lower:]')"

stage=""
case "$cmd" in
  *code-review*)                                    stage="CodeReview"        ;;
  *ui-review*)                                      stage="UIReview"          ;;
  *eval-review*)                                    stage="EvalReview"        ;;
  *validate*)                                       stage="Validate"          ;;
  *secure*)                                         stage="Secure"            ;;
  *verif*)                                          stage="Verify"            ;;
  *ui-phase*)                                       stage="UIPhase"           ;;
  *discuss*)                                        stage="Discuss"           ;;
  *plan*)                                           stage="Plan"              ;;
  *execut*)                                         stage="Execute"           ;;
  *research*)                                       stage="Research"          ;;
  *spec*)                                           stage="Spec"              ;;
  *quick*)                                          stage="Quick"             ;;
  *fast*)                                           stage="Fast"              ;;
  *debug*)                                          stage="Debug"             ;;
  *complete-milestone*)                             stage="CompleteMilestone" ;;
  *ship*)                                           stage="Ship"              ;;
  *roadmap*|*new-milestone*|*new-project*)          stage="Roadmap"           ;;
esac

# Phase number from the command args (e.g. /gsd-discuss-phase 20 → "20"), so the
# bar can show the live phase before STATE.md catches up. Empty if no number.
args="$(printf '%s' "$input" | jq -r '.command_args // ""' 2>/dev/null)"
phase="$(printf '%s' "$args" | grep -oE '[0-9]+(\.[0-9]+)?' | head -1)"

[ -n "$stage" ] && printf '%s %s %s\n' "$(date +%s)" "$stage" "$phase" > "/tmp/gsd-cmd-${sid}" 2>/dev/null
exit 0
