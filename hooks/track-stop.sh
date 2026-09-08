#!/usr/bin/env bash
# Stop hook. The turn (and thus the inline /gsd-<verb> command) finished — clear the
# live GSD command record + wave record so the statusline reverts to STATE.md.
# Always exits 0.
set -uo pipefail

input="$(cat)"
# Normalized identically in statusline-gsd.sh (see the long note there): jq's `//`
# does not fire on an EMPTY string, which collapsed every cache path to a shared
# suffix-less filename. The sanitize keeps the id from steering a write out of /tmp.
# Writer and reader address the same files by name, so this must not diverge.
sid="$(printf '%s' "$input" | jq -r '.session_id // empty' 2>/dev/null)"
sid="${sid//[^A-Za-z0-9_-]/}"
[ -z "$sid" ] && sid="default"
rm -f "/tmp/gsd-cmd-${sid}" 2>/dev/null
# Phase 4 D-16: /tmp/gsd-wave-<sid> is written by subagent-statusline.sh when
# executor agents label themselves "Wave N/M: ...". Clear it on Stop (cmd file
# parity). /tmp/gsd-live-<sid> remains self-managed by subagent-statusline (10s TTL).
rm -f "/tmp/gsd-wave-${sid}" 2>/dev/null
exit 0
