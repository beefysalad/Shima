#!/usr/bin/env bash
# Usage: scripts/with-log.sh OUT -- CMD...   Captures shima's unified log (debug level) while CMD runs.
set -uo pipefail
out="$1"; shift; [[ "${1:-}" == "--" ]] && shift
/usr/bin/log stream --level debug --style compact --predicate 'subsystem == "local.shima"' > "$out" 2>&1 &
lp=$!
sleep 1.5
"$@"; rc=$?
sleep 1
kill "$lp" 2>/dev/null; wait "$lp" 2>/dev/null
exit "$rc"
