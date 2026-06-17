#!/usr/bin/env bash
#
# generate_candidates.sh — (re)build maintainer_tools/candidates.md from the
# credence_evolution sister checkout.
#
# The queue is no longer hand-parsed. A *candidate* is a rule the evolution
# branch ADDED or CHANGED relative to `main` that has NOT yet been resolved.
# "Resolved" means the loop already decided it — there is a `<base>: accepted`
# or `<base>: followup …` commit on the current branch (or a `## <base>` section
# in followup.md). Baseline rules that evolution left untouched are NOT
# candidates (they live in `main` identically), which is what previously
# polluted the queue with ~100 already-done rules.
#
# Each pending rule is emitted as the anchored "set" review_loop.sh consumes: its
# `lib/<kind>/<base>.ex` line followed by its sister test files, grouped under
# longest-rule-base-prefix-wins (mirrors review_lib.sh's group_tests). The output
# is sorted and re-runnable; run it whenever you add rules to the evolution branch.
#
#   ./generate_candidates.sh             # overwrite candidates.md
#   ./generate_candidates.sh --dry-run   # print to stdout, write nothing
#   SISTER=/path MAIN_REF=main ./generate_candidates.sh
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$SCRIPT_DIR"/../.. && pwd)"
# shellcheck source=review_lib.sh
source "$SCRIPT_DIR/review_lib.sh"
CANDIDATES="$REPO/maintainer_tools/candidates.md"
FOLLOWUP="${FOLLOWUP:-$REPO/maintainer_tools/followup.md}"
SISTER="${SISTER:-$(cd "$REPO/.." && pwd)/credence_evolution}"
MAIN_REF="${MAIN_REF:-main}"

[[ -d "$SISTER" ]] || { echo "error: sister dir not found: $SISTER (override with SISTER=/path)" >&2; exit 1; }

dry=0
[[ "${1:-}" == "--dry-run" || "${1:-}" == "-n" ]] && dry=1

resolved_file="$(mktemp)"
out_file="$(mktemp)"
trap 'rm -f "$resolved_file" "$out_file"' EXIT

# Resolved bases: every rule the loop already decided — its commit subject is
# "<base>: accepted" / "<base>: promoted" (older accept verb) / "<base>: followup
# — …" — plus any base named in followup.md. The authoritative "already decided"
# set; subtracting it is what stops re-queuing finished rules.
{
  git -C "$REPO" log --format='%s' | sed -nE 's/^([a-z0-9_]+): (accepted|promoted|followup).*/\1/p'
  [[ -r "$FOLLOWUP" ]] && grep -hoE '^## [a-z0-9_]+' "$FOLLOWUP" | sed 's/^## //' || true
} | sort -u > "$resolved_file"

is_resolved() { grep -qxF "$1" "$resolved_file"; }

# Every sister rule base, for longest-prefix test ownership (so `no_filter` does
# not steal `no_filter_then_map`'s tests).
shopt -s nullglob
declare -a SISTER_BASES=()
for kind in pattern semantic syntax; do
  for f in "$SISTER/lib/$kind"/*.ex; do SISTER_BASES+=("$(basename "$f" .ex)"); done
done

# owns <base> <tname> — true if <base> is the longest rule base prefixing <tname>
# at an "_" boundary (i.e. <tname> belongs to <base>, not a longer sibling).
owns() {
  local base="$1" tname="$2" rb best=""
  case "$tname" in "${base}_"*) ;; *) return 1 ;; esac
  for rb in "${SISTER_BASES[@]}"; do
    case "$tname" in "${rb}_"*) ((${#rb} > ${#best})) && best="$rb" ;; esac
  done
  [[ "$best" == "$base" ]]
}

# emit_set <kind> <base> — the rule file line + its owned sister test lines.
emit_set() {
  local kind="$1" base="$2" t tname
  printf 'lib/%s/%s.ex\n' "$kind" "$base"
  for t in "$SISTER/test/$kind/${base}_"*; do
    [[ "$t" == *_test.exs ]] || continue
    tname="$(basename "$t")"
    owns "$base" "$tname" && printf 'test/%s/%s\n' "$kind" "$tname"
  done
}

# identical_to <ref-or-->  <file> — true if <file> equals the main blob (ref) or,
# with "-", reads the main blob from stdin already. Helper: compare main:rel to a path.
same_as_main() { # same_as_main <lib_rel> <path>
  git -C "$REPO" show "$MAIN_REF:$1" 2>/dev/null | diff -q - "$2" >/dev/null 2>&1
}
in_main() { git -C "$REPO" cat-file -e "$MAIN_REF:$1" 2>/dev/null; }

new=0
delta=0
for kind in pattern semantic syntax; do
  for f in "$SISTER/lib/$kind"/*.ex; do
    base="$(basename "$f" .ex)"
    lib_rel="lib/$kind/$base.ex"
    repo_file="$REPO/$lib_rel"

    is_resolved "$base" && continue

    if [[ ! -f "$repo_file" ]]; then
      # Not in the repo → a genuinely new rule still to review. (Rules that were
      # reviewed-and-rejected are also absent from the repo, but they are already
      # in `resolved` above, so only the unreviewed ones reach here.)
      new=$((new + 1))
    elif in_main "$lib_rel" && ! same_as_main "$lib_rel" "$f" && same_as_main "$lib_rel" "$repo_file"; then
      # Already in the repo, evolution CHANGED it vs main (sister≠main), and the
      # repo still holds main's version (the change hasn't been promoted) → a
      # pending delta. If the repo is identical to the sister, or ahead of it
      # (e.g. an in-tree edit), the change is already in → not a candidate.
      delta=$((delta + 1))
    else
      continue # baseline, already-promoted, or repo is ahead → nothing to do
    fi

    emit_set "$kind" "$base" >> "$out_file"
  done
done

n="$(grep -c '^lib/' "$out_file" 2>/dev/null || true)"
n="${n:-0}"

if [[ "$dry" == 1 ]]; then
  cat "$out_file"
  printf '# dry-run: %s pending set(s) — %s new, %s delta\n' "$n" "$new" "$delta" >&2
else
  cp "$out_file" "$CANDIDATES"
  printf 'wrote %s pending set(s) to maintainer_tools/candidates.md (%s new, %s delta)\n' "$n" "$new" "$delta"
fi
