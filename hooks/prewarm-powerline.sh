#!/usr/bin/env bash
# SessionStart hook. Pre-warms the @owloops/claude-powerline npx cache + writes
# /tmp/gsd-powerline-<session_id> so the FIRST render finds powerline already warm
# (COLD-01 fix — eliminates the ~2.6s npx stall on cold tabs).
#
# Always exits 0; the background npx is fully detached so the hook returns
# immediately. See README for the settings.json wiring snippet.

set -uo pipefail

input="$(cat)"

# Resolve sibling claude-powerline.json the same way statusline-gsd.sh does, so the
# whole repo stays relocatable (no hardcoded ~/.claude path).
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PL_CONFIG="$SCRIPT_DIR/../claude-powerline.json"

# Normalized identically in statusline-gsd.sh (see the long note there): jq's `//`
# does not fire on an EMPTY string, which collapsed every cache path to a shared
# suffix-less filename. The sanitize keeps the id from steering a write out of /tmp.
# Writer and reader address the same files by name, so this must not diverge.
session_id="$(printf '%s' "$input" | jq -r '.session_id // empty' 2>/dev/null)"
session_id="${session_id//[^A-Za-z0-9_-]/}"
[ -z "$session_id" ] && session_id="default"
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
