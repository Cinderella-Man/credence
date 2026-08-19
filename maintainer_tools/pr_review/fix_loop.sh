#!/usr/bin/env bash
#
# fix_loop.sh — the FIX phase of the whole-PR review campaign. Drains the fix
# ledger (fixes.json, one entry per reviewed file whose verdict was FINDINGS):
# per entry it briefs one claude session that must, per finding, CONFIRM with an
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
#   CLAUDE_MODEL / FIX_CLAUDE_MODEL  optional --model (FIX_ wins for fix sessions)
#   MAX_RETRIES          failed attempts per entry before `error` (default 2)
#   FIX_MEM_MAX          systemd MemoryMax for session AND gate (default 16G;
#                        empty string disables — see docs/21 OOM history)
#   FIX_SESSION_TIMEOUT  seconds per claude session (default 7200; 0 = none)
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
LOGDIR="$SCRIPT_DIR/.fix_logs"
BAKDIR="$LOGDIR/.bak"

CAP="${1:-0}"
WAIT_MIN="${2:-0}"
MAX_RETRIES="${MAX_RETRIES:-2}"
FIX_MEM_MAX="${FIX_MEM_MAX-16G}"
FIX_SESSION_TIMEOUT="${FIX_SESSION_TIMEOUT:-7200}"
FIX_GATE_TIMEOUT="${FIX_GATE_TIMEOUT:-2400}"
FIX_REFRESH="${FIX_REFRESH:-1}"
FIX_MODEL="${FIX_CLAUDE_MODEL:-${CLAUDE_MODEL:-}}"
ALLOWED_TOOLS="Read Grep Glob Write Edit Bash"

log() { printf '[fix_loop] %s\n' "$*"; }
die() { printf '[fix_loop] FATAL: %s\n' "$*" >&2; exit 1; }

[[ -f "$MANIFEST" ]] || die "no manifest.json — run generate_manifest.sh first"
[[ -f "$PROMPT" ]]   || die "prompt file missing: $PROMPT"
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
run_fix_session() { # $1 = briefing text; transcript goes to FIXLOG
  local prompt rc=0
  prompt="$(cat "$PROMPT")"$'\n\n'"$1"
  local -a model_args=()
  [[ -n "$FIX_MODEL" ]] && model_args=(--model "$FIX_MODEL")
  flog SESSION "starting claude (model=${FIX_MODEL:-default}, timeout=${FIX_SESSION_TIMEOUT}s, mem=${FIX_MEM_MAX:-uncapped})"
  flog SESSION "----- agent transcript -----"
  # timeout runs INSIDE the memory scope so its kill reaches the session.
  ( cd "$REPO" && "${CAPPED[@]}" timeout -k 60 "$FIX_SESSION_TIMEOUT" \
      claude -p "$prompt" --allowedTools "$ALLOWED_TOOLS" "${model_args[@]}" ) \
    >> "$FIXLOG" 2>&1 9>&- || rc=$?
  flog SESSION "----- end transcript (claude exit=${rc}) -----"
  return "$rc"
}

# ---- report ----------------------------------------------------------------
OUTCOME_RE='^- \[[0-9]+\] (fixed|refuted|obsolete|deferred)'

# validate_report <n_findings> <n_commits> — 0 = usable; reason on stdout if not.
validate_report() {
  local n="$1" ncommits="$2"
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
  if (( nfixed > 0 && ncommits == 0 )); then
    echo "report claims $nfixed finding(s) fixed but the session committed nothing"; return 1
  fi
  if (( ncommits > 0 && nfixed + ndeferred == 0 )); then
    echo "the session committed code but reports no finding as fixed or deferred — refuted/obsolete findings must not change code"; return 1
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

run_gate() { # $1 = pre_sha, $2 = gate log file
  local pre="$1" gatelog="$2" rc=0
  : > "$gatelog"
  if [[ -n "${FIX_GATE_CMD:-}" ]]; then
    ( cd "$REPO" && timeout -k 60 "$FIX_GATE_TIMEOUT" bash -c "$FIX_GATE_CMD" ) \
      >> "$gatelog" 2>&1 || rc=$?
    return "$rc"
  fi
  local -a touched=()
  local f
  while IFS= read -r f; do
    [[ -f "$REPO/$f" ]] && touched+=("$f")
  done < <(git -C "$REPO" diff --name-only "$pre"..HEAD | grep -E '\.(ex|exs)$' || true)
  (
    cd "$REPO" || exit 70
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
    run_fix_session "$briefing" || session_rc=$?

    local fail=""

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
        fail="unusable report: $why (claude exit=$session_rc)"
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

    # Guard 6: the wrapper's own gate. The session already ran it; trust nothing.
    local gate_desc="skipped (no commits)"
    if [[ -z "$fail" ]] && (( n_commits > 0 )); then
      local gatelog="$LOGDIR/$(tr '/' '__' <<<"$path").round${round}.attempt$((retry + 1)).gate.log"
      flog GATE "running the fast gate ($n_commits commits to verify)"
      log "  gate: verifying $n_commits commit(s) — $GATE_DESC"
      if run_gate "$pre_sha" "$gatelog"; then
        gate_desc="green ($GATE_DESC)"
        flog GATE "green"
      else
        local tail_out
        tail_out="$(tail -n 40 "$gatelog")"
        ledger_safe_reset "$pre_sha"
        commits=""; n_commits=0
        fail="the wrapper's gate is RED — your commits were discarded. Gate output tail:"$'\n'"$tail_out"
        flog GATE "red — reset to $pre_sha (full output: $gatelog)"
      fi
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
