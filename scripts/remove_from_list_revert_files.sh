#!/usr/bin/env bash
#
# remove_from_list_revert_files.sh — reject the set currently in the working tree (inverse of
# copy_next_candidate.sh).
#
# It:
#   1. figures out which rule + test files were added/modified locally
#      (uncommitted changes under lib/ and test/),
#   2. reverts those files (deletes new ones, restores modified ones to HEAD),
#   3. removes their lines from docs/candidates.md.
#
# Everything else — staged shared-file edits, docs/candidates.md's own diff — is
# left untouched. Pass file paths as args to restrict to just those instead of
# auto-detecting.
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(dirname "$SCRIPT_DIR")"
CANDIDATES="$REPO/docs/candidates.md"

[[ -f "$CANDIDATES" ]] || { echo "error: $CANDIDATES not found" >&2; exit 1; }

# Collect the set's files. Either the args given, or auto-detect: every changed
# (untracked/added/modified) path under lib/ or test/.
declare -a files=()
if [[ $# -gt 0 ]]; then
  files=("$@")
else
  while IFS= read -r line; do
    xy="${line:0:2}"
    path="${line:3}"
    case "$path" in
      lib/* | test/*) ;;
      *) continue ;;
    esac
    case "$xy" in
      '??' | 'A '* | ' A'* | 'AM' | ' M'* | 'M '* | 'MM' | 'AD' | 'MD' | 'D '* | ' D'*)
        files+=("$path") ;;
    esac
  done < <(git -C "$REPO" status --porcelain=v1)
fi

if [[ ${#files[@]} -eq 0 ]]; then
  echo "no added/modified rule/test files to drop — nothing to do."
  exit 0
fi

# 1 + 2: revert each file according to its git state.
reverted=0
for rel in "${files[@]}"; do
  xy="$(git -C "$REPO" status --porcelain=v1 -- "$rel" | head -1)"
  xy="${xy:0:2}"
  case "$xy" in
    '??')                 rm -f "$REPO/$rel";                    echo "  deleted   $rel" ;;
    'A '* | ' A'* | 'AM') git -C "$REPO" rm -f --quiet "$rel";   echo "  removed   $rel" ;;
    '')                   echo "  skipped   $rel  (no local changes)"; continue ;;
    *)                    git -C "$REPO" checkout HEAD -- "$rel"; echo "  restored  $rel" ;;
  esac
  reverted=$((reverted + 1))
done

# 3: drop the reverted files' lines from docs/candidates.md (exact whole-line match).
tmp="$(mktemp)"
printf '%s\n' "${files[@]}" > "$tmp"
before="$(grep -c -v '^[[:space:]]*$' "$CANDIDATES" || true)"
filtered="$(grep -vxF -f "$tmp" "$CANDIDATES" || true)"
printf '%s\n' "$filtered" > "$CANDIDATES"
rm -f "$tmp"
after="$(grep -c -v '^[[:space:]]*$' "$CANDIDATES" || true)"

echo "reverted ${reverted} file(s)  —  removed $((before - after)) line(s) from candidates.md, ${after} left"
