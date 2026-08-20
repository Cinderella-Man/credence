#!/usr/bin/env bash
#
# review_loop.sh — orchestrator for the whole-PR, one-file-at-a-time review.
#
# Per iteration: pick the first `pending` entry in manifest.json → verify the
# worktree file still matches the manifest's frozen head → build a briefing
# (diff / base version written to _briefing/ for the session to Read) → run one
# fresh, read-only claude session (Read Grep Glob Write; NO Bash, NO Edit) →
# read the verdict from _verdict (OK | FINDINGS + bullet lines) → append
# findings to findings.md → tick the entry off in manifest.json → print a
# one-line digest → yield. Resumable at any point; the manifest is the truth.
#
# Sessions are untrusted: manifest.json and findings.md are backed up around
# every session and restored (with a retry) if the session touched them; any
# other new dirt is reverted, and if the revert cannot restore the pre-session
# tree the loop aborts loudly. A row with no usable verdict retries with
# backoff (2/4/6… min, cap 10) up to MAX_RETRIES, then is marked `error` and
# the loop moves on.
#
# Usage:   review_loop.sh [cap] [wait_min]
#   cap        max files this run (0 = until manifest drained; default 0)
#   wait_min   minutes to sleep between files (default 0)
# Env:
#   CLAUDE_MODEL         optional --model for the session
#   MAX_RETRIES          no-verdict retries per row before `error` (default 3)
#   COMMIT_EVERY         0 = never touch git (default); N = commit
#                        manifest.json + findings.md every N reviewed files
#   REVIEW_RETRY_STEP_S  test hook: seconds per backoff step instead of minutes
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$SCRIPT_DIR"/../.. && pwd)"
# shellcheck source=../stage_1_promote_fixable_rules/review_lib.sh
source "$SCRIPT_DIR/../stage_1_promote_fixable_rules/review_lib.sh"

MANIFEST="$SCRIPT_DIR/manifest.json"
FINDINGS="$SCRIPT_DIR/findings.md"
VERDICT="$SCRIPT_DIR/_verdict"
PROMPT="$SCRIPT_DIR/review_file_prompt.md"
BRIEFDIR="$SCRIPT_DIR/_briefing"
LOGDIR="$SCRIPT_DIR/.review_logs"
BAKDIR="$SCRIPT_DIR/_briefing/.bak"   # inside _briefing: gitignored, wiped per row

CAP="${1:-0}"
WAIT_MIN="${2:-0}"
MAX_RETRIES="${MAX_RETRIES:-3}"
COMMIT_EVERY="${COMMIT_EVERY:-0}"
CLAUDE_MODEL="${CLAUDE_MODEL:-}"
ALLOWED_TOOLS="Read Grep Glob Write"

log() { printf '[pr_review] %s\n' "$*"; }
die() { printf '[pr_review] FATAL: %s\n' "$*" >&2; exit 1; }

[[ -f "$MANIFEST" ]] || die "no manifest.json — run generate_manifest.sh first"
[[ -f "$PROMPT" ]]   || die "prompt file missing: $PROMPT"
command -v jq >/dev/null || die "jq not found"
mkdir -p "$LOGDIR"
touch "$FINDINGS"   # must exist so the guard and commit_progress see one thing

exec 9>"$SCRIPT_DIR/.lock"
flock -n 9 || die "another review_loop (or manifest tool) is already running"

BASE_SHA="$(jq -r .base "$MANIFEST")"
HEAD_SHA="$(jq -r .head "$MANIFEST")"
TOTAL="$(jq -r '.files | length' "$MANIFEST")"

# The frozen head must be an ancestor of the current checkout: progress commits
# on top are fine, a branch switch or older detached HEAD is not.
git -C "$REPO" merge-base --is-ancestor "$HEAD_SHA" HEAD \
  || die "current checkout does not descend from the manifest's frozen head ${HEAD_SHA:0:9} — wrong branch? (re-freeze with generate_manifest.sh --refresh if intended)"

# Per-row transcript (gitignored). rlog narrates every stage into it.
ROWLOG=""
rlog() { [[ -n "$ROWLOG" ]] && printf '[%s] %-9s %s\n' "$(date +%H:%M:%S)" "$1" "${*:2}" >> "$ROWLOG"; return 0; }

done_count()   { jq -r '[.files[] | select(.status == "done")]  | length' "$MANIFEST"; }
# TSV: path origin category old_path stale blob — "-" placeholders keep every
# field non-empty (adjacent tabs collapse under IFS and shift the fields).
next_pending() {
  jq -r 'first(.files[] | select(.status == "pending")) // empty
         | [.path, .origin, .category, (.old_path // "-"), (.stale | tostring), .blob] | @tsv' "$MANIFEST"
}

# Atomic manifest updates (jq → tmp in the same dir → mv).
manifest_set() { # $1 = jq program body applied to the selected entry, rest = jq args
  local prog="$1"; shift
  local tmp; tmp="$(mktemp "$SCRIPT_DIR/.manifest.XXXXXX.json")"
  if jq "$@" "(.files[] | select(.path == \$p)) |= ($prog)" "$MANIFEST" > "$tmp"; then
    mv "$tmp" "$MANIFEST"
  else
    rm -f "$tmp"; die "jq manifest update failed"
  fi
}
# ungate_tests_of <rule path> — put this rule's own test rows into the queue.
# They enter the manifest as `gated` (see generate_manifest.sh's gated_by) and
# are only worth a session once the rule itself has come back with something:
# in the 2026-08-19 run every one of the 14 blockers came from a `lib/` rule
# file and none from a test file, while test files are half the universe.
# A rule that reviews clean leaves its tests gated; requeue.sh --gated opens
# them all when the rule pass is done.
ungate_tests_of() { # $1 = rule path
  local tmp n
  n="$(jq --arg r "$1" '[.files[] | select(.gated_by == $r and .status == "gated")] | length' "$MANIFEST")"
  (( n > 0 )) || return 0
  tmp="$(mktemp "$SCRIPT_DIR/.manifest.XXXXXX.json")"
  if jq --arg r "$1" \
       '(.files[] | select(.gated_by == $r and .status == "gated")) |= (.status = "pending")' \
       "$MANIFEST" > "$tmp"; then
    mv "$tmp" "$MANIFEST"
    rlog GATE "opened $n gated test row(s) for $1"
  else
    rm -f "$tmp"; die "jq manifest update failed while ungating tests of $1"
  fi
}

mark_done() { # path verdict n_findings
  manifest_set '.status = "done" | .verdict = $v | .findings = $n | .reviewed_at = $ts | .error = null | .stale = false' \
    --arg p "$1" --arg v "$2" --argjson n "$3" --arg ts "$(date -Is)"
  [[ "$2" == FINDINGS ]] && ungate_tests_of "$1"
  return 0
}
mark_error() { # path reason
  manifest_set '.status = "error" | .error = $r | .reviewed_at = $ts' \
    --arg p "$1" --arg r "$2" --arg ts "$(date -Is)"
}

# ---- tree guard ------------------------------------------------------------
# Sessions may only write the (gitignored) _verdict. Two layers:
#  1. The loop's own data files are backed up before and hash-checked after
#     every session — porcelain cannot see writes into already-dirty files,
#     and manifest.json/findings.md are dirty for the whole campaign.
#  2. Porcelain snapshots for the rest of the repo; new dirt is reverted, and
#     if the revert does not restore the pre-session state the loop aborts.
owned_hash() { cat "$MANIFEST" "$FINDINGS" "$SCRIPT_DIR/fixes.json" 2>/dev/null | md5sum; }
tree_state() { git -C "$REPO" status --porcelain=v1 | LC_ALL=C sort; }
revert_new_dirt() { # $1 = before-state, $2 = after-state; echoes reverted paths
  local line xy path
  while IFS= read -r line; do
    [[ -n "$line" ]] || continue
    xy="${line:0:2}"; path="${line:3}"
    case "$xy" in
      '??')
        if [[ "$path" == */ ]]; then rm -rf -- "${REPO:?}/${path%/}"
        else rm -f -- "$REPO/$path"; fi ;;
      *)  # restore worktree from the index (preserves anything the user staged)
        git -C "$REPO" checkout -q -- "$path" 2>/dev/null || rm -f -- "$REPO/$path" ;;
    esac
    printf '%s\n' "$path"
  done < <(LC_ALL=C comm -13 <(printf '%s' "$1") <(printf '%s' "$2"))
}

# ---- briefing --------------------------------------------------------------
BRIEF_REL="maintainer_tools/pr_review/_briefing"
build_briefing() { # path origin category old_path stale
  local path="$1" origin="$2" cat="$3" old="$4" stale="$5"
  {
    echo "# File briefing"
    echo "Path:     $path"
    [[ -n "$old" ]] && echo "Old path: $old (renamed in this PR)"
    echo "Origin:   $origin"
    echo "Category: $cat"
    echo "PR:       base $BASE_SHA → head $HEAD_SHA"
    [[ "$stale" == true ]] && echo "NOTE: this file changed after an earlier review of it — re-review."
    echo
    case "$origin" in
      added)
        echo "New file in this PR. Review the working-tree file at $path in full." ;;
      modified|renamed)
        git -C "$REPO" show "$BASE_SHA:${old:-$path}" > "$BRIEFDIR/base_version" 2>/dev/null \
          || echo "(base version unavailable)" > "$BRIEFDIR/base_version"
        git -C "$REPO" diff -M "$BASE_SHA".."$HEAD_SHA" -- ${old:+"$old"} "$path" > "$BRIEFDIR/diff.patch"
        echo "Modified by this PR. Judge the change; a defect you notice outside"
        echo "the delta is still reportable (label it pre-existing)."
        echo "- Current version:  the working-tree file $path"
        echo "- The PR's change:  $BRIEF_REL/diff.patch ($(wc -l < "$BRIEFDIR/diff.patch") lines)"
        echo "- Pre-PR version:   $BRIEF_REL/base_version" ;;
      deleted)
        git -C "$REPO" show "$BASE_SHA:$path" > "$BRIEFDIR/deleted_version" 2>/dev/null || true
        echo "Deleted by this PR; the file no longer exists in the tree."
        echo "- Its pre-PR content: $BRIEF_REL/deleted_version"
        echo "Judge whether the deletion is clean: search for dangling references"
        echo "to the file, its module name, and anything only it provided." ;;
      unchanged_rule)
        echo "NOT touched by this PR — but the code underneath it (helpers,"
        echo "dispatch, masking, ordering) changed. Review the rule from scratch"
        echo "at $path AND judge whether it still holds its contract on top of"
        echo "this PR's changes to shared code." ;;
    esac
    case "$cat" in
      rule_*|test_*)
        local kind="${cat#rule_}"; kind="${kind#test_}"
        local base; base="$(rule_base "$path")"
        echo
        echo "Files sharing this rule base in the tree:"
        ( cd "$REPO" && ls "lib/$kind/$base.ex" "test/$kind/$base"*_test.exs 2>/dev/null ) \
          | sed 's/^/  - /' || true ;;
    esac
  }
}

# ---- session ---------------------------------------------------------------
run_session() { # $1 = briefing text; transcript goes to ROWLOG
  local prompt rc=0
  prompt="$(cat "$PROMPT")"$'\n\n'"$1"
  local -a model_args=()
  [[ -n "$CLAUDE_MODEL" ]] && model_args=(--model "$CLAUDE_MODEL")
  rlog SESSION "starting claude (model=${CLAUDE_MODEL:-default}, prompt ${#prompt} chars)"
  rlog SESSION "----- agent transcript -----"
  # 9>&- : do not leak the lock fd into the session (an orphaned session would
  # otherwise hold the lock after the loop dies).
  ( cd "$REPO" && claude -p "$prompt" --allowedTools "$ALLOWED_TOOLS" "${model_args[@]}" ) \
    >> "$ROWLOG" 2>&1 9>&- || rc=$?
  rlog SESSION "----- end transcript (claude exit=${rc}) -----"
  return "$rc"
}

# ---- verdict ---------------------------------------------------------------
SEV_RE='^- (blocker|concern|nit):'
record_findings() { # path origin category — appends _verdict body to findings.md
  local path="$1" origin="$2" cat="$3"
  {
    echo "## $path — $(date +%F) ($origin, $cat)"
    tail -n +2 "$VERDICT"
    echo
  } >> "$FINDINGS"
}

commit_progress() { # $1 = done count
  local -a ledgers=("$MANIFEST" "$FINDINGS")
  [[ -f "$SCRIPT_DIR/fixes.json" ]] && ledgers+=("$SCRIPT_DIR/fixes.json")
  local f
  for f in "${ledgers[@]}"; do
    git -C "$REPO" add -- "$f" || log "warning: could not stage ${f##*/}"
  done
  # pathspec commit: never sweeps up anything the user staged for their own work
  if git -C "$REPO" commit -q -m "pr_review: $1/$TOTAL files reviewed" -- "${ledgers[@]}"; then
    rlog COMMIT "committed progress ($1/$TOTAL)"
  else
    rlog COMMIT "nothing to commit"
  fi
}

# ---- main ------------------------------------------------------------------
main() {
  local pre_dirt
  pre_dirt="$(tree_state | grep -v 'maintainer_tools/pr_review/' || true)"
  [[ -n "$pre_dirt" ]] && log "note: tree already dirty outside pr_review — session writes into these files would be invisible to the guard:"$'\n'"$pre_dirt"

  local iter=0 retry=0 prev_path=""
  while :; do
    rm -f "$VERDICT"

    local row
    row="$(next_pending)"
    if [[ -z "$row" ]]; then
      log "done — no pending entries ($(done_count)/$TOTAL reviewed)"
      break
    fi
    if (( CAP > 0 && iter >= CAP )); then log "cap $CAP reached"; break; fi

    local path origin cat old stale blob
    IFS=$'\t' read -r path origin cat old stale blob <<<"$row"
    [[ "$old" == "-" ]] && old=""
    [[ "$path" == "$prev_path" ]] || retry=0
    prev_path="$path"

    # One log per SESSION, not per path. Keying the filename on the path alone
    # and truncating meant every re-review — and every retry — erased the one
    # before it: of the 42 review sessions in the 2026-08-19 run, 31 left no
    # trace at all, which is why that run looked like it had idle gaps in it.
    # A round or attempt suffix does not work here: review_loop.sh resets
    # iter/retry at startup and campaign.sh starts a fresh process per
    # iteration, so every log would collide on the same suffix again.
    ROWLOG="$LOGDIR/$(tr '/' '__' <<<"$path").$(date +%Y%m%dT%H%M%S).log"; : > "$ROWLOG"
    local ndone; ndone="$(done_count)"
    rlog START "file $((ndone + 1))/$TOTAL: $path ($origin, $cat)${old:+ old=$old}"
    log "▶ $(date '+%H:%M') reviewing $path ($origin, $cat) — $ndone/$TOTAL done$([[ $retry -gt 0 ]] && echo " [retry #$retry]")"

    # The session reviews the WORKTREE file; the verdict is only meaningful if
    # that still matches the frozen head this manifest describes.
    local actual="absent"
    [[ -f "$REPO/$path" ]] && actual="$(git -C "$REPO" hash-object -- "$REPO/$path")"
    if { [[ "$origin" == deleted && "$actual" != absent ]]; } \
       || { [[ "$origin" != deleted && "$actual" != "$blob" ]]; }; then
      mark_error "$path" "worktree content does not match the frozen head (worktree $actual, manifest ${blob:0:9}) — local edits? requeue after resolving, or --refresh"
      rlog ERROR "worktree/manifest mismatch (worktree=$actual manifest=$blob) — marked error"
      log "✗ $path — ERROR (worktree does not match frozen head; resolve then requeue.sh)"
      retry=0; prev_path=""; iter=$((iter + 1))
      continue
    fi

    rm -rf "$BRIEFDIR"; mkdir -p "$BAKDIR"
    local briefing before after owned_before
    briefing="$(build_briefing "$path" "$origin" "$cat" "$old" "$stale" 2>>"$ROWLOG")"
    rlog BRIEF "briefing built ($(wc -c <<<"$briefing") chars)"

    cp "$MANIFEST" "$BAKDIR/manifest.json"
    cp "$FINDINGS" "$BAKDIR/findings.md"
    [[ -f "$SCRIPT_DIR/fixes.json" ]] && cp "$SCRIPT_DIR/fixes.json" "$BAKDIR/fixes.json"
    owned_before="$(owned_hash)"
    before="$(tree_state)"

    local session_rc=0
    run_session "$briefing" || session_rc=$?

    if [[ "$(owned_hash)" != "$owned_before" ]]; then
      cp "$BAKDIR/manifest.json" "$MANIFEST"
      cp "$BAKDIR/findings.md" "$FINDINGS"
      if [[ -f "$BAKDIR/fixes.json" ]]; then
        cp "$BAKDIR/fixes.json" "$SCRIPT_DIR/fixes.json"
      elif [[ -f "$SCRIPT_DIR/fixes.json" ]]; then
        rm -f "$SCRIPT_DIR/fixes.json"   # the session invented it
      fi
      rlog GUARD "session touched the campaign ledgers — restored from backup"
      log "⚠ session touched the loop's own data files (restored) — retrying"
      rm -f "$VERDICT"
    fi

    after="$(tree_state)"
    if [[ "$before" != "$after" ]]; then
      local reverted; reverted="$(revert_new_dirt "$before" "$after")"
      rlog GUARD "session dirtied the tree — reverted: $(tr '\n' ' ' <<<"$reverted")"
      log "⚠ session modified the repo (reverted: $(tr '\n' ' ' <<<"$reverted")) — retrying"
      rm -f "$VERDICT"
      [[ "$(tree_state)" == "$before" ]] \
        || die "tree still dirty after reverting session writes — inspect 'git status' before rerunning"
    fi

    local v1
    v1="$(head -n1 "$VERDICT" 2>/dev/null || true)"
    case "$v1" in
      OK)
        mark_done "$path" "OK" 0
        rlog DONE "OK"
        log "✓ $((ndone + 1))/$TOTAL  $path — OK" ;;
      FINDINGS)
        local nf
        nf="$(grep -cE "$SEV_RE" "$VERDICT")"
        if (( nf == 0 )); then
          v1=""   # malformed: FINDINGS with no severity bullets → retry path
        else
          record_findings "$path" "$origin" "$cat"
          mark_done "$path" "FINDINGS" "$nf"
          rlog DONE "FINDINGS($nf) → findings.md"
          log "⚠ $((ndone + 1))/$TOTAL  $path — FINDINGS($nf) → findings.md"
        fi ;;
    esac

    if [[ "$v1" != OK && "$v1" != FINDINGS ]]; then
      # No usable verdict: transient (crash, token limit, malformed output).
      retry=$((retry + 1))
      if (( retry > MAX_RETRIES )); then
        mark_error "$path" "no verdict after $MAX_RETRIES retries (last claude exit=$session_rc)"
        rlog ERROR "no verdict after $MAX_RETRIES retries — marked error, moving on"
        log "✗ $path — ERROR (no verdict after $MAX_RETRIES retries; requeue.sh to retry later)"
        retry=0; prev_path=""
        iter=$((iter + 1))
        continue
      fi
      local mins=$((retry * 2)); (( mins > 10 )) && mins=10
      local secs=$((mins * 60))
      [[ -n "${REVIEW_RETRY_STEP_S:-}" ]] && secs=$((retry * REVIEW_RETRY_STEP_S))
      rlog RETRY "no verdict (claude exit=$session_rc) — retry #$retry in ${secs}s"
      log "↻ no verdict for $path (claude exit=$session_rc) — retry #$retry in ${secs}s"
      sleep "$secs"
      continue
    fi

    retry=0
    iter=$((iter + 1))
    rm -f "$VERDICT"

    ndone="$(done_count)"
    if (( COMMIT_EVERY > 0 && ndone % COMMIT_EVERY == 0 )); then commit_progress "$ndone"; fi

    if (( WAIT_MIN > 0 )); then
      log "waiting ${WAIT_MIN} min before the next file ($ndone/$TOTAL done)…"
      sleep "$((WAIT_MIN * 60))"
    fi
  done

  [[ "${QUIET_STATUS:-0}" == 1 ]] || "$SCRIPT_DIR/status.sh" || true
}

# Run main unless sourced (sourcing exposes the functions for testing).
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main
fi
