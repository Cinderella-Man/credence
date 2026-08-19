#!/usr/bin/env bash
#
# run_capped.sh — run one command under a systemd memory ceiling. The OOM
# history in this repo (docs/21) is unbounded compiles, not concurrency: any
# ad-hoc evaluation of rule output or fixture strings goes through this wrapper
# so a runaway compile kills the scope, not the machine.
#
# Usage: run_capped.sh [-m MEM] <cmd> [args...]     (default MEM: 4G)
# Env:   RUN_CAPPED_MEM — default ceiling when -m is not given
set -uo pipefail

MEM="${RUN_CAPPED_MEM:-4G}"
if [[ "${1:-}" == "-m" ]]; then
  [[ $# -ge 2 ]] || { echo "usage: run_capped.sh [-m MEM] <cmd> [args...]" >&2; exit 2; }
  MEM="$2"; shift 2
fi
[[ $# -ge 1 ]] || { echo "usage: run_capped.sh [-m MEM] <cmd> [args...]" >&2; exit 2; }

if command -v systemd-run >/dev/null 2>&1 \
   && systemd-run --user --scope -q -p MemoryMax="$MEM" true 2>/dev/null; then
  exec systemd-run --user --scope -q -p MemoryMax="$MEM" -p MemorySwapMax=0 -- "$@"
fi

echo "[run_capped] WARNING: systemd-run unavailable — running UNCAPPED" >&2
exec "$@"
