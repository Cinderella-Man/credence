#!/usr/bin/env bash
#
# remove_from_list_keep_files.sh — ACCEPT mechanic.
#
# Strip the current set's lines from docs/candidates.md — the rule line plus its
# grouped test line(s) (longest-rule-base-prefix-wins, incl. any superseded
# single <base>_test.exs) — and KEEP all files. This is the inverse of
# remove_from_list_revert_files.sh, which reverts the files as well.
#
# Anchor = the first non-blank line of candidates.md (the rule file), unless a
# rule path is passed as $1.
#
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(dirname "$SCRIPT_DIR")"
# shellcheck source=review_lib.sh
source "$SCRIPT_DIR/review_lib.sh"
CANDIDATES="$REPO/docs/candidates.md"

[[ -f "$CANDIDATES" ]] || { echo "error: $CANDIDATES not found" >&2; exit 1; }

anchor="${1:-$(grep -m1 -v '^[[:space:]]*$' "$CANDIDATES" || true)}"
[[ -n "$anchor" ]] || { echo "candidates.md empty — nothing to remove."; exit 0; }

base="$(rule_base "$anchor")"
strip="$(mktemp)"; trap 'rm -f "$strip"' EXIT
printf '%s\n' "$anchor" > "$strip"
group_tests "$base" "$CANDIDATES" >> "$strip"

before="$(grep -c -v '^[[:space:]]*$' "$CANDIDATES" || true)"
filtered="$(grep -vxF -f "$strip" "$CANDIDATES" || true)"
printf '%s\n' "$filtered" > "$CANDIDATES"
after="$(grep -c -v '^[[:space:]]*$' "$CANDIDATES" || true)"

echo "removed $((before - after)) line(s) for set '${base}', kept files; ${after} left in candidates.md."
