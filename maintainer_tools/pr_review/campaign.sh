#!/usr/bin/env bash
#
# campaign.sh — review-first campaign driver. It completes a review tranche,
# aggregates its findings, and only then drains blocker-level fixes.
#
# Review and repair are deliberately separated so repeated root causes can be
# triaged before the campaign spends fix sessions on symptoms.
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

reviews_before="$(jq '[.files[] | select(.status == "done")] | length' "$MANIFEST")"
reviews_total="$(jq '.files | length' "$MANIFEST")"
log "review phase: $reviews_before/$reviews_total done, $(pending_reviews) pending"
QUIET_STATUS=1 "$SCRIPT_DIR/review_loop.sh" "$CAP" "$WAIT_MIN" 8>&- \
  || die "review_loop failed — fix the cause, then rerun campaign.sh"
"$SCRIPT_DIR/aggregate_findings.sh" 8>&- \
  || die "finding aggregation failed"

# The default severity floor is blocker. Explicitly preserve an operator's
# override for end-of-campaign concern/nit sweeps.
log "fix phase: $(pending_fixes) pending entries"
FIX_MIN_SEVERITY="${FIX_MIN_SEVERITY:-blocker}" "$SCRIPT_DIR/fix_loop.sh" 8>&- \
  || die "fix_loop failed — fix the cause, then rerun campaign.sh"

if (( $(pending_reviews) == 0 )); then
    (( $(pending_fixes) == 0 )) || die "review queue drained but fix entries remain pending"
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
else
  reviews_after="$(jq '[.files[] | select(.status == "done")] | length' "$MANIFEST")"
  log "review tranche complete — $((reviews_after - reviews_before)) review(s); inspect finding_summary.md before the next tranche"
fi

"$SCRIPT_DIR/status.sh" || true
