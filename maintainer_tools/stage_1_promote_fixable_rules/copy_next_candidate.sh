#!/usr/bin/env bash
#
# copy_next_candidate.sh — fetch the next review "set" from the credence_evolution sister
# checkout into this repo.
#
# A "set" is the FIRST file listed in maintainer_tools/candidates.md (the rule file) plus any
# of its test files that also appear in the list. Each file is copied from the
# sister checkout into the same relative path here (nested dirs preserved).
#
# It does NOT modify maintainer_tools/candidates.md — that list is your progress tracker, so
# remove a set's lines yourself once you've finished reviewing it. Running this
# again then picks up the new first line.
#
# Sister checkout defaults to ../credence_evolution; override with SISTER=/path.
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$SCRIPT_DIR"/../.. && pwd)"
# shellcheck source=review_lib.sh
source "$SCRIPT_DIR/review_lib.sh"
CANDIDATES="$REPO/maintainer_tools/candidates.md"
SISTER="${SISTER:-$(cd "$REPO/.." && pwd)/credence_evolution}"

[[ -f "$CANDIDATES" ]] || { echo "error: $CANDIDATES not found" >&2; exit 1; }
[[ -d "$SISTER" ]] || { echo "error: sister dir not found: $SISTER (override with SISTER=/path)" >&2; exit 1; }

# First non-blank line is the anchor of the set (normally the rule file).
first="$(grep -m1 -v '^[[:space:]]*$' "$CANDIDATES" || true)"
if [[ -z "$first" ]]; then
  echo "maintainer_tools/candidates.md is empty — nothing left to do."
  exit 0
fi

# Derive the base rule name and its grouped test files (longest-rule-base-prefix
# -wins; see review_lib.sh). Captures multi-variant tests while stopping a short
# base from stealing a longer base's tests.
base="$(rule_base "$first")"
mapfile -t tests < <(group_tests "$base" "$CANDIDATES")

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

remaining="$(grep -c -v '^[[:space:]]*$' "$CANDIDATES" || true)"
echo "copied ${copied} file(s)$([[ $missing -gt 0 ]] && echo ", ${missing} missing")  —  ${remaining} line(s) left in candidates.md"
