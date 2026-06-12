#!/usr/bin/env bash
# SessionStart hook. Pre-warms the @owloops/claude-powerline npx cache + writes
# the session-scoped /tmp/gsd-powerline-<session_id> cache file so the very FIRST
# render of statusline-gsd.sh finds the powerline output ready (no ~2.6s npx fetch
# stall on cold tabs — COLD-01 fix bundled into v1.2).
#
# Why a SessionStart hook (not a per-render warm-up):
#   v1.1 tried "script-side background warm-up" in statusline-gsd.sh itself and
#   regressed the warm path. Moving the warm-up OUT of the render hot path and INTO
#   a one-shot SessionStart trigger means:
#     (a) no overhead on the per-second render
#     (b) the very first render of a new session finds the cache already warm
#
# Side-effect only: writes to /tmp/gsd-powerline-${session_id} (4s TTL — same cache
# file statusline-gsd.sh reads at ~line 319). Always exits 0 so it never blocks
# Claude Code session startup. The background npx is fully detached via
# nohup + disown so the hook returns immediately.
#
# ---------------------------------------------------------------------------
# USER-SIDE WIRING — add this to ~/.claude/settings.json under "hooks":
# ---------------------------------------------------------------------------
#   "hooks": {
#     "SessionStart": [{
#       "hooks": [{
#         "type": "command",
#         "command": "bash /Users/tresur/Documents/claude-tooling/hooks/prewarm-powerline.sh",
#         "timeout": 5
#       }]
#     }]
#   }
# ---------------------------------------------------------------------------

set -uo pipefail

input="$(cat)"

# Resolve sibling claude-powerline.json the same way statusline-gsd.sh does, so the
# whole repo stays relocatable (no hardcoded ~/.claude path).
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PL_CONFIG="$SCRIPT_DIR/../claude-powerline.json"

session_id="$(printf '%s' "$input" | jq -r '.session_id // "default"' 2>/dev/null)"
[ -z "$session_id" ] && session_id="default"

cache="/tmp/gsd-powerline-${session_id}"

# Fire the npx call IN THE BACKGROUND. Detach fully so this hook returns
# immediately (Claude Code session startup must not block on the npx fetch).
# - nohup + </dev/null: detach stdin
# - >"$cache" 2>/dev/null: write output to the session cache file
# - & disown: remove from job table so no "Terminated" notification ever fires
nohup bash -c "printf '%s' \"\$0\" | npx -y @owloops/claude-powerline@latest --config=\"\$1\" > \"\$2\" 2>/dev/null" \
  "$input" "$PL_CONFIG" "$cache" </dev/null >/dev/null 2>&1 &
disown 2>/dev/null || true

exit 0
