#!/usr/bin/env bash
#
# generate_manifest.sh — build (or --refresh) manifest.json, the tick-off list
# for the whole-PR review. The universe is every file changed between
# merge-base(BASE_BRANCH, HEAD_BRANCH) and HEAD_BRANCH, PLUS every current rule
# file (lib/{syntax,semantic,pattern}/*.ex) even if the PR never touched it.
#
# The base/head SHAs are FROZEN into the manifest, so committing review
# progress (which moves the branch tip) does not change the universe.
#
# Usage: generate_manifest.sh [--dry-run | --refresh]
#   --dry-run   print the would-be rows (TSV) + counts, write nothing
#   --refresh   recompute against the CURRENT tips and merge: same-blob entries
#               keep their status/verdict; reviewed entries whose blob changed
#               go back to pending with stale=true, up to MAX_REREVIEWS times;
#               new files enter as pending (or `gated`, see gated_by)
# Env: BASE_BRANCH (main), HEAD_BRANCH (evolution_accepted)
#      MAX_REREVIEWS (1) — how many times a file may be sent BACK to review
#        after a fix changed it. 1 = the reviewer verifies the fixer's work
#        once, then the row settles with stale: true. Set higher to restore the
#        old behaviour of circling until the fix round cap fires.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$SCRIPT_DIR"/../.. && pwd)"
# shellcheck source=../stage_1_promote_fixable_rules/review_lib.sh
source "$SCRIPT_DIR/../stage_1_promote_fixable_rules/review_lib.sh"

MANIFEST="$SCRIPT_DIR/manifest.json"
BASE_BRANCH="${BASE_BRANCH:-main}"
HEAD_BRANCH="${HEAD_BRANCH:-evolution_accepted}"
MAX_REREVIEWS="${MAX_REREVIEWS:-1}"

MODE=build
case "${1:-}" in
  --dry-run) MODE=dry ;;
  --refresh) MODE=refresh ;;
  '') ;;
  *) echo "usage: generate_manifest.sh [--dry-run | --refresh]" >&2; exit 2 ;;
esac

die() { printf '[generate_manifest] FATAL: %s\n' "$*" >&2; exit 1; }

[[ "$MODE" == build && -f "$MANIFEST" ]] \
  && die "manifest.json exists — use --refresh to merge, or delete it to start over"
[[ "$MODE" == refresh && ! -f "$MANIFEST" ]] \
  && die "--refresh needs an existing manifest.json"

if [[ "$MODE" != dry ]]; then
  exec 9>"$SCRIPT_DIR/.lock"
  flock -n 9 || die "review_loop is running — stop it before regenerating the manifest"
fi

HEAD_SHA="$(git -C "$REPO" rev-parse "$HEAD_BRANCH")"
BASE_SHA="$(git -C "$REPO" merge-base "$BASE_BRANCH" "$HEAD_BRANCH")"

# category <path> — the review category (drives ordering + the prompt's lens).
category() {
  case "$1" in
    lib/syntax/*)       echo rule_syntax ;;
    lib/semantic/*)     echo rule_semantic ;;
    lib/pattern/*)      echo rule_pattern ;;
    test/syntax/*)      echo test_syntax ;;
    test/semantic/*)    echo test_semantic ;;
    test/pattern/*)     echo test_pattern ;;
    lib/*)              echo lib_core ;;
    test/*)             echo test_other ;;
    maintainer_tools/*) echo tooling ;;
    .github/*)          echo ci ;;
    docs/*)             echo docs ;;
    *)                  echo other ;;
  esac
}

# prio <category> — block order of the campaign.
prio() {
  case "$1" in
    rule_syntax) echo 10 ;;   test_syntax) echo 10 ;;
    rule_semantic) echo 20 ;; test_semantic) echo 20 ;;
    rule_pattern) echo 30 ;;  test_pattern) echo 30 ;;
    lib_core) echo 40 ;; test_other) echo 50 ;; tooling) echo 60 ;;
    ci) echo 70 ;; docs) echo 80 ;; *) echo 90 ;;
  esac
}

# sort_key <path> <category> — "prio|group|sub|path". For rule kinds the group
# is the rule base and the rule file sorts immediately before its own tests.
sort_key() {
  local path="$1" cat="$2" p g='' s=0
  p="$(prio "$cat")"
  case "$cat" in
    rule_*)  g="$(rule_base "$path")"; s=0 ;;
    test_syntax|test_semantic|test_pattern) g="$(rule_base "$path")"; s=1 ;;
  esac
  printf '%s|%s|%s|%s' "$p" "$g" "$s" "$path"
}

# gated_by <path> <category> — the rule file whose review decides whether this
# test row is worth reviewing, or "" for rows that are never gated.
#
# Measured over the 2026-08-19 run: 21 reviews of `lib/` rule files produced 14
# blockers; 22 reviews of `test/` files produced ZERO — 8 concerns and 33 nits.
# Test files are 392 of the 780 rows, half the universe, and no blocker has ever
# come out of one. So a rule's tests are queued when the rule's own review comes
# back with findings, and left gated when it comes back OK.
#
# Only per-rule test files are gated. `test_other` (meta-gates, test/support,
# whole-suite tests) has no owning rule and stays in the queue unconditionally.
#
# This is a scheduling bet, not a claim that test files are clean: a vacuous test
# masks another defect, which is the blocker definition. It is a bet that the
# rule's own review is the cheaper place to notice. `requeue.sh --gated` opens
# the whole set when the rule pass is done.
gated_by() {
  local path="$1" cat="$2" kind base rule
  case "$cat" in
    test_syntax|test_semantic|test_pattern) kind="${cat#test_}" ;;
    *) return 0 ;;
  esac
  base="$(rule_base "$path")"
  rule="lib/$kind/$base.ex"
  git -C "$REPO" cat-file -e "$HEAD_SHA:$rule" 2>/dev/null && printf '%s' "$rule"
  return 0
}

# numstat_for <origin> <path> <old_path> — echo "ins<TAB>del" ("-" for binary).
numstat_for() {
  local origin="$1" path="$2" old="$3" line
  if [[ "$origin" == unchanged_rule ]]; then printf '0\t0'; return; fi
  if [[ "$origin" == renamed ]]; then
    line="$(git -C "$REPO" -c core.quotePath=false diff --numstat -M \
              "$BASE_SHA".."$HEAD_SHA" -- "$old" "$path" | head -n1)"
  else
    line="$(git -C "$REPO" -c core.quotePath=false diff --numstat \
              "$BASE_SHA".."$HEAD_SHA" -- "$path" | head -n1)"
  fi
  printf '%s\t%s' "$(cut -f1 <<<"$line")" "$(cut -f2 <<<"$line")"
}

blob_for() { # <origin> <path> — blob sha at HEAD_SHA ("-" for deleted files)
  local origin="$1" path="$2"
  if [[ "$origin" == deleted ]]; then printf -- '-'; else
    git -C "$REPO" rev-parse "$HEAD_SHA:$path"
  fi
}

# ---- gather rows -----------------------------------------------------------
# TSV per row: sort_key \t path \t origin \t category \t ins \t del \t blob \t old_path \t gated_by
rows() {
  local st p1 p2 path old origin cat nd
  declare -A changed=()

  while IFS=$'\t' read -r st p1 p2; do
    old=''
    case "$st" in
      A)  origin=added;    path="$p1" ;;
      M)  origin=modified; path="$p1" ;;
      D)  origin=deleted;  path="$p1" ;;
      R*) origin=renamed;  path="$p2"; old="$p1" ;;
      C*) origin=added;    path="$p2" ;;
      *)  die "unhandled name-status '$st' for '$p1'" ;;
    esac
    case "$path" in
      # The campaign's own ledgers churn with every session; as rows they
      # would be perpetual worktree-mismatch errors after any --refresh.
      maintainer_tools/pr_review/manifest.json | \
      maintainer_tools/pr_review/findings.md | \
      maintainer_tools/pr_review/fixes.json) continue ;;
    esac
    changed["$path"]=1
    cat="$(category "$path")"
    nd="$(numstat_for "$origin" "$path" "$old")"
    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
      "$(sort_key "$path" "$cat")" "$path" "$origin" "$cat" "$nd" \
      "$(blob_for "$origin" "$path")" "$old" "$(gated_by "$path" "$cat")"
  done < <(git -C "$REPO" -c core.quotePath=false diff --name-status -M \
             "$BASE_SHA".."$HEAD_SHA")

  # Every rule the PR did NOT touch, at the frozen head.
  while IFS= read -r path; do
    [[ -n "${changed[$path]:-}" ]] && continue
    cat="$(category "$path")"
    printf '%s\t%s\t%s\t%s\t0\t0\t%s\t\t%s\n' \
      "$(sort_key "$path" "$cat")" "$path" unchanged_rule "$cat" \
      "$(blob_for unchanged_rule "$path")" "$(gated_by "$path" "$cat")"
  done < <(git -C "$REPO" ls-tree -r --name-only "$HEAD_SHA" -- \
             lib/syntax lib/semantic lib/pattern | grep '\.ex$')
}

SORTED="$(rows | LC_ALL=C sort -t$'\t' -k1,1)"
BODY="$(cut -f2- <<<"$SORTED")"

if [[ "$MODE" == dry ]]; then
  printf '%s\n' "$BODY"
  echo "---" >&2
  printf 'total: %s\n' "$(wc -l <<<"$BODY")" >&2
  cut -f2 <<<"$BODY" | sort | uniq -c | sort -rn >&2
  exit 0
fi

NEW_JSON="$(jq -Rn \
  --arg base_branch "$BASE_BRANCH" --arg head_branch "$HEAD_BRANCH" \
  --arg base "$BASE_SHA" --arg head "$HEAD_SHA" --arg ts "$(date -Is)" '
  {schema: 1, base_branch: $base_branch, head_branch: $head_branch,
   base: $base, head: $head, generated_at: $ts,
   files: [inputs | split("\t") |
     {path: .[0], origin: .[1], category: .[2],
      insertions: (.[3] | tonumber? // null),
      deletions:  (.[4] | tonumber? // null),
      blob: .[5],
      old_path: (if (.[6] // "") == "" then null else .[6] end),
      gated_by: (if (.[7] // "") == "" then null else .[7] end),
      status: (if (.[7] // "") == "" then "pending" else "gated" end),
      verdict: null, findings: 0, rereviews: 0,
      reviewed_at: null, stale: false, error: null}]}' <<<"$BODY")"

if [[ "$MODE" == refresh ]]; then
  NEW_JSON="$(jq --slurpfile old "$MANIFEST" --argjson max "$MAX_REREVIEWS" '
    ($old[0].files | map({key: .path, value: .}) | from_entries) as $idx |
    .files |= map(
      ($idx[.path] // null) as $prev |
      # keep_status — whether to carry the old row.status over, or adopt the
      # freshly computed one. Adopting matters exactly once, for a manifest
      # generated before `gated_by` existed: its never-reviewed test rows are
      # `pending` and must migrate to `gated`. A row that already has the key
      # has been through this logic, so its status is authoritative — that is
      # what stops a refresh RE-GATING a row its rule already opened.
      def keep_status($prev):
        if ($prev | has("gated_by")) then {status: $prev.status}
        elif $prev.status == "pending" then {}
        else {status: $prev.status} end;

      if $prev == null then .
      elif $prev.blob == .blob then
        . + {verdict: $prev.verdict,
             findings: $prev.findings, reviewed_at: $prev.reviewed_at,
             stale: $prev.stale, rereviews: ($prev.rereviews // 0),
             error: $prev.error}
          + keep_status($prev)
      elif $prev.status == "done" then
        # Reviewed, then a fix changed it. Send it back for ONE verification
        # pass — that is where 6 of the 7 blockers repaired in the 2026-08-19
        # run were found. Sending it back a THIRD and FOURTH time is the loop
        # that never converged: the re-review is a fresh full review, a freshly
        # rewritten file reliably yields something, and every file ended parked
        # at the fix round cap.
        #
        # Past the cap the row keeps its verdict and carries stale: true —
        # visible in status.sh, not in the queue. `requeue.sh --stale` is the
        # end-of-campaign sweep over exactly the files that actually changed.
        # gated_by takes the FRESHLY computed value, never the one from $prev: a manifest
        # written before the gate existed has no such key, and carrying that
        # null onto a row this branch may leave `gated` strands it — nothing
        # would ever match it to open it again.
        (($prev.rereviews // 0) + 1) as $n |
        . + {stale: true, rereviews: $n}
          + (if $n > $max
             then {status: "done", verdict: $prev.verdict,
                   findings: $prev.findings, reviewed_at: $prev.reviewed_at,
                   error: $prev.error}
             else {} end)
      # Not yet reviewed and the blob moved: nothing to preserve but the
      # scheduling state. gated_by takes the freshly computed value.
      else . + {rereviews: ($prev.rereviews // 0)} + keep_status($prev) end)' <<<"$NEW_JSON")"
fi

TMP="$(mktemp "$SCRIPT_DIR/.manifest.XXXXXX.json")"
printf '%s\n' "$NEW_JSON" > "$TMP"
mv "$TMP" "$MANIFEST"

jq -r '"manifest.json: \(.files | length) files  (base \(.base[0:9]) → head \(.head[0:9]))",
       "  by origin:   \(.files | group_by(.origin)   | map("\(.[0].origin) \(length)")   | join(", "))",
       "  by status:   \(.files | group_by(.status)   | map("\(.[0].status) \(length)")   | join(", "))"' \
  "$MANIFEST"
