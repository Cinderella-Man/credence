#!/usr/bin/env bash
# Run cross-cutting, read-only adversarial reviews after category tranches.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$SCRIPT_DIR/../.." && pwd)"
RUNNER="$SCRIPT_DIR/agent_runner.sh"
OUT="$SCRIPT_DIR/adversarial_findings.md"
LOG_DIR="$SCRIPT_DIR/.adversarial_logs"
PASS="${1:-all}"

declare -A LENSES=(
  [ordering]="Rule ordering, diagnostic ownership, starvation, and duplicate ownership across semantic dispatch."
  [interaction]="Cross-rule interference: one repair changing another rule's admission, output, ordering, or safety guard."
  [masking]="Source masking, byte/grapheme offsets, strings/comments/heredocs, and edits outside intended code bytes."
  [convergence]="Idempotency, repeated repair rounds, oscillation, partial repair, and non-converging fixes."
  [containment]="Compilation and execution containment, timeouts, heap limits, and arbitrary fixture execution."
  [tests]="Vacuous tests, weak text assertions, fixture collisions, missing end-to-end firing, and false-green controls."
  [performance]="Algorithmic, memory, compilation, corpus, mutation, and CI performance regressions."
)

run_pass() {
  local name="$1" result log
  result="$(mktemp "$SCRIPT_DIR/.adversarial.${name}.XXXXXX")"
  mkdir -p "$LOG_DIR"
  log="$LOG_DIR/${name}-$(date +%Y%m%dT%H%M%S).log"
  prompt="You are an adversarial maintainer reviewing the main...evolution_accepted candidate. Focus only on: ${LENSES[$name]}

Read the repository and PR diff. Do not modify files or run builds/tests. Return either exactly OK or FINDINGS followed by concrete bullets in the form '- blocker|concern|nit: path:line — impact and triggering input'. Avoid duplicating findings already recorded in maintainer_tools/pr_review/findings.md or this adversarial ledger."
  if ! printf '%s' "$prompt" | AGENT_REPO="$REPO" "$RUNNER" review "$result" >"$log" 2>&1; then
    echo "adversarial pass '$name' failed; transcript: $log" >&2
    tail -n 40 "$log" >&2
    rm -f "$result"
    return 1
  fi
  {
    printf '## %s — %s\n\n' "$name" "$(date -Is)"
    cat "$result"
    printf '\n\n'
  } >> "$OUT"
  rm -f "$result"
}

exec 9>"$SCRIPT_DIR/.adversarial.lock"
flock -n 9 || { echo "another adversarial review is running" >&2; exit 1; }
touch "$OUT"
if [[ "$PASS" == all ]]; then
  for name in ordering interaction masking convergence containment tests performance; do run_pass "$name"; done
elif [[ -n "${LENSES[$PASS]:-}" ]]; then
  run_pass "$PASS"
else
  echo "unknown pass: $PASS" >&2; exit 64
fi
