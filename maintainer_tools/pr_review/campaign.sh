#!/usr/bin/env bash
#
# campaign.sh — the full review-AND-fix campaign: alternate one read-only
# review session with the fix phase, so a finding is confirmed, tested, fixed
# and re-verified as soon as it is produced instead of piling up in findings.md.
#
# Per iteration:
#   1. fix_loop.sh          — drain every pending fix entry (it syncs the fix
#                             ledger from manifest+findings itself, gates every
#                             commit, and refreshes the manifest when commits
#                             land so fixed files re-enter review as stale)
#   2. review_loop.sh 1     — review exactly one pending file
# until there is nothing pending on either side. Each child takes the shared
# .lock itself; this wrapper holds only .campaign.lock (one campaign at a time).
#
# Usage:   campaign.sh [cap] [wait_min]
#   cap        max review sessions this run (0 = until drained; default 0)
#   wait_min   minutes between iterations (default 0)
# Env: everything review_loop.sh and fix_loop.sh honour (AGENT_PROVIDER,
#      AGENT_MODEL, FIX_AGENT_MODEL, COMMIT_EVERY, MAX_RETRIES, FIX_MEM_MAX, …).
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MANIFEST="$SCRIPT_DIR/manifest.json"
FIXES="$SCRIPT_DIR/fixes.json"

CAP="${1:-0}"
WAIT_MIN="${2:-0}"

log() { printf '[campaign] %s\n' "$*"; }
die() { printf '[campaign] FATAL: %s\n' "$*" >&2; exit 1; }

[[ -f "$MANIFEST" ]] || die "no manifest.json — run generate_manifest.sh first"
command -v jq >/dev/null || die "jq not found"

exec 8>"$SCRIPT_DIR/.campaign.lock"
flock -n 8 || die "another campaign is already running"

pending_reviews() { jq -r '[.files[] | select(.status == "pending")] | length' "$MANIFEST"; }
gated_reviews()   { jq -r '[.files[] | select(.status == "gated")]   | length' "$MANIFEST"; }
stale_reviews()   { jq -r '[.files[] | select(.stale == true and .status == "done")] | length' "$MANIFEST"; }
pending_fixes()   { [[ -f "$FIXES" ]] && jq -r '[.entries[] | select(.status == "pending")] | length' "$FIXES" || echo 0; }

reviews=0
while :; do
  # Fix phase first: it also drains any backlog findings.md already holds.
  # 8>&- : children (and the agent sessions under them) must not inherit the
  # campaign lock fd — an orphaned session would hold it forever.
  "$SCRIPT_DIR/fix_loop.sh" 8>&- || die "fix_loop failed — fix the cause, then rerun campaign.sh"

  if (( $(pending_reviews) == 0 )); then
    (( $(pending_fixes) == 0 )) || die "no reviews pending but fix entries still pending — fix_loop should have drained them"
    # "Drained" means the QUEUE is empty, which is not the same as "everything
    # has been looked at". Two deliberate holdbacks survive it, and saying so
    # here is the difference between a finished campaign and one that only
    # looks finished.
    log "drained — nothing pending to review or fix"
    g="$(gated_reviews)"; s="$(stale_reviews)"
    (( g > 0 )) && log "  $g test row(s) still gated — their rule reviewed clean. Open with: requeue.sh --gated"
    (( s > 0 )) && log "  $s reviewed row(s) changed after their last review and settled at the re-review cap. Sweep with: requeue.sh --stale"
    (( $(jq -r '[.entries[] | select(.status == "skipped")] | length' "$FIXES" 2>/dev/null || echo 0) > 0 )) \
      && log "  nit-only fix rounds were recorded but not scheduled. Sweep with: FIX_MIN_SEVERITY=nit ./fix_queue.sh requeue --skipped"
    break
  fi
  if (( CAP > 0 && reviews >= CAP )); then
    log "cap $CAP review sessions reached"
    break
  fi

  QUIET_STATUS=1 "$SCRIPT_DIR/review_loop.sh" 1 8>&- || die "review_loop failed — fix the cause, then rerun campaign.sh"
  reviews=$((reviews + 1))

  if (( WAIT_MIN > 0 )); then
    log "waiting ${WAIT_MIN} min…"
    sleep "$((WAIT_MIN * 60))"
  fi
done

"$SCRIPT_DIR/status.sh" || true
