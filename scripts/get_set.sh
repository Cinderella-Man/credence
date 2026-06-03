#!/usr/bin/env bash
#
# get_set.sh — fetch the next review "set" from the credence_evolution sister
# checkout into this repo.
#
# A "set" is the FIRST file listed in docs/pr_diff.md (the rule file) plus any
# of its test files that also appear in the list. Each file is copied from the
# sister checkout into the same relative path here (nested dirs preserved).
#
# It does NOT modify docs/pr_diff.md — that list is your progress tracker, so
# remove a set's lines yourself once you've finished reviewing it. Running this
# again then picks up the new first line.
#
# Sister checkout defaults to ../credence_evolution; override with SISTER=/path.
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(dirname "$SCRIPT_DIR")"
PRDIFF="$REPO/docs/pr_diff.md"
SISTER="${SISTER:-$(cd "$REPO/.." && pwd)/credence_evolution}"

[[ -f "$PRDIFF" ]] || { echo "error: $PRDIFF not found" >&2; exit 1; }
[[ -d "$SISTER" ]] || { echo "error: sister dir not found: $SISTER (override with SISTER=/path)" >&2; exit 1; }

# First non-blank line is the anchor of the set (normally the rule file).
first="$(grep -m1 -v '^[[:space:]]*$' "$PRDIFF" || true)"
if [[ -z "$first" ]]; then
  echo "docs/pr_diff.md is empty — nothing left to do."
  exit 0
fi

# Derive the base rule name from the anchor's filename.
fname="${first##*/}"
stem="${fname%.exs}"; stem="${stem%.ex}"
if [[ "$stem" == *_test ]]; then
  base="${stem%_test}"
  for q in _check _fix _analyze; do base="${base%"$q"}"; done
else
  base="$stem"
fi

# Matching test files = list entries under test/ whose basename is exactly one
# of the known test-file shapes for this base. Matching by exact basename keeps
# a base like "no_filter" from grabbing "no_filter_then_map_test.exs".
mapfile -t tests < <(
  grep '^test/' "$PRDIFF" | while IFS= read -r line; do
    case "${line##*/}" in
      "${base}_test.exs"|"${base}_check_test.exs"|"${base}_fix_test.exs"|"${base}_analyze_test.exs")
        printf '%s\n' "$line" ;;
    esac
  done
)

echo "set: ${base}"

copied=0; missing=0
declare -A seen=()
for rel in "$first" "${tests[@]}"; do
  [[ -n "${seen[$rel]:-}" ]] && continue
  seen[$rel]=1

  src="$SISTER/$rel"
  dst="$REPO/$rel"
  if [[ -f "$src" ]]; then
    mkdir -p "$(dirname "$dst")"
    cp "$src" "$dst"
    echo "  copied   $rel"
    copied=$((copied + 1))
  else
    echo "  MISSING  $rel  (not found in $SISTER)" >&2
    missing=$((missing + 1))
  fi
done

remaining="$(grep -c -v '^[[:space:]]*$' "$PRDIFF" || true)"
echo "copied ${copied} file(s)$([[ $missing -gt 0 ]] && echo ", ${missing} missing")  —  ${remaining} line(s) left in pr_diff.md"
