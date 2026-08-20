#!/usr/bin/env bash
#
# selftest_manifest.sh — end-to-end tests of the REVIEW side's scheduling:
# generate_manifest.sh's universe and its --refresh merge, the test-row gate,
# and requeue.sh. Sibling of selftest.sh, which covers the fix pipeline.
#
# Both use the same shape: throwaway git repos under $TMPDIR, a stubbed `claude`
# on PATH, and nothing that touches this repo.
#
# What is deliberately NOT covered: the quality of real review sessions, and the
# session sandbox (review sessions are not actually sandboxed — see README).
#
# Usage: selftest_manifest.sh     exits 0 iff every scenario passes
set -uo pipefail

SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/pr_review_selftest_manifest.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

PASS=0; FAIL=0; CURRENT=""; R=""

ok()  { PASS=$((PASS + 1)); }
bad() { FAIL=$((FAIL + 1)); printf 'FAIL [%s] %s\n' "$CURRENT" "$1"; }
assert() { local desc="$1"; shift; if "$@" >/dev/null 2>&1; then ok; else bad "$desc"; fi; }
assert_m() { # description, jq filter that must yield true against manifest.json
  local desc="$1" filter="$2"
  if jq -e "$filter" "$R/maintainer_tools/pr_review/manifest.json" 2>/dev/null | grep -q '^true$'
  then ok; else bad "$desc"; fi
}
pr() { printf '%s' "$R/maintainer_tools/pr_review"; }

# make_repo <name> — a repo with `main` and a `campaign` branch that adds one
# syntax rule, two of its tests, one unrelated test, and one doc.
make_repo() {
  R="$WORK/$1"
  mkdir -p "$R"/{lib/syntax,test/syntax,docs,maintainer_tools/pr_review,maintainer_tools/stage_1_promote_fixable_rules,bin}
  git -C "$R" init -q -b main
  git -C "$R" config user.email selftest@example.invalid
  git -C "$R" config user.name "pr_review selftest"
  printf 'placeholder\n' > "$R/README.md"
  git -C "$R" add -A && git -C "$R" commit -q -m base

  git -C "$R" checkout -q -b campaign
  printf 'defmodule Foo do\n  def foo(_), do: :ok\nend\n'        > "$R/lib/syntax/foo.ex"
  printf 'defmodule Bar do\n  def bar(_), do: :ok\nend\n'        > "$R/lib/syntax/bar.ex"
  printf '# foo fix tests\n'   > "$R/test/syntax/foo_fix_test.exs"
  printf '# foo analyze tests\n' > "$R/test/syntax/foo_analyze_test.exs"
  printf '# bar tests\n'       > "$R/test/syntax/bar_fix_test.exs"
  printf '# a meta gate\n'     > "$R/test/meta_gate_test.exs"
  printf 'docs\n'              > "$R/docs/01.md"
  cat > "$R/.gitignore" <<'EOF'
maintainer_tools/pr_review/_verdict
maintainer_tools/pr_review/_briefing/
maintainer_tools/pr_review/.review_logs/
maintainer_tools/pr_review/.lock
maintainer_tools/pr_review/.manifest.*.json
EOF
  git -C "$R" add -A && git -C "$R" commit -q -m "the PR"

  local f
  for f in generate_manifest.sh review_loop.sh requeue.sh status.sh review_file_prompt.md; do
    cp "$SRC/$f" "$(pr)/"
  done
  cp "$SRC/../stage_1_promote_fixable_rules/review_lib.sh" \
     "$R/maintainer_tools/stage_1_promote_fixable_rules/"

  # Stubbed session: writes the verdict named by SELFTEST_VERDICT.
  cat > "$R/bin/claude" <<'EOF'
#!/usr/bin/env bash
set -u
case "${SELFTEST_VERDICT:?}" in
  ok)       printf 'OK\n' > maintainer_tools/pr_review/_verdict ;;
  findings) printf 'FINDINGS\n- concern: lib/syntax/foo.ex:2 — foo/1 is wrong\n' \
              > maintainer_tools/pr_review/_verdict ;;
esac
EOF
  chmod +x "$R/bin/claude"
}

# Env goes BEFORE the call (`MAX_REREVIEWS=1 gen --refresh`); args go after.
gen() { ( cd "$(pr)" && BASE_BRANCH=main HEAD_BRANCH=campaign ./generate_manifest.sh "$@" ) ; }
review_one() { # $1 = verdict for the stub
  ( cd "$(pr)" && PATH="$R/bin:$PATH" SELFTEST_VERDICT="$1" QUIET_STATUS=1 \
      MAX_RETRIES=0 ./review_loop.sh 1 )
}

# ---- the universe and the test gate ----------------------------------------
CURRENT="gate_shape"
make_repo gate_shape
gen >/dev/null 2>&1
assert_m "rule rows are queued"          '[.files[] | select(.path == "lib/syntax/foo.ex")] | .[0].status == "pending"'
assert_m "a rule test row is gated"      '[.files[] | select(.path == "test/syntax/foo_fix_test.exs")] | .[0].status == "gated"'
assert_m "and names the rule that opens it" \
  '[.files[] | select(.path == "test/syntax/foo_fix_test.exs")] | .[0].gated_by == "lib/syntax/foo.ex"'
assert_m "both of a rule's tests are gated" \
  '[.files[] | select(.gated_by == "lib/syntax/foo.ex")] | length == 2'
assert_m "a test with no owning rule is NOT gated" \
  '[.files[] | select(.path == "test/meta_gate_test.exs")] | .[0].status == "pending" and .[0].gated_by == null'
assert_m "docs are not gated"            '[.files[] | select(.path == "docs/01.md")] | .[0].status == "pending"'
assert_m "rows start at zero re-reviews" '[.files[] | select(.rereviews != 0)] | length == 0'

# The queue must not hand out a gated row.
CURRENT="gated_rows_are_not_queued"
assert_m "the first pending row is a rule, not a test" \
  'first(.files[] | select(.status == "pending")) | .path | startswith("lib/")'

# ---- a rule review with findings opens its tests ---------------------------
CURRENT="findings_opens_tests"
review_one findings >/dev/null 2>&1
assert_m "the rule row is done"          '[.files[] | select(.path == "lib/syntax/bar.ex" or .path == "lib/syntax/foo.ex") | select(.status == "done")] | length == 1'
REVIEWED="$(jq -r 'first(.files[] | select(.status == "done")) | .path' "$(pr)/manifest.json")"
assert "a rule was reviewed first" test "${REVIEWED#lib/}" != "$REVIEWED"
assert_m "its tests are now queued" \
  "[.files[] | select(.gated_by == \"$REVIEWED\")] | length > 0 and all(.status == \"pending\")"

# ---- a clean rule review leaves its tests gated ----------------------------
CURRENT="ok_leaves_tests_gated"
make_repo ok_leaves_tests_gated
gen >/dev/null 2>&1
review_one ok >/dev/null 2>&1
REVIEWED="$(jq -r 'first(.files[] | select(.status == "done")) | .path' "$(pr)/manifest.json")"
# `all` over an empty selection is true, so the length check is what stops this
# passing on a build that never gated anything in the first place.
assert_m "an OK rule leaves its tests gated" \
  "[.files[] | select(.gated_by == \"$REVIEWED\")] | length > 0 and all(.status == \"gated\")"

# ---- requeue --gated is the escape hatch -----------------------------------
CURRENT="requeue_gated"
GATED_BEFORE="$(jq '[.files[] | select(.status == "gated")] | length' "$(pr)/manifest.json")"
assert "there were gated rows to open" test "$GATED_BEFORE" -gt 0
( cd "$(pr)" && ./requeue.sh --gated ) >/dev/null 2>&1
assert_m "requeue --gated opens every one" '[.files[] | select(.status == "gated")] | length == 0'
assert_m "and does not disturb the done row" '[.files[] | select(.status == "done")] | length == 1'

# ---- MAX_REREVIEWS: one verification pass, then the row settles -------------
# A fix changing a reviewed file sends it back ONCE. The second change leaves it
# `done` with stale: true — visible, requeue-able, not in the queue. Circling
# past that is what made every file in the 2026-08-19 run park at the fix cap.
CURRENT="rereview_cap"
make_repo rereview_cap
gen >/dev/null 2>&1
review_one findings >/dev/null 2>&1
REVIEWED="$(jq -r 'first(.files[] | select(.status == "done")) | .path' "$(pr)/manifest.json")"

echo '# fix 1' >> "$R/$REVIEWED"
git -C "$R" commit -q -am "fix 1"
MAX_REREVIEWS=1 gen --refresh >/dev/null 2>&1
assert_m "first change sends it back for verification" \
  "[.files[] | select(.path == \"$REVIEWED\")] | .[0].status == \"pending\" and .[0].stale == true and .[0].rereviews == 1"

review_one findings >/dev/null 2>&1
echo '# fix 2' >> "$R/$REVIEWED"
git -C "$R" commit -q -am "fix 2"
MAX_REREVIEWS=1 gen --refresh >/dev/null 2>&1
assert_m "second change settles the row instead of circling" \
  "[.files[] | select(.path == \"$REVIEWED\")] | .[0].status == \"done\" and .[0].stale == true and .[0].rereviews == 2"
assert_m "a settled row keeps its verdict" \
  "[.files[] | select(.path == \"$REVIEWED\")] | .[0].verdict == \"FINDINGS\""

# requeue --stale is the end-of-campaign sweep over exactly those rows.
( cd "$(pr)" && ./requeue.sh --stale ) >/dev/null 2>&1
assert_m "requeue --stale puts a settled row back" \
  "[.files[] | select(.path == \"$REVIEWED\")] | .[0].status == \"pending\""

# ---- MAX_REREVIEWS=0 and a high cap both behave -----------------------------
CURRENT="rereview_cap_bounds"
make_repo rereview_cap_bounds
gen >/dev/null 2>&1
review_one findings >/dev/null 2>&1
REVIEWED="$(jq -r 'first(.files[] | select(.status == "done")) | .path' "$(pr)/manifest.json")"
echo '# fix' >> "$R/$REVIEWED"
git -C "$R" commit -q -am fix
MAX_REREVIEWS=0 gen --refresh >/dev/null 2>&1
assert_m "MAX_REREVIEWS=0 never re-queues" \
  "[.files[] | select(.path == \"$REVIEWED\")] | .[0].status == \"done\" and .[0].stale == true"

CURRENT="rereview_cap_high"
make_repo rereview_cap_high
gen >/dev/null 2>&1
review_one findings >/dev/null 2>&1
REVIEWED="$(jq -r 'first(.files[] | select(.status == "done")) | .path' "$(pr)/manifest.json")"
echo '# fix' >> "$R/$REVIEWED"
git -C "$R" commit -q -am fix
MAX_REREVIEWS=9 gen --refresh >/dev/null 2>&1
assert_m "a high cap restores the old circling" \
  "[.files[] | select(.path == \"$REVIEWED\")] | .[0].status == \"pending\""

# ---- refresh preserves the gate ---------------------------------------------
CURRENT="refresh_preserves_gate"
make_repo refresh_preserves_gate
gen >/dev/null 2>&1
echo '# unrelated' >> "$R/docs/01.md"
git -C "$R" commit -q -am "touch docs"
gen --refresh >/dev/null 2>&1
assert_m "gated rows survive a refresh" \
  '[.files[] | select(.path == "test/syntax/foo_fix_test.exs")] | .[0].status == "gated" and .[0].gated_by == "lib/syntax/foo.ex"'

# A row opened by its rule must not be re-gated by a later refresh.
CURRENT="refresh_keeps_opened_rows_open"
review_one findings >/dev/null 2>&1
REVIEWED="$(jq -r 'first(.files[] | select(.status == "done")) | .path' "$(pr)/manifest.json")"
echo '# unrelated again' >> "$R/docs/01.md"
git -C "$R" commit -q -am "touch docs again"
gen --refresh >/dev/null 2>&1
assert_m "an opened test row stays open across a refresh" \
  "[.files[] | select(.gated_by == \"$REVIEWED\")] | all(.status != \"gated\")"

# ---- status.sh reports the new states ---------------------------------------
CURRENT="status_output"
assert "status.sh names the gated rows" \
  bash -c "cd '$(pr)' && ./status.sh | grep -q 'gated'"

echo
if (( FAIL == 0 )); then
  echo "selftest_manifest: PASS ($PASS assertions)"
else
  echo "selftest_manifest: FAIL ($FAIL failed, $PASS passed)"
  exit 1
fi
