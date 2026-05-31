#!/usr/bin/env bash
# Stop hook. The turn (and thus the inline /gsd-<verb> command) finished — clear the
# live GSD command record + wave record so the statusline reverts to STATE.md.
# Always exits 0.
set -uo pipefail

input="$(cat)"
sid="$(printf '%s' "$input" | jq -r '.session_id // "default"' 2>/dev/null)"
rm -f "/tmp/gsd-cmd-${sid}" 2>/dev/null
# Phase 4 D-16: /tmp/gsd-wave-<sid> is written by subagent-statusline.sh when
# executor agents label themselves "Wave N/M: ...". Clear it on Stop (cmd file
# parity). /tmp/gsd-live-<sid> remains self-managed by subagent-statusline (10s TTL).
rm -f "/tmp/gsd-wave-${sid}" 2>/dev/null
exit 0
