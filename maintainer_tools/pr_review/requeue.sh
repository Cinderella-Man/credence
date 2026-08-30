#!/usr/bin/env bash
#
# requeue.sh — flip manifest entries back to `pending` so the loop retries them.
#
# Usage: requeue.sh --errors            # every status=error entry
#        requeue.sh --stale             # every stale=true entry (re-review)
#        requeue.sh --gated             # every test row still waiting on its rule
#        requeue.sh <path> [<path>...]  # specific entries (any status)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MANIFEST="$SCRIPT_DIR/manifest.json"
[[ -f "$MANIFEST" ]] || { echo "no manifest.json" >&2; exit 1; }
[[ $# -ge 1 ]] || { echo "usage: requeue.sh --errors | --stale | --gated | <path>..." >&2; exit 2; }

exec 9>"$SCRIPT_DIR/.lock"
flock -n 9 || { echo "review_loop is running — stop it before editing the manifest" >&2; exit 1; }

RESET='.status = "pending" | .error = null | .verdict = null | .findings = 0 | .reviewed_at = null'

requeue() { # $1 = jq select expression
  local tmp before after
  before="$(jq -r '[.files[] | select(.status == "pending")] | length' "$MANIFEST")"
  tmp="$(mktemp "$SCRIPT_DIR/.manifest.XXXXXX.json")"
  jq "(.files[] | select($1)) |= ($RESET)" "$MANIFEST" > "$tmp"
  mv "$tmp" "$MANIFEST"
  after="$(jq -r '[.files[] | select(.status == "pending")] | length' "$MANIFEST")"
  echo "requeued $((after - before)) entr$([[ $((after - before)) -eq 1 ]] && echo y || echo ies)"
}

case "$1" in
  --errors) requeue '.status == "error"' ;;
  --stale)  requeue '.stale == true' ;;
  # Gated rows were never reviewed, so RESET would not change them — flip the
  # status only, and leave any that were already opened alone.
  --gated)
    tmp="$(mktemp "$SCRIPT_DIR/.manifest.XXXXXX.json")"
    n="$(jq '[.files[] | select(.status == "gated")] | length' "$MANIFEST")"
    jq '(.files[] | select(.status == "gated")) |= (.status = "pending")' "$MANIFEST" > "$tmp"
    mv "$tmp" "$MANIFEST"
    echo "opened $n gated entr$([[ $n -eq 1 ]] && echo y || echo ies)" ;;
  *)
    for p in "$@"; do
      jq -e --arg p "$p" '.files[] | select(.path == $p)' "$MANIFEST" >/dev/null \
        || { echo "not in manifest: $p" >&2; exit 1; }
    done
    for p in "$@"; do
      tmp="$(mktemp "$SCRIPT_DIR/.manifest.XXXXXX.json")"
      jq --arg p "$p" "(.files[] | select(.path == \$p)) |= ($RESET)" \
        "$MANIFEST" > "$tmp"
      mv "$tmp" "$MANIFEST"
      echo "requeued: $p"
    done ;;
esac
