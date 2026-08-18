#!/usr/bin/env bash
#
# status.sh — progress digest for the whole-PR review campaign.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MANIFEST="$SCRIPT_DIR/manifest.json"
[[ -f "$MANIFEST" ]] || { echo "no manifest.json — run generate_manifest.sh first" >&2; exit 1; }

jq -r '
  (.files | length) as $total |
  ([.files[] | select(.status == "done")]    | length) as $done |
  ([.files[] | select(.status == "pending")] | length) as $pending |
  ([.files[] | select(.status == "error")]   | length) as $err |
  ([.files[] | select(.status == "done" and .verdict == "FINDINGS")] | length) as $ffiles |
  ([.files[] | select(.status == "done") | .findings] | add // 0) as $nfind |
  ([.files[] | select(.stale == true)] | length) as $stale |
  "pr_review — base \(.base[0:9]) → head \(.head[0:9])  (generated \(.generated_at))",
  "",
  "  progress:  \($done)/\($total) done (\(if $total > 0 then ($done * 100 / $total | floor) else 0 end)%)  ·  \($pending) pending  ·  \($err) error\(if $stale > 0 then "  ·  \($stale) stale" else "" end)",
  "  verdicts:  \($done - $ffiles) OK  ·  \($ffiles) with findings (\($nfind) findings total → findings.md)",
  "",
  "  by category (done/total):",
  (.files | group_by(.category) | sort_by(.[0].category) | .[] |
    "    \(.[0].category | . + (" " * (14 - length)))\([.[] | select(.status == "done")] | length)/\(length)"),
  (if $err > 0 then
    "", "  errors (requeue.sh --errors to retry):",
    (.files[] | select(.status == "error") | "    \(.path) — \(.error)")
   else empty end),
  (if $done > 0 then
    "", "  last reviewed:",
    ([.files[] | select(.status == "done")] | sort_by(.reviewed_at) | .[-5:] | .[] |
      "    \(.reviewed_at)  \(.path) — \(.verdict)\(if .findings > 0 then "(\(.findings))" else "" end)")
   else empty end)
' "$MANIFEST"
