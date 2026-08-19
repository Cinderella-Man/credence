#!/usr/bin/env bash
#
# selftest.sh — end-to-end tests of the fix pipeline's MECHANICS (fix_queue.sh,
# fix_loop.sh guards, campaign.sh termination) with a stubbed `claude` and a
# stubbed gate, inside throwaway git repos. Never touches this repo.
#
# What is deliberately NOT covered: the built-in mix gate (needs Elixir; the
# real campaign run covers it) and the quality of real fix sessions.
#
# Usage: selftest.sh          exits 0 iff every scenario passes
set -uo pipefail

SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/pr_review_selftest.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

PASS=0; FAIL=0; CURRENT=""

ok()   { PASS=$((PASS + 1)); }
bad()  { FAIL=$((FAIL + 1)); printf 'FAIL [%s] %s\n' "$CURRENT" "$1"; }
assert() { # description, then a command that must succeed
  local desc="$1"; shift
  if "$@" >/dev/null 2>&1; then ok; else bad "$desc"; fi
}
assert_jq() { # description, jq filter that must yield true against fixes.json
  local desc="$1" filter="$2"
  if jq -e "$filter" "$R/maintainer_tools/pr_review/fixes.json" 2>/dev/null | grep -q '^true$'; then
    ok
  else
    bad "$desc"
  fi
}

# ---- fixture repo ----------------------------------------------------------
make_repo() { # $1 = scenario name (repo dir name)
  R="$WORK/$1"
  mkdir -p "$R"
  git -C "$R" init -q -b campaign_branch
  git -C "$R" config user.email selftest@example.invalid
  git -C "$R" config user.name "pr_review selftest"

  mkdir -p "$R/lib" "$R/test" "$R/maintainer_tools/pr_review" "$R/bin"
  printf 'defmodule Foo do\n  def foo(_), do: :wrong\nend\n' > "$R/lib/foo.ex"
  printf '# test placeholder\n' > "$R/test/foo_test.exs"
  cat > "$R/.gitignore" <<'EOF'
maintainer_tools/pr_review/_fix_report
maintainer_tools/pr_review/.fix_logs/
maintainer_tools/pr_review/.fix_scratch/
maintainer_tools/pr_review/.fixes.*.json
maintainer_tools/pr_review/.lock
maintainer_tools/pr_review/.campaign.lock
maintainer_tools/pr_review/.needs_refresh
EOF
  local f
  for f in fix_loop.sh fix_queue.sh fix_file_prompt.md run_capped.sh campaign.sh status.sh; do
    cp "$SRC/$f" "$R/maintainer_tools/pr_review/"
  done

  cat > "$R/bin/claude" <<'EOF'
#!/usr/bin/env bash
# Stubbed session: ignores its arguments, acts per SELFTEST_SCENARIO. cwd is
# the repo root (fix_loop cds there before invoking claude).
set -u
PR=maintainer_tools/pr_review
case "${SELFTEST_SCENARIO:?}" in
  happy|gate_red)
    printf '  def fixed_marker, do: :ok\n' >> lib/foo.ex
    printf 'assert Foo.fixed_marker() == :ok\n' >> test/foo_test.exs
    git add lib/foo.ex test/foo_test.exs
    git commit -q -m "pr_review fix: lib/foo.ex — return :ok on empty input"
    printf 'REPORT\n- [1] fixed — reproduced with the probe, pinned in test/foo_test.exs, foo/1 now returns :ok\n- [2] refuted — read call sites and ran the battery; the name matches usage\n' > "$PR/_fix_report" ;;
  malformed)
    printf 'REPORT\n- [1] refuted — checked\n' > "$PR/_fix_report" ;;
  ledger_touch)
    echo "SESSION WAS HERE" >> "$PR/findings.md"
    printf 'REPORT\n- [1] refuted — evidence\n- [2] refuted — evidence\n' > "$PR/_fix_report" ;;
  no_commits)
    printf 'REPORT\n- [1] refuted — ran the probe, the output is correct as-is\n- [2] deferred — the name is a policy call; question: keep foo or rename battery-wide?\n' > "$PR/_fix_report" ;;
  fixed_no_commit)
    printf 'REPORT\n- [1] fixed — (dishonest: nothing was committed)\n- [2] refuted — fine\n' > "$PR/_fix_report" ;;
  pr_review_commit)
    echo poison > "$PR/stub_note.md"
    git add "$PR/stub_note.md"
    git commit -q -m "session writes where it must not"
    printf 'REPORT\n- [1] fixed — did it\n- [2] refuted — fine\n' > "$PR/_fix_report" ;;
  leftover_dirt)
    printf '  # dangling uncommitted edit\n' >> lib/foo.ex
    printf 'REPORT\n- [1] refuted — e\n- [2] refuted — e\n' > "$PR/_fix_report" ;;
  staged_ledger)
    echo "SESSION STAGES THE LEDGER" >> "$PR/findings.md"
    git add "$PR/findings.md"
    printf 'REPORT\n- [1] refuted — e\n- [2] refuted — e\n' > "$PR/_fix_report" ;;
  staged_track)
    printf '  # staged but never committed\n' >> lib/foo.ex
    git add lib/foo.ex
    printf 'REPORT\n- [1] refuted — e\n- [2] refuted — e\n' > "$PR/_fix_report" ;;
  leftover_new_file)
    printf 'the forgotten pinning test\n' > test/new_pin_test.exs
    printf 'REPORT\n- [1] refuted — e\n- [2] refuted — e\n' > "$PR/_fix_report" ;;
  merge_import)
    git merge -q --no-ff -m "merge side" side
    printf '  def own_fix, do: :ok\n' >> lib/foo.ex
    git add lib/foo.ex
    git commit -q -m "pr_review fix: lib/foo.ex — own change"
    printf 'REPORT\n- [1] fixed — did it\n- [2] refuted — fine\n' > "$PR/_fix_report" ;;
  net_zero_fixed)
    printf '  # temporary\n' >> lib/foo.ex
    git add lib/foo.ex
    git commit -q -m "pr_review fix: lib/foo.ex — change"
    git revert --no-edit HEAD >/dev/null
    printf 'REPORT\n- [1] fixed — honest-looking but net-zero\n- [2] refuted — fine\n' > "$PR/_fix_report" ;;
  *) echo "stub: unknown scenario" >&2; exit 3 ;;
esac
exit 0
EOF
  chmod +x "$R/bin/claude"

  git -C "$R" add -A
  git -C "$R" commit -q -m "initial"
  INITIAL_SHA="$(git -C "$R" rev-parse HEAD)"

  # A side branch with a foreign commit, for the merge-import scenario.
  git -C "$R" checkout -q -b side
  printf 'defmodule Bar do\nend\n' > "$R/lib/bar.ex"
  git -C "$R" add lib/bar.ex
  git -C "$R" commit -q -m "foreign work"
  git -C "$R" checkout -q campaign_branch

  jq -n --arg head "$INITIAL_SHA" --arg base "$INITIAL_SHA" '
    {schema: 1, base_branch: "main", head_branch: "campaign_branch",
     base: $base, head: $head, generated_at: "2026-08-19T09:00:00+02:00",
     files: [{path: "lib/foo.ex", origin: "added", category: "rule_syntax",
              insertions: 3, deletions: 0, blob: "x", old_path: null,
              status: "done", verdict: "FINDINGS", findings: 2,
              reviewed_at: "2026-08-19T09:10:00+02:00", stale: false, error: null}]}' \
    > "$R/maintainer_tools/pr_review/manifest.json"

  cat > "$R/maintainer_tools/pr_review/findings.md" <<'EOF'
## lib/foo.ex — 2026-08-19 (added, rule_syntax)
- concern: lib/foo.ex:2 — foo/1 returns :wrong for every input; callers branch on :ok
- nit: lib/foo.ex:2 — the name foo/1 says nothing about what it checks
- experiment: echo probe

EOF
}

run_fix() { # $1 = gate cmd, $2 = scenario
  ( cd "$R/maintainer_tools/pr_review" \
    && PATH="$R/bin:$PATH" SELFTEST_SCENARIO="$2" \
       FIX_GATE_CMD="$1" FIX_MEM_MAX= FIX_RETRY_STEP_S=0 MAX_RETRIES=1 \
       FIX_REFRESH=0 FIX_SESSION_TIMEOUT=120 \
       ./fix_loop.sh )
}

entry_status() { jq -r '.entries[0].status' "$R/maintainer_tools/pr_review/fixes.json"; }

# ---- scenarios -------------------------------------------------------------

CURRENT="sync"
make_repo sync
( cd "$R/maintainer_tools/pr_review" && ./fix_queue.sh sync ) >/dev/null
assert_jq "ledger has exactly one entry"        '.entries | length == 1'
assert_jq "severities parsed in order"          '.entries[0].severities == ["concern", "nit"]'
assert_jq "entry starts pending, round 1"       '.entries[0].status == "pending" and .entries[0].round == 1'
( cd "$R/maintainer_tools/pr_review" && ./fix_queue.sh sync ) >/dev/null
assert_jq "sync is idempotent"                  '.entries | length == 1'

CURRENT="happy"
make_repo happy
run_fix true happy >/dev/null 2>&1
assert_jq "entry done"                          '.entries[0].status == "done"'
assert_jq "outcomes recorded (fixed, refuted)"  '.entries[0].outcomes | map(.outcome) == ["fixed", "refuted"]'
assert_jq "one commit recorded"                 '.entries[0].commits | length == 1'
assert_jq "gate recorded green"                 '.entries[0].gate | startswith("green")'
assert_jq "nothing deferred"                    '.entries[0].needs_human == false'
assert "commit kept on the branch" \
  test "$(git -C "$R" rev-list --count "$INITIAL_SHA"..HEAD)" = 1
assert "resolution appended to findings.md" \
  grep -q '^## lib/foo.ex — fix round 1' "$R/maintainer_tools/pr_review/findings.md"
assert "resolution names the severity" \
  grep -q '^- \[1 concern\] fixed' "$R/maintainer_tools/pr_review/findings.md"
assert "durable refresh marker created for the accepted commits" \
  test -f "$R/maintainer_tools/pr_review/.needs_refresh"

CURRENT="gate_red"
make_repo gate_red
run_fix false gate_red >/dev/null 2>&1
assert "commits discarded (HEAD back at initial)" \
  test "$(git -C "$R" rev-parse HEAD)" = "$INITIAL_SHA"
assert "worktree file restored" git -C "$R" diff --quiet -- lib/foo.ex
assert "entry errored" test "$(entry_status)" = error
assert_jq "error names the gate"                '.entries[0].error | contains("gate")'
assert "no resolution written" \
  bash -c "! grep -q 'fix round' '$R/maintainer_tools/pr_review/findings.md'"

CURRENT="malformed"
make_repo malformed
run_fix true malformed >/dev/null 2>&1
assert "entry errored" test "$(entry_status)" = error
assert_jq "error explains the bad report"       '.entries[0].error | contains("cover findings")'
assert "HEAD untouched" test "$(git -C "$R" rev-parse HEAD)" = "$INITIAL_SHA"

CURRENT="ledger_touch"
make_repo ledger_touch
BEFORE_MD5="$(md5sum "$R/maintainer_tools/pr_review/findings.md" | cut -d' ' -f1)"
run_fix true ledger_touch >/dev/null 2>&1
assert "findings.md restored byte-for-byte" \
  test "$(md5sum "$R/maintainer_tools/pr_review/findings.md" | cut -d' ' -f1)" = "$BEFORE_MD5"
assert "entry errored" test "$(entry_status)" = error
assert_jq "error names the ledgers"             '.entries[0].error | contains("ledgers")'

CURRENT="no_commits"
make_repo no_commits
run_fix false no_commits >/dev/null 2>&1   # gate cmd would fail — must be skipped
assert "entry done (gate skipped, not run)" test "$(entry_status)" = done
assert_jq "gate recorded as skipped"            '.entries[0].gate == "skipped (no commits)"'
assert_jq "deferred flags needs_human"          '.entries[0].needs_human == true'

CURRENT="fixed_no_commit"
make_repo fixed_no_commit
run_fix true fixed_no_commit >/dev/null 2>&1
assert "entry errored" test "$(entry_status)" = error
assert_jq "error says fixed-without-commit"     '.entries[0].error | contains("committed nothing")'

CURRENT="pr_review_commit"
make_repo pr_review_commit
run_fix true pr_review_commit >/dev/null 2>&1
assert "poisoned commit discarded" test "$(git -C "$R" rev-parse HEAD)" = "$INITIAL_SHA"
assert "poisoned file gone" bash -c "! test -e '$R/maintainer_tools/pr_review/stub_note.md'"
assert "entry errored" test "$(entry_status)" = error

CURRENT="leftover_dirt"
make_repo leftover_dirt
run_fix true leftover_dirt >/dev/null 2>&1
assert "uncommitted edit reverted" git -C "$R" diff --quiet -- lib/foo.ex
assert "entry errored" test "$(entry_status)" = error
assert_jq "error names uncommitted changes"     '.entries[0].error | contains("uncommitted")'

CURRENT="staged_ledger"
make_repo staged_ledger
BEFORE_MD5="$(md5sum "$R/maintainer_tools/pr_review/findings.md" | cut -d' ' -f1)"
run_fix true staged_ledger >/dev/null 2>&1
assert "findings.md worktree restored byte-for-byte" \
  test "$(md5sum "$R/maintainer_tools/pr_review/findings.md" | cut -d' ' -f1)" = "$BEFORE_MD5"
assert "index left clean (staged ledger edit unstaged)" \
  git -C "$R" diff --cached --quiet
assert "entry errored" test "$(entry_status)" = error
assert_jq "error names the ledgers"             '.entries[0].error | contains("ledgers")'

CURRENT="staged_track"
make_repo staged_track
run_fix true staged_track >/dev/null 2>&1
assert "staged edit fully reverted (index and worktree)" \
  bash -c "[[ -z \"\$(git -C '$R' status --porcelain -- lib/foo.ex)\" ]]"
assert "entry errored" test "$(entry_status)" = error
assert_jq "error names uncommitted changes"     '.entries[0].error | contains("uncommitted")'

CURRENT="leftover_new_file"
make_repo leftover_new_file
run_fix true leftover_new_file >/dev/null 2>&1
assert "forgotten new file deleted" bash -c "! test -e '$R/test/new_pin_test.exs'"
assert "entry errored (not silently accepted)" test "$(entry_status)" = error
assert_jq "error names NEW files"               '.entries[0].error | contains("NEW files")'

CURRENT="merge_import"
make_repo merge_import
run_fix true merge_import >/dev/null 2>&1
assert "merge and own commit both discarded" \
  test "$(git -C "$R" rev-parse HEAD)" = "$INITIAL_SHA"
assert "foreign file absent" bash -c "! test -e '$R/lib/bar.ex'"
assert "entry errored" test "$(entry_status)" = error
assert_jq "error names foreign commits"         '.entries[0].error | contains("foreign")'

CURRENT="net_zero_fixed"
make_repo net_zero_fixed
run_fix true net_zero_fixed >/dev/null 2>&1
assert "commit+revert pair discarded" \
  test "$(git -C "$R" rev-parse HEAD)" = "$INITIAL_SHA"
assert "entry errored" test "$(entry_status)" = error
assert_jq "error names the net-zero effect"     '.entries[0].error | contains("net effect")'

CURRENT="ok_rereview"
make_repo ok_rereview
( cd "$R/maintainer_tools/pr_review" && ./fix_queue.sh sync ) >/dev/null
jq '.files[0].verdict = "OK" | .files[0].findings = 0 | .files[0].reviewed_at = "2026-08-19T11:00:00+02:00"' \
  "$R/maintainer_tools/pr_review/manifest.json" > "$R/maintainer_tools/pr_review/.m.tmp" \
  && mv "$R/maintainer_tools/pr_review/.m.tmp" "$R/maintainer_tools/pr_review/manifest.json"
run_fix true happy >/dev/null 2>&1
assert "no session ran against withdrawn findings" \
  test "$(git -C "$R" rev-parse HEAD)" = "$INITIAL_SHA"
assert "entry errored as superseded" test "$(entry_status)" = error
assert_jq "error says the manifest moved on"    '.entries[0].error | contains("manifest no longer carries")'

CURRENT="zero_findings_requeue"
make_repo zero_findings_requeue
jq -n '{schema: 1, entries: [
    {path: "lib/foo.ex", reviewed_at: "rz", round: 1, severities: [], status: "error",
     attempts: 0, outcomes: [], commits: [], gate: null, needs_human: false,
     error: "no severity bullets parsed", enqueued_at: "t", resolved_at: null},
    {path: "lib/gone.ex", reviewed_at: "rn", round: 1, severities: ["nit"], status: "error",
     attempts: 2, outcomes: [], commits: [], gate: null, needs_human: false,
     error: "some transient failure", enqueued_at: "t", resolved_at: null}]}' \
  > "$R/maintainer_tools/pr_review/fixes.json"
( cd "$R/maintainer_tools/pr_review" && ./fix_queue.sh requeue --errors ) >/dev/null
assert_jq "zero-findings entry stays parked"    '.entries[0].status == "error"'
assert_jq "normal error entry requeued"         '.entries[1].status == "pending"'

CURRENT="round_cap"
make_repo round_cap
( cd "$R/maintainer_tools/pr_review" \
  && jq -n '{schema: 1, entries: [
       {path: "lib/foo.ex", reviewed_at: "r1", round: 1, severities: ["concern"], status: "done",
        attempts: 1, outcomes: [], commits: [], gate: null, needs_human: false, error: null,
        enqueued_at: "t", resolved_at: "t"},
       {path: "lib/foo.ex", reviewed_at: "r2", round: 2, severities: ["concern"], status: "done",
        attempts: 1, outcomes: [], commits: [], gate: null, needs_human: false, error: null,
        enqueued_at: "t", resolved_at: "t"},
       {path: "lib/foo.ex", reviewed_at: "r3", round: 3, severities: ["concern"], status: "done",
        attempts: 1, outcomes: [], commits: [], gate: null, needs_human: false, error: null,
        enqueued_at: "t", resolved_at: "t"}]}' > fixes.json \
  && ./fix_queue.sh sync ) >/dev/null
assert_jq "round-4 entry exists"                '.entries | length == 4'
assert_jq "round cap turns it into error"       '.entries[3].status == "error" and (.entries[3].error | contains("round cap"))'

CURRENT="dirty_tree"
make_repo dirty_tree
echo "wip" >> "$R/lib/foo.ex"
if run_fix true no_commits >/dev/null 2>&1; then
  bad "fix_loop must refuse a dirty tree outside pr_review"
else
  ok
fi
git -C "$R" checkout -q -- lib/foo.ex

CURRENT="campaign_drained"
make_repo campaign_drained
run_fix true happy >/dev/null 2>&1
OUT="$( cd "$R/maintainer_tools/pr_review" \
        && PATH="$R/bin:$PATH" SELFTEST_SCENARIO=happy FIX_GATE_CMD=true \
           FIX_MEM_MAX= FIX_RETRY_STEP_S=0 FIX_REFRESH=0 ./campaign.sh 2>&1 )"
assert "campaign terminates when drained" grep -q "drained" <<<"$OUT"

# ---- verdict ---------------------------------------------------------------
echo
if (( FAIL == 0 )); then
  echo "selftest: PASS ($PASS assertions)"
else
  echo "selftest: FAIL ($FAIL failed, $PASS passed)"
  exit 1
fi
