#!/usr/bin/env bash
#
# fix_loop.sh — the FIX phase of the whole-PR review campaign. Drains the fix
# ledger (fixes.json, one entry per reviewed file whose verdict was FINDINGS):
# per entry it briefs one agent session that must, per finding, CONFIRM with an
# executed reproduction, PIN with a failing test, FIX, PROVE, and COMMIT — or
# honestly refute/defer. The session is powerful (Bash, Edit) and therefore
# untrusted; the wrapper holds the gate:
#
#   - the pr_review ledgers are hash-checked around the session and restored if
#     touched; commits that touch maintainer_tools/pr_review/ are discarded
#   - history rewrites and branch switches are refused
#   - uncommitted tracked changes left behind void the attempt
#   - the CI fast gate (format on touched files, compile --warnings-as-errors,
#     mix test --exclude corpus --exclude idempotency, tree-stays-clean) is
#     re-run INDEPENDENTLY by the wrapper; red gate = every commit of the
#     attempt is reset away and the session gets the gate tail as feedback
#
# Outcomes land in fixes.json (machine truth) and as an append-only resolution
# section in findings.md. After any accepted commits the manifest is refreshed
# (generate_manifest.sh --refresh) so fixed files re-enter review as stale and
# new test files enter as pending — the reviewer verifies the fixer's work.
#
# Usage:   fix_loop.sh [cap] [wait_min]
#   cap        max entries this run (0 = drain; default 0)
#   wait_min   minutes to sleep between entries (default 0)
# Env:
#   AGENT_PROVIDER       codex (default) | claude
#   AGENT_MODEL          optional model for both session kinds
#   FIX_AGENT_MODEL      fix-only model override
#   MAX_RETRIES          failed attempts per entry before `error` (default 2)
#   FIX_MEM_MAX          systemd MemoryMax for session AND gate (default 16G;
#                        empty string disables — see docs/21 OOM history)
#   FIX_SESSION_TIMEOUT  seconds per agent session (default 7200; 0 = none)
#   FIX_GATE_TIMEOUT     seconds per gate step (default 2400)
#   FIX_MAX_ROUNDS       review↔fix rounds per file before needs-human (3)
#   FIX_REFRESH          1 = refresh manifest after accepted commits (default 1)
#   FIX_GATE_CMD         test hook: replaces the whole built-in gate
#   FIX_RETRY_STEP_S     test hook: seconds per backoff step instead of minutes
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$SCRIPT_DIR"/../.. && pwd)"
# shellcheck source=fix_queue.sh
source "$SCRIPT_DIR/fix_queue.sh"   # functions only (fixes_*, sync_queue, …)

MANIFEST="$SCRIPT_DIR/manifest.json"
FINDINGS="$SCRIPT_DIR/findings.md"
REPORT="$SCRIPT_DIR/_fix_report"
PROMPT="$SCRIPT_DIR/fix_file_prompt.md"
AGENT_RUNNER="$SCRIPT_DIR/agent_runner.sh"
LOGDIR="$SCRIPT_DIR/.fix_logs"
BAKDIR="$LOGDIR/.bak"

CAP="${1:-0}"
WAIT_MIN="${2:-0}"
MAX_RETRIES="${MAX_RETRIES:-2}"
FIX_MEM_MAX="${FIX_MEM_MAX-16G}"
FIX_SESSION_TIMEOUT="${FIX_SESSION_TIMEOUT:-7200}"
FIX_GATE_TIMEOUT="${FIX_GATE_TIMEOUT:-2400}"
FIX_REFRESH="${FIX_REFRESH:-1}"

log() { printf '[fix_loop] %s\n' "$*"; }
die() { printf '[fix_loop] FATAL: %s\n' "$*" >&2; exit 1; }

[[ -f "$MANIFEST" ]] || die "no manifest.json — run generate_manifest.sh first"
[[ -f "$PROMPT" ]]   || die "prompt file missing: $PROMPT"
[[ -x "$AGENT_RUNNER" ]] || die "agent runner missing or not executable: $AGENT_RUNNER"
command -v jq >/dev/null || die "jq not found"
mkdir -p "$LOGDIR" "$BAKDIR"
touch "$FINDINGS"

# Refresh against the branches RECORDED in the manifest (env can override),
# never the generator's own defaults — a mismatch would rebuild the universe
# against the wrong branch. Clears the crash marker only on success.
refresh_manifest() {
  BASE_BRANCH="${BASE_BRANCH:-$(jq -r .base_branch "$MANIFEST")}" \
  HEAD_BRANCH="${HEAD_BRANCH:-$(jq -r .head_branch "$MANIFEST")}" \
    "$SCRIPT_DIR/generate_manifest.sh" --refresh && rm -f "$SCRIPT_DIR/.needs_refresh"
}

# Crash recovery: a previous run accepted commits but its manifest refresh
# never completed. Do it before taking the lock (the generator locks itself).
if [[ -f "$SCRIPT_DIR/.needs_refresh" && "$FIX_REFRESH" == 1 ]]; then
  log "catching up on a manifest refresh a previous run left behind"
  refresh_manifest || die "catch-up manifest refresh failed — run generate_manifest.sh --refresh by hand"
fi

exec 9>"$SCRIPT_DIR/.lock"
flock -n 9 || die "another review_loop/fix_loop (or manifest tool) is already running"

HEAD_SHA="$(jq -r .head "$MANIFEST")"
MANIFEST_HEAD_BRANCH="$(jq -r .head_branch "$MANIFEST")"
git -C "$REPO" merge-base --is-ancestor "$HEAD_SHA" HEAD \
  || die "current checkout does not descend from the manifest's frozen head ${HEAD_SHA:0:9} — wrong branch?"

# Memory ceiling for the session and the gate: the OOM history is unbounded
# compiles (docs/21), and fix sessions compile.
CAPPED=()
if [[ -n "$FIX_MEM_MAX" ]]; then
  if command -v systemd-run >/dev/null 2>&1 \
     && systemd-run --user --scope -q -p MemoryMax="$FIX_MEM_MAX" true 2>/dev/null; then
    CAPPED=(systemd-run --user --scope -q -p MemoryMax="$FIX_MEM_MAX" -p MemorySwapMax=0 --)
  else
    log "warning: systemd-run unavailable — sessions and gate run UNCAPPED"
  fi
fi

FIXLOG=""
flog() { [[ -n "$FIXLOG" ]] && printf '[%s] %-9s %s\n' "$(date +%H:%M:%S)" "$1" "${*:2}" >> "$FIXLOG"; return 0; }

tree_state() { git -C "$REPO" status --porcelain=v1 | LC_ALL=C sort; }
owned_hash() { cat "$MANIFEST" "$FINDINGS" "$FIXES" 2>/dev/null | md5sum; }

# remove_new_untracked <baseline tree_state> — delete untracked files that
# appeared since the baseline (outside pr_review). A red gate's own suite run
# can create artifacts; left behind they would fail every later gate's
# tree-clean step and wedge the rest of the run.
remove_new_untracked() {
  local line xy p
  while IFS= read -r line; do
    [[ -n "$line" ]] || continue
    xy="${line:0:2}"; p="${line:3}"
    [[ "$xy" == '??' ]] || continue
    case "$p" in maintainer_tools/pr_review/*) continue ;; esac
    if [[ "$p" == */ ]]; then rm -rf -- "${REPO:?}/${p%/}"; else rm -f -- "$REPO/$p"; fi
    flog GUARD "removed leftover untracked artifact: $p"
  done < <(LC_ALL=C comm -13 <(printf '%s' "$1") <(tree_state))
}

# verify_restored <baseline tree_state> — after cleanup, the tree must be
# byte-identical (porcelain-wise) to the pre-session state; anything else is a
# state we do not understand, and continuing would compound it.
verify_restored() {
  [[ "$(tree_state)" == "$1" ]] \
    || die "tree not restored to the pre-session state — inspect 'git status' before rerunning"
}

next_pending_fix() {
  jq -r 'first(.entries[] | select(.status == "pending")) // empty
         | [.path, .reviewed_at, (.round | tostring), (.severities | join(","))] | @tsv' "$FIXES"
}

# ledger_safe_reset <sha> — reset --hard without losing the campaign ledgers,
# which are dirty (or untracked) in the worktree for the whole campaign.
ledger_safe_reset() {
  local b="$BAKDIR/reset"
  mkdir -p "$b"
  cp "$MANIFEST" "$b/manifest.json"
  cp "$FINDINGS" "$b/findings.md"
  [[ -f "$FIXES" ]] && cp "$FIXES" "$b/fixes.json"
  git -C "$REPO" reset --hard -q "$1" || die "git reset --hard $1 failed — inspect the tree"
  cp "$b/manifest.json" "$MANIFEST"
  cp "$b/findings.md" "$FINDINGS"
  [[ -f "$b/fixes.json" ]] && cp "$b/fixes.json" "$FIXES"
  return 0
}

# ---- briefing --------------------------------------------------------------
build_fix_briefing() { # path round sevs_csv feedback
  local path="$1" round="$2" sevs_csv="$3" feedback="$4"
  local -a sevs; IFS=',' read -ra sevs <<<"$sevs_csv"
  {
    echo "# Fix briefing"
    echo "File under fix: $path"
    echo "Fix round: $round (cap $FIX_MAX_ROUNDS — after a fix lands, the file is re-reviewed)"
    echo
    echo "The reviewer's findings, verbatim from findings.md:"
    echo '~~~'
    findings_section "$path"
    echo '~~~'
    echo "The findings are numbered in order of their \`- blocker:/- concern:/- nit:\` bullets:"
    local i
    for i in "${!sevs[@]}"; do echo "  [$((i + 1))] ${sevs[$i]}"; done
    echo "(\`- experiment:\` bullets are the reviewer's suggested reproductions — hints, not findings.)"
    if (( round > 1 )); then
      echo
      echo "This is round $round: earlier fix rounds for this file are recorded in"
      echo "findings.md under '## $path — fix round …'. Read them before repeating work."
    fi
    if [[ -n "$feedback" ]]; then
      echo
      echo "## Your previous attempt FAILED"
      echo "$feedback"
      echo
      echo "Every commit of that attempt was discarded; the tree is back to the"
      echo "pre-attempt state. Address the cause before anything else."
    fi
  }
}

# ---- session ---------------------------------------------------------------
# The agent never runs in the maintainer's checkout. It receives a temporary
# branch in a linked worktree at pre_sha. Only a clean, linear set of commits
# produced during the attempt is validated and committed by the wrapper; every
# other artifact is destroyed with the worktree.
SESSION_ISOLATION_FAIL=""
SESSION_GATE_DESC=""
ACTIVE_FIX_WORKTREE=""
ACTIVE_FIX_BRANCH=""
cleanup_fix_worktree() {
  local rc=0
  if [[ -n "$ACTIVE_FIX_WORKTREE" ]]; then
    git -C "$REPO" worktree remove --force "$ACTIVE_FIX_WORKTREE" >/dev/null 2>&1 || rc=1
  fi
  if [[ -n "$ACTIVE_FIX_BRANCH" ]]; then
    git -C "$REPO" branch -D "$ACTIVE_FIX_BRANCH" >/dev/null 2>&1 || rc=1
  fi
  ACTIVE_FIX_WORKTREE=""
  ACTIVE_FIX_BRANCH=""
  return "$rc"
}
trap cleanup_fix_worktree EXIT

run_fix_session() { # $1 = briefing, $2 = pre_sha, $3 = path, $4 = round, $5 = n_findings
  local prompt rc=0 pre_sha="$2" target_path="$3" round="$4" n_findings="$5"
  prompt="$(cat "$PROMPT")"$'\n\n'"$1"
  SESSION_ISOLATION_FAIL=""
  SESSION_GATE_DESC=""

  local worktree branch
  worktree="$(mktemp -d "${TMPDIR:-/tmp}/pr-review-fix.XXXXXX")"
  rmdir "$worktree"
  branch="pr-review-attempt-$$-${RANDOM}"
  ACTIVE_FIX_WORKTREE="$worktree"
  ACTIVE_FIX_BRANCH="$branch"
  if ! git -C "$REPO" worktree add -q -b "$branch" "$worktree" "$pre_sha"; then
    cleanup_fix_worktree || true
    SESSION_ISOLATION_FAIL="could not create the disposable fix worktree"
    return 70
  fi

  flog SESSION "starting ${AGENT_PROVIDER:-codex} (model=${FIX_AGENT_MODEL:-${AGENT_MODEL:-default}}, timeout=${FIX_SESSION_TIMEOUT}s, mem=${FIX_MEM_MAX:-uncapped})"
  flog SESSION "disposable worktree: $worktree ($branch at ${pre_sha:0:9})"
  flog SESSION "----- agent transcript -----"
  # timeout runs INSIDE the memory scope so its kill reaches the session.
  ( cd "$worktree" && printf '%s' "$prompt" | "${CAPPED[@]}" timeout -k 60 "$FIX_SESSION_TIMEOUT" \
      env AGENT_REPO="$worktree" "$AGENT_RUNNER" fix "$REPORT" ) \
    >> "$FIXLOG" 2>&1 9>&- || rc=$?
  flog SESSION "----- end transcript (agent exit=${rc}) -----"

  local wt_branch wt_commits dirt
  wt_branch="$(git -C "$worktree" rev-parse --abbrev-ref HEAD 2>/dev/null || true)"
  if [[ "$wt_branch" != "$branch" ]]; then
    SESSION_ISOLATION_FAIL="the session switched branches inside its disposable worktree"
  elif ! git -C "$worktree" merge-base --is-ancestor "$pre_sha" HEAD; then
    SESSION_ISOLATION_FAIL="the session rewrote history inside its disposable worktree"
  fi

  wt_commits="$(git -C "$worktree" rev-list --reverse "$pre_sha"..HEAD 2>/dev/null || true)"
  [[ -z "$SESSION_ISOLATION_FAIL" && -n "$wt_commits" ]] \
    && SESSION_ISOLATION_FAIL="the agent created commits; only the wrapper may commit a fix attempt"

  dirt="$(git -C "$worktree" status --porcelain=v1)"
  if [[ -z "$SESSION_ISOLATION_FAIL" ]] && grep -q 'maintainer_tools/pr_review/' <<<"$dirt"; then
    SESSION_ISOLATION_FAIL="the session changed campaign files under maintainer_tools/pr_review/"
  fi

  local has_changes=0
  [[ -n "$dirt" ]] && has_changes=1
  if [[ -z "$SESSION_ISOLATION_FAIL" ]]; then
    local why
    if ! why="$(validate_report "$n_findings" "$has_changes")"; then
      SESSION_ISOLATION_FAIL="unusable report: $why (agent exit=$rc)"
    fi
  fi

  if [[ -z "$SESSION_ISOLATION_FAIL" && "$has_changes" == 1 ]]; then
    local -a changed=()
    while IFS= read -r -d '' p; do changed+=("$p"); done \
      < <({ git -C "$worktree" diff --name-only -z; git -C "$worktree" diff --cached --name-only -z; git -C "$worktree" ls-files --others --exclude-standard -z; })
    mapfile -d '' -t changed < <(printf '%s\0' "${changed[@]}" | LC_ALL=C sort -zu)
    git -C "$worktree" add -- "${changed[@]}" || SESSION_ISOLATION_FAIL="wrapper could not stage the fix attempt"
    if [[ -z "$SESSION_ISOLATION_FAIL" ]]; then
      git -C "$worktree" commit -q -m "pr_review fix: $target_path — wrapper-owned round $round" \
        -m "Agent proposed the working-tree changes; the wrapper validated the report and owns this commit." \
        || SESSION_ISOLATION_FAIL="wrapper could not commit the fix attempt"
    fi
  fi

  if [[ -z "$SESSION_ISOLATION_FAIL" && "$has_changes" == 1 ]]; then
    local gatelog="$LOGDIR/$(tr '/' '__' <<<"$target_path").round${round}.worktree.gate.log"
    if run_gate "$pre_sha" "$gatelog" "$worktree"; then
      SESSION_GATE_DESC="green ($GATE_DESC)"
    else
      SESSION_ISOLATION_FAIL="the wrapper's gate is RED in the disposable worktree. Gate output tail:"$'\n'"$(tail -n 40 "$gatelog")"
    fi
  elif [[ -z "$SESSION_ISOLATION_FAIL" ]]; then
    SESSION_GATE_DESC="skipped (no changes)"
  fi

  wt_commits="$(git -C "$worktree" rev-list --reverse "$pre_sha"..HEAD 2>/dev/null || true)"
  if [[ -z "$SESSION_ISOLATION_FAIL" && -n "$wt_commits" ]]; then
    if ! git -C "$REPO" cherry-pick $wt_commits >> "$FIXLOG" 2>&1; then
      git -C "$REPO" cherry-pick --abort >/dev/null 2>&1 || true
      SESSION_ISOLATION_FAIL="could not import the disposable worktree commits into the campaign branch"
    else
      flog SESSION "imported $(grep -c . <<<"$wt_commits") commit(s) from disposable worktree"
    fi
  fi

  cleanup_fix_worktree \
    || SESSION_ISOLATION_FAIL="${SESSION_ISOLATION_FAIL:-could not remove the disposable fix worktree and branch}"
  [[ -n "$SESSION_ISOLATION_FAIL" ]] && flog GUARD "$SESSION_ISOLATION_FAIL"
  return "$rc"
}

# ---- report ----------------------------------------------------------------
OUTCOME_RE='^- \[[0-9]+\] (fixed|refuted|obsolete|deferred)'

# validate_report <n_findings> <has_changes:0|1> — 0 = usable; reason on stdout.
validate_report() {
  local n="$1" has_changes="$2"
  [[ -f "$REPORT" ]] || { echo "no _fix_report was written"; return 1; }
  [[ "$(head -n1 "$REPORT")" == "REPORT" ]] \
    || { echo "_fix_report's first line is not exactly REPORT"; return 1; }
  local nums expect
  nums="$(grep -oE '^- \[[0-9]+\]' "$REPORT" | grep -oE '[0-9]+' | LC_ALL=C sort -n | tr '\n' ' ')"
  expect="$(seq 1 "$n" | tr '\n' ' ')"
  [[ "$nums" == "$expect" ]] \
    || { echo "report bullets do not cover findings 1..$n exactly once (saw: ${nums:-none})"; return 1; }
  local nvalid
  nvalid="$(grep -cE "$OUTCOME_RE" "$REPORT")"
  (( nvalid == n )) \
    || { echo "some bullets lack a valid outcome word (fixed|refuted|obsolete|deferred)"; return 1; }
  local nfixed ndeferred
  nfixed="$(grep -cE '^- \[[0-9]+\] fixed' "$REPORT")" || true
  ndeferred="$(grep -cE '^- \[[0-9]+\] deferred' "$REPORT")" || true
  if (( nfixed > 0 && has_changes == 0 )); then
    echo "report claims $nfixed finding(s) fixed but the session changed nothing"; return 1
  fi
  if (( has_changes > 0 && nfixed + ndeferred == 0 )); then
    echo "the session changed code but reports no finding as fixed or deferred — refuted/obsolete findings must not change code"; return 1
  fi
  return 0
}

# outcomes_json <sevs_csv> — the report's bullets as a JSON array on stdout.
outcomes_json() {
  local -a sevs; IFS=',' read -ra sevs <<<"$1"
  local line n o note
  while IFS= read -r line; do
    [[ "$line" =~ ^-\ \[([0-9]+)\]\ (fixed|refuted|obsolete|deferred)(.*)$ ]] || continue
    n="${BASH_REMATCH[1]}"; o="${BASH_REMATCH[2]}"
    note="$(sed -E 's/^[[:space:]]*(—|–|-|:)?[[:space:]]*//' <<<"${BASH_REMATCH[3]}")"
    jq -n --argjson n "$n" --arg sev "${sevs[$((n - 1))]:-?}" --arg o "$o" --arg note "$note" \
      '{n: $n, severity: $sev, outcome: $o, note: $note}'
  done < "$REPORT" | jq -s 'sort_by(.n)'
}

# record_resolution <path> <round> <sevs_csv> <gate_desc> <commits (space-sep)>
record_resolution() {
  local path="$1" round="$2" gate_desc="$4" commits="$5"
  local -a sevs; IFS=',' read -ra sevs <<<"$3"
  {
    echo "## $path — fix round $round ($(date +%F))"
    local line n
    while IFS= read -r line; do
      if [[ "$line" =~ ^-\ \[([0-9]+)\]\ (fixed|refuted|obsolete|deferred)(.*)$ ]]; then
        n="${BASH_REMATCH[1]}"
        echo "- [$n ${sevs[$((n - 1))]:-?}] ${BASH_REMATCH[2]}${BASH_REMATCH[3]}"
      elif [[ "$line" =~ ^-\ note: ]] || [[ "$line" =~ ^[[:space:]]+[^[:space:]] ]]; then
        echo "$line"
      fi
    done < <(tail -n +2 "$REPORT")
    [[ -n "$commits" ]] && echo "- commits: $commits"
    echo "- gate: $gate_desc"
    echo
  } >> "$FINDINGS"
}

# ---- gate ------------------------------------------------------------------
GATE_DESC="mix format (touched) · compile --warnings-as-errors · mix test --exclude corpus --exclude idempotency · tree clean"

run_gate() { # $1 = pre_sha, $2 = gate log file, $3 = repo (default primary)
  local pre="$1" gatelog="$2" gate_repo="${3:-$REPO}" rc=0
  : > "$gatelog"
  if [[ -n "${FIX_GATE_CMD:-}" ]]; then
    ( cd "$gate_repo" && timeout -k 60 "$FIX_GATE_TIMEOUT" bash -c "$FIX_GATE_CMD" ) \
      >> "$gatelog" 2>&1 || rc=$?
    return "$rc"
  fi
  local -a touched=()
  local f
  while IFS= read -r f; do
    [[ -f "$gate_repo/$f" ]] && touched+=("$f")
  done < <(git -C "$gate_repo" diff --name-only "$pre"..HEAD | grep -E '\.(ex|exs)$' || true)
  (
    cd "$gate_repo" || exit 70
    if ((${#touched[@]})); then
      echo "== mix format --check-formatted (${#touched[@]} touched files)"
      timeout -k 60 "$FIX_GATE_TIMEOUT" mix format --check-formatted "${touched[@]}" || exit 1
      # A cached _build hides warnings in already-compiled files; force the
      # touched ones (and their dependents) through the compiler again.
      touch "${touched[@]}"
    fi
    echo "== mix compile --warnings-as-errors"
    "${CAPPED[@]}" timeout -k 60 "$FIX_GATE_TIMEOUT" mix compile --warnings-as-errors || exit 1
    echo "== mix test --exclude corpus --exclude idempotency"
    "${CAPPED[@]}" timeout -k 60 "$FIX_GATE_TIMEOUT" mix test --exclude corpus --exclude idempotency || exit 1
    echo "== tree must stay clean outside pr_review (fixture healer parity with CI)"
    dirt="$(git status --porcelain=v1 -- . ':(exclude)maintainer_tools/pr_review' )"
    if [[ -n "$dirt" ]]; then
      echo "tree dirty after the suite (the fixture healer rewrote something the session should have committed canonically):"
      echo "$dirt"
      exit 1
    fi
  ) >> "$gatelog" 2>&1 || rc=$?
  return "$rc"
}

# ---- main ------------------------------------------------------------------
main() {
  fixes_init
  sync_queue

  # Fix sessions commit; anything already dirty outside pr_review would get
  # entangled with (or destroyed by) the attempt-revert machinery. Hard stop.
  local pre_dirt
  pre_dirt="$(tree_state | grep -v 'maintainer_tools/pr_review/' || true)"
  [[ -n "$pre_dirt" ]] && die "tree is dirty outside maintainer_tools/pr_review — commit or stash first:"$'\n'"$pre_dirt"

  local start_branch
  start_branch="$(git -C "$REPO" rev-parse --abbrev-ref HEAD)"
  [[ "$start_branch" == "HEAD" ]] && die "detached HEAD — check out the campaign branch first"
  [[ "$start_branch" == "$MANIFEST_HEAD_BRANCH" ]] \
    || die "checked out '$start_branch' but the campaign branch is '$MANIFEST_HEAD_BRANCH' — fix commits and the manifest refresh must land there"

  local iter=0 retry=0 prev_key="" feedback=""
  while :; do
    rm -f "$REPORT"

    local row
    row="$(next_pending_fix)"
    if [[ -z "$row" ]]; then
      log "done — no pending fix entries"
      break
    fi
    if (( CAP > 0 && iter >= CAP )); then log "cap $CAP reached"; break; fi

    local path ra round sevs_csv
    IFS=$'\t' read -r path ra round sevs_csv <<<"$row"
    local key="$path@$ra"
    [[ "$key" == "$prev_key" ]] || { retry=0; feedback=""; }
    prev_key="$key"
    local n_findings
    n_findings="$(awk -F',' '{print NF}' <<<"$sevs_csv")"

    FIXLOG="$LOGDIR/$(tr '/' '__' <<<"$path").round${round}.attempt$((retry + 1)).log"; : > "$FIXLOG"
    flog START "fixing $path (round $round, $n_findings findings)${feedback:+ [retry #$retry]}"
    log "▶ $(date '+%H:%M') fixing $path (round $round, $n_findings findings)$([[ $retry -gt 0 ]] && echo " [retry #$retry]")"

    # The manifest must still stand behind this exact review: the row exists,
    # still says FINDINGS, and was not re-reviewed since. A newer review (even
    # one that came back OK and so left no trace in the fix ledger) withdraws
    # these findings; fixing them anyway would change code nobody asked about.
    local mrow
    mrow="$(jq -r --arg p "$path" \
      'first(.files[] | select(.path == $p)) // empty | "\(.verdict)\t\(.reviewed_at)"' "$MANIFEST")"
    if [[ "$mrow" != "FINDINGS"$'\t'"$ra" ]]; then
      fixes_update "$path" "$ra" '.status = "error" | .error = "manifest no longer carries this review (re-reviewed, requeued, or dropped) — entry superseded"'
      log "✗ $path — manifest no longer carries this review, skipping"
      retry=0; prev_key=""; iter=$((iter + 1)); continue
    fi
    if (( n_findings == 0 )); then
      fixes_update "$path" "$ra" '.status = "error" | .error = "entry has no parsed findings — nothing to brief a session with"'
      log "✗ $path — no parsed findings, skipping"
      retry=0; prev_key=""; iter=$((iter + 1)); continue
    fi
    # The findings section must still parse to the same shape it was enqueued
    # with — the briefing numbers findings by it.
    local live_n
    live_n="$(section_severities "$(findings_section "$path")" | grep -c . || true)"
    if [[ "$live_n" != "$n_findings" ]]; then
      fixes_update "$path" "$ra" '.status = "error" | .error = $e' \
        --arg e "findings section changed since enqueue ($n_findings findings enqueued, $live_n now) — resync"
      log "✗ $path — findings section changed since enqueue, marked error"
      retry=0; prev_key=""; iter=$((iter + 1)); continue
    fi

    local briefing pre_sha owned_before before
    briefing="$(build_fix_briefing "$path" "$round" "$sevs_csv" "$feedback")"
    pre_sha="$(git -C "$REPO" rev-parse HEAD)"
    cp "$MANIFEST" "$BAKDIR/manifest.json"
    cp "$FINDINGS" "$BAKDIR/findings.md"
    cp "$FIXES" "$BAKDIR/fixes.json"
    owned_before="$(owned_hash)"
    before="$(tree_state)"

    local session_rc=0 session_start
    session_start="$(date +%s)"
    run_fix_session "$briefing" "$pre_sha" "$path" "$round" "$n_findings" || session_rc=$?

    local fail="$SESSION_ISOLATION_FAIL"

    # Guard 1: the campaign ledgers are the wrapper's, not the session's.
    if [[ "$(owned_hash)" != "$owned_before" ]]; then
      cp "$BAKDIR/manifest.json" "$MANIFEST"
      cp "$BAKDIR/findings.md" "$FINDINGS"
      cp "$BAKDIR/fixes.json" "$FIXES"
      fail="the session modified the campaign ledgers (manifest.json/findings.md/fixes.json) — they were restored; never touch maintainer_tools/pr_review/"
      flog GUARD "$fail"
    fi

    # Guard 2: same branch, no history rewrites.
    local cur_branch
    cur_branch="$(git -C "$REPO" rev-parse --abbrev-ref HEAD)"
    [[ "$cur_branch" == "$start_branch" ]] \
      || die "session switched branches ($start_branch → $cur_branch) — refusing to continue; inspect the tree"
    if ! git -C "$REPO" merge-base --is-ancestor "$pre_sha" HEAD; then
      ledger_safe_reset "$pre_sha"
      fail="${fail:-the session rewrote history (pre-session commit is no longer an ancestor) — all its work was discarded}"
      flog GUARD "history rewrite detected — reset to $pre_sha"
    fi

    # Guard 2b: only commits authored DURING this session are acceptable — a
    # `git merge` (or fast-forward) would import unreviewed foreign commits
    # while keeping pre_sha an ancestor. Merge commits are rejected outright;
    # linear commits must be no older than the session start (with slack).
    local n_merges oldest_ct
    n_merges="$(git -C "$REPO" rev-list --min-parents=2 --count "$pre_sha"..HEAD)"
    oldest_ct="$(git -C "$REPO" log --format=%ct "$pre_sha"..HEAD | LC_ALL=C sort -n | head -n1)"
    if (( n_merges > 0 )) || { [[ -n "$oldest_ct" ]] && (( oldest_ct < session_start - 120 )); }; then
      ledger_safe_reset "$pre_sha"
      fail="${fail:-the session imported foreign commits (a merge or fast-forward) — everything was discarded; only commits you author in this session are allowed}"
      flog GUARD "foreign/merge commits detected — reset to $pre_sha"
    fi

    # Guard 3: NO commit may touch the campaign's own directory — checked
    # per-commit (git log --name-only), not as a net diff, so a touch-then-
    # revert pair cannot slip a ledger edit through.
    local commits n_commits
    commits="$(git -C "$REPO" rev-list --reverse "$pre_sha"..HEAD)"
    n_commits="$(grep -c . <<<"$commits" || true)"
    if (( n_commits > 0 )) \
       && git -C "$REPO" log --format= --name-only "$pre_sha"..HEAD | grep -q '^maintainer_tools/pr_review/'; then
      ledger_safe_reset "$pre_sha"
      commits=""; n_commits=0
      fail="${fail:-a commit of the session touched maintainer_tools/pr_review/ — all its commits were discarded}"
      flog GUARD "commits touched pr_review — reset to $pre_sha"
    fi

    # Guard 4: no uncommitted leftovers of ANY kind. Tracked modifications and
    # staged changes are restored from HEAD — never from the index, which the
    # session may have poisoned with `git add` (a plain `git checkout -- p`
    # would write the staged bad content into the worktree, clobbering e.g.
    # Guard 1's ledger restore). New files are deleted. All three void the
    # attempt: a forgotten `git add` of a pinning test must fail loudly, not
    # vanish while the finding is recorded as fixed.
    local after line xy p tracked_dirt="" untracked_dirt="" ledger_index_dirt=""
    after="$(tree_state)"
    while IFS= read -r line; do
      [[ -n "$line" ]] || continue
      xy="${line:0:2}"; p="${line:3}"
      case "$p" in
        maintainer_tools/pr_review/*)
          # The worktree ledgers are cp-managed by Guard 1 — fix the INDEX
          # only; never checkout over them, and never rm -rf a directory here.
          if [[ "$xy" == '??' ]]; then
            [[ "$p" == */ ]] || rm -f -- "$REPO/$p"
            flog GUARD "removed stray file under pr_review: $p"
          else
            git -C "$REPO" reset -q HEAD -- "$p" 2>/dev/null
            ledger_index_dirt+="$p "
            flog GUARD "unstaged index change under pr_review: $p"
          fi ;;
        *)
          case "$xy" in
            '??')
              if [[ "$p" == */ ]]; then rm -rf -- "${REPO:?}/${p%/}"; else rm -f -- "$REPO/$p"; fi
              untracked_dirt+="$p "
              flog GUARD "removed uncommitted new file: $p" ;;
            *)
              # Restore index AND worktree from HEAD; a staged-new file ('A')
              # has no HEAD version — unstage it and delete the file.
              if ! git -C "$REPO" checkout -q HEAD -- "$p" 2>/dev/null; then
                git -C "$REPO" reset -q HEAD -- "$p" 2>/dev/null
                rm -f -- "$REPO/$p"
              fi
              tracked_dirt+="$p "
              flog GUARD "reverted uncommitted change (index+worktree): $p" ;;
          esac ;;
      esac
    done < <(LC_ALL=C comm -13 <(printf '%s' "$before") <(printf '%s' "$after"))
    if [[ -z "$fail" ]]; then
      if [[ -n "$ledger_index_dirt" ]]; then
        fail="the session staged changes under maintainer_tools/pr_review/ ($ledger_index_dirt) — never touch the campaign's directory"
      elif [[ -n "$tracked_dirt" ]]; then
        fail="the session left uncommitted changes to tracked files ($tracked_dirt) — commit everything you mean to keep; the attempt was discarded"
      elif [[ -n "$untracked_dirt" ]]; then
        fail="the session left uncommitted NEW files ($untracked_dirt) — they were deleted and the attempt discarded; a forgotten 'git add' of a pinning test must never silently vanish"
      fi
    fi

    # Guard 5: the report must be well-formed and consistent with the commits.
    if [[ -z "$fail" ]]; then
      local why
      if ! why="$(validate_report "$n_findings" "$n_commits")"; then
        (( n_commits > 0 )) && { ledger_safe_reset "$pre_sha"; commits=""; n_commits=0; }
        fail="unusable report: $why (agent exit=$session_rc)"
        flog GUARD "$fail"
      fi
    fi
    # A 'fixed' claim whose commits cancel to a net no-op (commit-then-revert)
    # would also dodge the refresh's re-review backstop — reject it.
    if [[ -z "$fail" ]] && (( n_commits > 0 )) \
       && grep -qE '^- \[[0-9]+\] fixed' "$REPORT" \
       && git -C "$REPO" diff --quiet "$pre_sha" HEAD; then
      ledger_safe_reset "$pre_sha"
      commits=""; n_commits=0
      fail="the commits have no net effect on the tree, yet the report claims a fix — a fix must change something"
      flog GUARD "net-zero commits with a fixed claim — reset to $pre_sha"
    fi

    # Guard 6: the wrapper gate ran in the disposable worktree before import.
    local gate_desc="${SESSION_GATE_DESC:-skipped (no changes)}"
    if [[ -z "$fail" ]] && (( n_commits > 0 )); then
      [[ "$SESSION_GATE_DESC" == green* ]] \
        || fail="the disposable worktree did not produce a green gate result"
    fi

    if [[ -n "$fail" ]]; then
      # Whatever guard fired: a failed attempt never leaves commits behind,
      # and never leaves gate/suite artifacts that would wedge later gates.
      if [[ "$(git -C "$REPO" rev-parse HEAD)" != "$pre_sha" ]]; then
        ledger_safe_reset "$pre_sha"
        flog GUARD "failed attempt still had commits — reset to $pre_sha"
      fi
      remove_new_untracked "$before"
      verify_restored "$before"
      retry=$((retry + 1))
      if (( retry > MAX_RETRIES )); then
        fixes_update "$path" "$ra" '.status = "error" | .attempts = $a | .error = $e' \
          --argjson a "$retry" --arg e "no accepted fix after $MAX_RETRIES retries — last failure: ${fail%%$'\n'*}"
        flog ERROR "giving up after $MAX_RETRIES retries"
        log "✗ $path — ERROR (no accepted fix after $MAX_RETRIES retries; fix_queue.sh requeue to retry)"
        retry=0; prev_key=""; feedback=""
        iter=$((iter + 1))
        continue
      fi
      feedback="$fail"
      local mins=$((retry * 2)); (( mins > 10 )) && mins=10
      local secs=$((mins * 60))
      [[ -n "${FIX_RETRY_STEP_S:-}" ]] && secs=$((retry * FIX_RETRY_STEP_S))
      flog RETRY "attempt failed — retry #$retry in ${secs}s: ${fail%%$'\n'*}"
      log "↻ attempt on $path failed (${fail%%$'\n'*}) — retry #$retry in ${secs}s"
      sleep "$secs"
      continue
    fi

    # Accept.
    verify_restored "$before"
    local oj needs_human commits_json commits_csv summary
    oj="$(outcomes_json "$sevs_csv")"
    needs_human="$(jq 'any(.[]; .outcome == "deferred")' <<<"$oj")"
    commits_json="$(jq -R 'select(length > 0)' <<<"$commits" | jq -s .)"
    commits_csv="$(tr '\n' ' ' <<<"$commits" | sed 's/ *$//')"
    fixes_update "$path" "$ra" \
      '.status = "done" | .outcomes = $o | .commits = $c | .gate = $g
       | .needs_human = $h | .attempts = $a | .resolved_at = $ts | .error = null' \
      --argjson o "$oj" --argjson c "$commits_json" \
      --arg g "$gate_desc" --argjson h "$needs_human" --argjson a "$((retry + 1))" --arg ts "$(date -Is)"
    record_resolution "$path" "$round" "$sevs_csv" "$gate_desc" "$commits_csv"
    # Durable marker: commits are in but the manifest refresh has not run yet.
    # Survives a crash — the next run catches up before doing anything else.
    [[ -n "$commits_csv" ]] && touch "$SCRIPT_DIR/.needs_refresh"
    summary="$(jq -r 'group_by(.outcome) | map("\(length) \(.[0].outcome)") | join(", ")' <<<"$oj")"
    flog DONE "$summary — gate: $gate_desc"
    log "✓ $path — $summary$([[ -n "$commits_csv" ]] && echo " (committed: $commits_csv)")"
    [[ "$needs_human" == true ]] && log "  ⚑ deferred finding(s) need a human — see findings.md"

    retry=0; feedback=""
    iter=$((iter + 1))
    rm -f "$REPORT"

    if (( WAIT_MIN > 0 )); then
      log "waiting ${WAIT_MIN} min before the next entry…"
      sleep "$((WAIT_MIN * 60))"
    fi
  done

  # Fixed files must re-enter review (stale) and new test files must enter as
  # pending — that is generate_manifest.sh --refresh. It takes the same lock,
  # so release ours first. Keyed on the durable marker, not an in-memory flag.
  if [[ -f "$SCRIPT_DIR/.needs_refresh" && "$FIX_REFRESH" == 1 ]]; then
    exec 9>&-
    log "commits landed — refreshing the manifest so fixed files re-enter review"
    refresh_manifest || die "manifest refresh failed — run generate_manifest.sh --refresh by hand (.needs_refresh is kept so the next run retries)"
  fi

  queue_status
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main
fi
