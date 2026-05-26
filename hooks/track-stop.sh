#!/usr/bin/env bash
# Stop hook. The turn (and thus the inline /gsd-<verb> command) finished — clear the
# live GSD command record so the statusline reverts to STATE.md. Always exits 0.
set -uo pipefail

input="$(cat)"
sid="$(printf '%s' "$input" | jq -r '.session_id // "default"' 2>/dev/null)"
rm -f "/tmp/gsd-cmd-${sid}" 2>/dev/null
exit 0
