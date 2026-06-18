#!/usr/bin/env bash
#
# validate_loop.sh — autonomous corpus-whitelist validation loop.
#
# Drives one fresh, read-only (no edits, no git) Claude session per 100-finding
# batch from data/. The session audits every finding in its batch for over-firing
# and unsafe auto-fixes; its final message IS the batch report, captured to
# reports/<batch>.md. Between batches the loop sleeps a configurable number of
# minutes (mirrors stage_1's review_loop.sh).
#
# On the first run (data/ empty) it stages the batches via prepare_batches.sh,
# and fetches the corpus once so the agent can read corpus/<path>.
#
# A batch with a non-empty report is treated as DONE and skipped, so the loop is
# resumable: stop it (Ctrl-C) and re-run to continue where it left off.
#
# Usage:   validate_loop.sh [cap] [wait_min]
#   cap        max batches to validate THIS run (0 = all remaining; default 0)
#   wait_min   minutes to sleep between batches (default 5)
# Env:
#   CLAUDE_MODEL   optional --model for the session
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$SCRIPT_DIR"/../.. && pwd)"

DATA="$SCRIPT_DIR/data"
REPORTS="$SCRIPT_DIR/reports"
LOGDIR="$SCRIPT_DIR/.logs"
PROMPT="$SCRIPT_DIR/validate_batch_prompt.md"
CLAUDE_MODEL="${CLAUDE_MODEL:-}"

CAP="${1:-0}"
WAIT_MIN="${2:-5}"

# Read-only toolset: no Edit/Write/git — the agent only reads code and runs the
# read-only showfix/mix helpers. Its report comes back on stdout.
ALLOWED_TOOLS="Read Grep Glob Bash(mix run:*) Bash(elixir:*) Bash(cat:*) Bash(sed:*)"

log() { printf '[validate_loop] %s\n' "$*"; }
die() { printf '[validate_loop] FATAL: %s\n' "$*" >&2; exit 1; }

[[ -f "$PROMPT" ]] || die "prompt not found: $PROMPT"
mkdir -p "$LOGDIR" "$REPORTS"

# First run (or a cleared data/) → stage the batches.
if ! find "$DATA" -name 'batch_*.txt' 2>/dev/null | grep -q .; then
  log "no batches found — staging via prepare_batches.sh…"
  "$SCRIPT_DIR/prepare_batches.sh"
fi

# The agent reads corpus/<path>; make sure the corpus is present once up front.
# `credence.corpus.fetch` is idempotent (a no-op once the cache is warm).
log "ensuring the corpus is fetched (one-time)…"
( cd "$REPO" && mix credence.corpus.fetch >/dev/null 2>&1 ) \
  || log "warning: 'mix credence.corpus.fetch' returned non-zero — continuing"

mapfile -t BATCHES < <(find "$DATA" -name 'batch_*.txt' | sort)
TOTAL="${#BATCHES[@]}"
(( TOTAL > 0 )) || die "no batch files in $DATA"

# Run one read-only session over $1 (batch path); capture its report to $2.tmp.
# Returns non-zero on a failed/empty session.
run_session() {
  local batch="$1" report="$2" name prompt rc=0 rows
  name="$(basename "${batch%.txt}")"
  rows="$(wc -l < "$batch" | tr -d ' ')"
  prompt="$(cat "$PROMPT")"$'\n\n'"---"$'\n'"BATCH FILE: ${batch}"$'\n'"FINDINGS IN THIS BATCH: ${rows}"

  local -a model_args=()
  [[ -n "$CLAUDE_MODEL" ]] && model_args=(--model "$CLAUDE_MODEL")

  ( cd "$REPO" && claude -p "$prompt" --permission-mode acceptEdits \
      --allowedTools "$ALLOWED_TOOLS" "${model_args[@]}" ) \
      > "${report}.tmp" 2> "$LOGDIR/${name}.log" || rc=$?

  # A zero exit with empty output is still a failed session.
  [[ "$rc" -eq 0 && -s "${report}.tmp" ]]
}

main() {
  local idx=0 processed=0 done_count=0 retry=0

  # Count already-finished batches for the opening line.
  local b name report
  for b in "${BATCHES[@]}"; do
    name="$(basename "${b%.txt}")"; report="$REPORTS/${name}.md"
    [[ -s "$report" ]] && done_count=$((done_count + 1))
  done
  log "starting: ${TOTAL} batch(es), ${done_count} already validated, $((TOTAL - done_count)) to go (cap=${CAP:-0}, wait=${WAIT_MIN}m)"

  while (( idx < TOTAL )); do
    b="${BATCHES[idx]}"
    name="$(basename "${b%.txt}")"
    report="$REPORTS/${name}.md"

    if [[ -s "$report" ]]; then
      idx=$((idx + 1)); continue   # already validated
    fi
    if (( CAP > 0 && processed >= CAP )); then
      log "cap ${CAP} reached for this run"; break
    fi

    log "▶ validating ${name} ($((done_count + 1))/${TOTAL})  (transcript: $LOGDIR/${name}.log)"
    if run_session "$b" "$report"; then
      mv "${report}.tmp" "$report"
      processed=$((processed + 1)); done_count=$((done_count + 1)); retry=0
      log "✓ ${name} validated → ${report}"
    else
      rm -f "${report}.tmp"
      retry=$((retry + 1))
      local mins=$(( retry * 5 )); (( mins > 30 )) && mins=30
      local rs; rs="$(date -d "+${mins} minutes" '+%H:%M' 2>/dev/null || date '+%H:%M')"
      log "⚠ no report from Claude on ${name} (agent error/limit) — NOT done; retry #${retry} in ${mins} min (≈ ${rs}). Ctrl-C to stop."
      sleep $(( mins * 60 ))
      continue   # stay on the same batch
    fi

    idx=$((idx + 1))
    (( idx < TOTAL )) || { log "done — all batches processed"; break; }
    if (( CAP > 0 && processed >= CAP )); then log "cap ${CAP} reached for this run"; break; fi

    if (( WAIT_MIN > 0 )); then
      local resume; resume="$(date -d "+${WAIT_MIN} minutes" '+%H:%M' 2>/dev/null || date '+%H:%M')"
      log "waiting ${WAIT_MIN} min before the next batch ( $((TOTAL - done_count)) left ). Next ≈ ${resume}. Not crashed — sleeping; Ctrl-C to stop."
      sleep $(( WAIT_MIN * 60 ))
    fi
  done

  log "run complete: ${processed} batch(es) validated this run, ${done_count}/${TOTAL} total. Reports in $REPORTS"
}

main
