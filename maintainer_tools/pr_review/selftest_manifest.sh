#!/usr/bin/env bash
#
# selftest_manifest.sh — end-to-end tests of the REVIEW side's scheduling:
# generate_manifest.sh's universe and its --refresh merge, the test-row gate,
# and requeue.sh. Sibling of selftest.sh, which covers the fix pipeline.
#
# Both use the same shape: throwaway git repos under $TMPDIR, a stubbed agent
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
  for f in agent_runner.sh generate_manifest.sh review_loop.sh requeue.sh status.sh review_file_prompt.md; do
    cp "$SRC/$f" "$(pr)/"
  done
  cp "$SRC/../stage_1_promote_fixable_rules/review_lib.sh" \
     "$R/maintainer_tools/stage_1_promote_fixable_rules/"

  # Stubbed session: writes the verdict named by SELFTEST_VERDICT.
  cat > "$R/bin/codex" <<'EOF'
#!/usr/bin/env bash
set -u
OUT=""
EPHEMERAL=0
SANDBOX=""
while (($#)); do
  if [[ "$1" == -o || "$1" == --output-last-message ]]; then OUT="$2"; shift 2
  elif [[ "$1" == --ephemeral ]]; then EPHEMERAL=1; shift
  elif [[ "$1" == --sandbox ]]; then SANDBOX="$2"; shift 2
  else shift
  fi
done
[[ -n "$OUT" ]] || exit 64
[[ "$EPHEMERAL" == 1 && "$SANDBOX" == read-only ]] || exit 65
case "${SELFTEST_VERDICT:?}" in
  ok)       printf 'OK\n' > "$OUT" ;;
  findings) printf 'FINDINGS\n- concern: lib/syntax/foo.ex:2 — foo/1 is wrong\n' \
              > "$OUT" ;;
esac
EOF
  chmod +x "$R/bin/codex" "$R/maintainer_tools/pr_review/agent_runner.sh"
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

# ---- migrating a manifest written before the gate existed -------------------
# This path fires exactly once per campaign and getting it wrong is silent: the
# gate would simply never apply to the 392 test rows already in the queue.
CURRENT="migrate_pregate_manifest"
make_repo migrate_pregate_manifest
gen >/dev/null 2>&1
# Forge a genuine pre-gate manifest: strip the new fields AND put every row
# back to `pending`, which is what a manifest generated before the gate existed
# actually looks like. Stripping the fields alone is not enough — the rows would
# still carry status "gated" from this generation and the migration would never
# be exercised. Mark one rule done so there is a reviewed row to leave alone.
jq '.files |= map(del(.gated_by) | del(.rereviews)
                  | if .status == "gated" then .status = "pending" else . end)
    | (.files[] | select(.path == "lib/syntax/bar.ex"))
        |= (.status = "done" | .verdict = "OK" | .reviewed_at = "t")' \
  "$(pr)/manifest.json" > "$(pr)/.m" && mv "$(pr)/.m" "$(pr)/manifest.json"
assert_m "forged manifest really has no gate" '[.files[] | select(has("gated_by"))] | length == 0'
assert_m "and no row is gated in it" '[.files[] | select(.status == "gated")] | length == 0'

gen --refresh >/dev/null 2>&1
assert_m "migration gates the untouched test rows" \
  '[.files[] | select(.path == "test/syntax/foo_fix_test.exs")] | .[0].status == "gated"'
assert_m "migration does not disturb a reviewed row" \
  '[.files[] | select(.path == "lib/syntax/bar.ex")] | .[0].status == "done" and .[0].verdict == "OK"'
assert_m "migration leaves non-rule tests queued" \
  '[.files[] | select(.path == "test/meta_gate_test.exs")] | .[0].status == "pending"'
assert_m "migration backfills rereviews" '[.files[] | select(.rereviews == null)] | length == 0'

# The invariant that makes the gate safe at all: a row can only be opened by a
# rule that names it, so a gated row without a gated_by is stranded forever.
# The re-review branch used to carry $prev.gated_by, which is absent in a
# pre-gate manifest — that null landed on rows this branch leaves gated.
CURRENT="no_stranded_gated_rows"
assert_m "no gated row is missing its opener" \
  '[.files[] | select(.status == "gated" and .gated_by == null)] | length == 0'

# The live case that produced four stranded rows: a pre-gate manifest in which a
# TEST row was already reviewed, and then a fix changed that test file. The
# re-review branch handles it, and it is the branch that may leave the row
# `gated` — so it must not carry a gated_by from a manifest that has none.
CURRENT="rereviewed_test_row_is_not_stranded"
make_repo rereviewed_test_row_is_not_stranded
gen >/dev/null 2>&1
jq '.files |= map(del(.gated_by) | del(.rereviews)
                  | if .status == "gated" then .status = "pending" else . end)
    | (.files[] | select(.path == "test/syntax/foo_fix_test.exs"))
        |= (.status = "done" | .verdict = "FINDINGS" | .findings = 1 | .reviewed_at = "t")' \
  "$(pr)/manifest.json" > "$(pr)/.m" && mv "$(pr)/.m" "$(pr)/manifest.json"
echo '# a fix touched this test' >> "$R/test/syntax/foo_fix_test.exs"
git -C "$R" commit -q -am "fix touches the test"
gen --refresh >/dev/null 2>&1
assert_m "the changed test row is not stranded" \
  '[.files[] | select(.path == "test/syntax/foo_fix_test.exs")] | .[0].gated_by == "lib/syntax/foo.ex"'
assert_m "no gated row anywhere is missing its opener" \
  '[.files[] | select(.status == "gated" and .gated_by == null)] | length == 0'

# And a second refresh must be a no-op — not a re-gate of rows already opened.
CURRENT="migration_is_idempotent"
make_repo migration_is_idempotent
gen >/dev/null 2>&1
review_one findings >/dev/null 2>&1
( cd "$(pr)" && ./requeue.sh --gated ) >/dev/null 2>&1
gen --refresh >/dev/null 2>&1
assert_m "a refresh does not re-gate opened rows" \
  '[.files[] | select(.status == "gated")] | length == 0'

# ---- status.sh reports the new states ---------------------------------------
# Its own repo: the scenario above deliberately ends with everything ungated,
# and reusing it would have this assert pass or fail on test ORDER rather than
# on what status.sh prints.
CURRENT="status_output"
make_repo status_output
gen >/dev/null 2>&1
assert_m "this repo has gated rows to report" '[.files[] | select(.status == "gated")] | length > 0'
assert "status.sh names the gated rows" \
  bash -c "cd '$(pr)' && ./status.sh | grep -q 'gated'"
assert "status.sh names the way to open them" \
  bash -c "cd '$(pr)' && ./status.sh | grep -q -- '--gated'"

echo
if (( FAIL == 0 )); then
  echo "selftest_manifest: PASS ($PASS assertions)"
else
  echo "selftest_manifest: FAIL ($FAIL failed, $PASS passed)"
  exit 1
fi
