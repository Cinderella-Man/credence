#!/usr/bin/env bash
#
# move_unfixable_out.sh — one-time pre-pass over docs/candidates.md.
#
# Reads the sister checkout to find candidate rules that are PROVABLY check-only
# (the `unfixable_stub?` predicate in review_lib.sh) and removes each from the
# queue — its rule line PLUS its grouped test line(s) — recording it in
# docs/unfixable.md. List-only bookkeeping: no rule files enter this branch.
# One commit + push. Idempotent: once the queue is clean, a re-run is a no-op.
#
# Works for all three kinds (pattern|semantic|syntax); the predicate dispatches
# on the rule path. Today this filters 51 pattern stubs and 0 semantic/syntax.
#
# Env:
#   SISTER=/path   sister checkout (default ../credence_evolution)
#   DRY_RUN=1      preview what would move; make no edits, no commit, no push
#
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(dirname "$SCRIPT_DIR")"
# shellcheck source=review_lib.sh
source "$SCRIPT_DIR/review_lib.sh"
CANDIDATES="$REPO/docs/candidates.md"
UNFIXABLE="$REPO/docs/unfixable.md"
SISTER="${SISTER:-$(cd "$REPO/.." && pwd)/credence_evolution}"
DRY_RUN="${DRY_RUN:-}"

[[ -f "$CANDIDATES" ]] || { echo "error: $CANDIDATES not found" >&2; exit 1; }
[[ -f "$UNFIXABLE"  ]] || { echo "error: $UNFIXABLE not found"  >&2; exit 1; }
[[ -d "$SISTER"     ]] || { echo "error: sister dir not found: $SISTER (override with SISTER=/path)" >&2; exit 1; }

today="$(date +%F)"
strip="$(mktemp)"; entries="$(mktemp)"
trap 'rm -f "$strip" "$entries"' EXIT

count=0
while IFS= read -r rel; do
  case "$rel" in
    lib/pattern/*.ex | lib/semantic/*.ex | lib/syntax/*.ex) ;;
    *) continue ;;
  esac
  src="$SISTER/$rel"
  [[ -f "$src" ]] || continue
  is_unfixable_stub "$src" || continue

  kind="$(rule_kind "$rel")"
  base="$(rule_base "$rel")"
  mapfile -t tlines < <(group_tests "$base" "$CANDIDATES")

  printf '%s\n' "$rel" >> "$strip"
  [[ ${#tlines[@]} -gt 0 ]] && printf '%s\n' "${tlines[@]}" >> "$strip"

  {
    echo "## ${base} (${kind}) — ${today}"
    echo "- Rule: \`${rel}\`"
    if [[ ${#tlines[@]} -gt 0 ]]; then
      echo "- Tests:"
      printf '  - `%s`\n' "${tlines[@]}"
    fi
    echo "- Reason: check-only stub — every fix clause is the verbatim dead form (\`unfixable_stub?\`)."
    echo
  } >> "$entries"
  count=$((count + 1))
done < "$CANDIDATES"

if [[ "$count" -eq 0 ]]; then
  echo "no unfixable stubs in candidates.md — nothing to do."
  exit 0
fi

strip_n="$(grep -c . "$strip" || true)"
echo "found ${count} unfixable stub(s) → ${strip_n} line(s) to strip from candidates.md."

if [[ -n "$DRY_RUN" ]]; then
  echo "--- DRY RUN: lines that would be stripped ---"; cat "$strip"
  echo "--- DRY RUN: entries that would be appended to unfixable.md ---"; cat "$entries"
  exit 0
fi

before="$(grep -c -v '^[[:space:]]*$' "$CANDIDATES" || true)"
filtered="$(grep -vxF -f "$strip" "$CANDIDATES" || true)"
printf '%s\n' "$filtered" > "$CANDIDATES"
cat "$entries" >> "$UNFIXABLE"
after="$(grep -c -v '^[[:space:]]*$' "$CANDIDATES" || true)"

git -C "$REPO" add "$CANDIDATES" "$UNFIXABLE"
git -C "$REPO" commit -q -m "move ${count} check-only stubs to unfixable"
git -C "$REPO" push -q

echo "moved ${count} rule(s); candidates.md ${before} → ${after} line(s). committed + pushed."
