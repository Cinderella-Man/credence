#!/usr/bin/env bash
#
# review_loop.sh — orchestrator for the autonomous fixable-rule review loop.
#
# Drives one fresh, sandboxed (no-git) Claude session per candidate set from
# docs/candidates.md. The wrapper owns ALL git and ALL list edits; the session's
# only output channel is docs/_verdict (ACCEPT | FOLLOWUP: <reason>).
#
# Per iteration: self-heal a stale tree → pick the top set → (orphan test ⇒
# followup, no session) → copy the set in → classify new-vs-delta + build a
# briefing → run the session → read the verdict → ACCEPT runs the per-kind
# re-verify gate (keep files, commit, push) else FOLLOWUP (revert files, record,
# commit, push). Only a verified ACCEPT exits to "accepted"; everything else goes
# to followup, so a set never re-fetches in a loop.
#
# Usage:   review_loop.sh [cap] [wait_min]
#   cap        max iterations (0 = run until candidates.md empty; default 0)
#   wait_min   minutes to sleep between iterations (default 15)
# Env:
#   SISTER=/path     sister checkout (default ../credence_evolution)
#   CLAUDE_MODEL     optional --model for the session
#
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(dirname "$SCRIPT_DIR")"
# shellcheck source=review_lib.sh
source "$SCRIPT_DIR/review_lib.sh"

CANDIDATES="$REPO/docs/candidates.md"
FOLLOWUP="$REPO/docs/followup.md"
VERDICT="$REPO/docs/_verdict"
PROMPT="$SCRIPT_DIR/review_set_prompt.md"
SISTER="${SISTER:-$(cd "$REPO/.." && pwd)/credence_evolution}"
CLAUDE_MODEL="${CLAUDE_MODEL:-}"

CAP="${1:-0}"
WAIT_MIN="${2:-15}"

ALLOWED_TOOLS="Read Edit Write Grep Glob Bash(mix test:*) Bash(mix format:*) Bash(elixir:*)"

for f in "$CANDIDATES" "$FOLLOWUP" "$PROMPT"; do
  [[ -f "$f" ]] || { echo "error: required file not found: $f" >&2; exit 1; }
done
[[ -d "$SISTER" ]] || { echo "error: sister dir not found: $SISTER" >&2; exit 1; }

log() { printf '[review_loop] %s\n' "$*"; }
die() { printf '[review_loop] FATAL: %s\n' "$*" >&2; exit 1; }

# Per-row transcript. ROWLOG is set in main; rlog appends a timestamped, stage-
# tagged line so the log narrates every step (copy → classify → scan → session →
# each gate check → commit → push).
ROWLOG=""
rlog() { [[ -n "$ROWLOG" ]] && printf '[%s] %-9s %s\n' "$(date +%H:%M:%S)" "$1" "${*:2}" >> "$ROWLOG"; return 0; }

# Informational scan: report each fix test's `=~` / `\n`-escaped-string count.
# Never fails the gate — the agent is expected to have converted these; this just
# makes the state visible (e.g. "fix tests are clean — no =~").
# Partial-match ASSERTION weasels the AI has used to dodge exact `==` compares:
# =~, and assert/refute lines using String.contains?/match?/starts_with?/ends_with?
# /split or Regex.match?/run/scan. Anchored to assert|refute so the SAME functions
# appearing inside the code-under-test or an expected heredoc are NOT flagged.
WEASEL_RE='^[[:space:]]*(assert|refute)[[:space:]].*(String\.(contains\?|match\?|starts_with\?|ends_with\?|split)|Regex\.(match\?|run|scan))'
# A `\n` inside a longer string literal (an `\n`-escaped code string), but NOT the
# bare `"\n"` used by `fix/` helpers (there the `\n` is right after the quote).
NLSTR_RE='[^"]\\n'
scan_fix_tests() {
  local base="$1" kind="$2" t="test/${kind}" ft n p m tot=0 totp=0 totnl=0
  for ft in "$REPO/$t/${base}"*_fix_test.exs "$REPO/$t/${base}_test.exs"; do
    [[ -f "$ft" ]] || continue
    n="$(grep -c '=~' "$ft" 2>/dev/null)"; n="${n:-0}"
    p="$(grep -cE "$WEASEL_RE" "$ft" 2>/dev/null)"; p="${p:-0}"
    m="$(grep -cE "$NLSTR_RE" "$ft" 2>/dev/null)"; m="${m:-0}"
    tot=$((tot + n)); totp=$((totp + p)); totnl=$((totnl + m))
    rlog SCAN "$(basename "$ft"): ${n} =~, ${p} partial-match assert (contains?/match?/split/Regex), ${m} \\n-escaped string(s)"
  done
  if (( tot == 0 && totp == 0 && totnl == 0 )); then
    rlog SCAN "fix tests are CLEAN — exact whole-string == compares only (no =~, no String.contains?/match?, no \\n-strings)"
  else
    rlog SCAN "TOTAL ${tot} =~ + ${totp} partial-match assert(s) + ${totnl} \\n-escaped string(s) — all should be exact == compares"
  fi
}

list_empty()  { ! grep -q -v '^[[:space:]]*$' "$CANDIDATES"; }
top_anchor()  { grep -m1 -v '^[[:space:]]*$' "$CANDIDATES" || true; }
count_list()  { local n; n="$(grep -c -v '^[[:space:]]*$' "$CANDIDATES" 2>/dev/null)"; echo "${n:-0}"; }

# Per-row agent transcripts (gitignored); keep the console a one-line digest.
LOGDIR="$REPO/scripts/.review_logs"
mkdir -p "$LOGDIR"
MIXLOG=/tmp/review_loop_mixtest.log

# Per-row summary state, reset each iteration; set by the handlers, printed once.
G_ROW=0; G_BASE=""; G_KIND=""; G_MODE=""; G_VERDICT=""; G_REASON=""
G_FILES=""; G_SUITE=""; G_PUSH=""; G_LB=0; G_LA=0; G_GATE_REASON=""; G_SESSION_RC=0

# Compact "NNNN✓" / "NNNN/F✗" parsed from the gate's mix test log.
suite_summary() {
  local line tests fails
  [[ -f "$MIXLOG" ]] || { echo ""; return; }
  line="$(grep -oE '[0-9]+ tests?, [0-9]+ failures?' "$MIXLOG" | tail -1)"
  [[ -n "$line" ]] || { echo ""; return; }
  tests="$(grep -oE '^[0-9]+' <<<"$line")"
  fails="$(grep -oE '[0-9]+ failures?' <<<"$line" | grep -oE '[0-9]+')"
  if [[ "$fails" == 0 ]]; then echo "${tests}✓"; else echo "${tests}/${fails}✗"; fi
}

# Compact diffstat of HEAD: "<N>f +<ins>/-<del>".
diffstat_head() {
  local stat ins del nf
  stat="$(git -C "$REPO" show --shortstat --format= HEAD | tail -1)"
  ins="$(grep -oE '[0-9]+ insertion' <<<"$stat" | grep -oE '[0-9]+')"
  del="$(grep -oE '[0-9]+ deletion'  <<<"$stat" | grep -oE '[0-9]+')"
  nf="$(git -C "$REPO" show --stat --format= HEAD | grep -c '|')"
  echo "${nf}f +${ins:-0}/-${del:-0}"
}

# Push and record status for the digest.
do_push() {
  if git -C "$REPO" push -q; then G_PUSH="pushed"
  else G_PUSH="local"; log "warning: push failed for $1 (commit is local)"; fi
}

# Print the one-line row digest from the G_* state.
row_summary() {
  local sym
  case "$G_VERDICT" in
    ACCEPT)   sym="✓" ;;
    FOLLOWUP) sym="✗" ;;
    ORPHAN)   sym="—" ;;
    RETRY)    sym="↻" ;;
    *)        sym="?" ;;
  esac
  local line="${sym} row ${G_ROW}  ${G_BASE} (${G_KIND}${G_MODE:+/$G_MODE})  ${G_VERDICT}"
  [[ -n "$G_REASON" ]] && line+=": ${G_REASON:0:90}"
  [[ -n "$G_FILES"  ]] && line+="  | ${G_FILES}"
  [[ -n "$G_SUITE"  ]] && line+="  | suite ${G_SUITE}"
  line+="  | list ${G_LB}→${G_LA}"
  [[ -n "$G_PUSH"   ]] && line+="  | ${G_PUSH}"
  printf '%s\n' "$line"
}

# The set paths for a given anchor: the rule file + its grouped test line(s) as
# they appear in candidates.md (whatever was/will be copied in).
set_paths() {
  local anchor="$1" base; base="$(rule_base "$anchor")"
  printf '%s\n' "$anchor"
  group_tests "$base" "$CANDIDATES"
}

# Every dirty code path (lib/ test/) currently in the tree, "XY\tpath" porcelain.
dirty_code() { git -C "$REPO" status --porcelain=v1 | grep -E ' (lib|test)/' || true; }

# True if every dirty lib/test path is owned by <base> (i.e. confined to the set).
dirty_confined_to() {
  local base="$1" line path
  while IFS= read -r line; do
    [[ -n "$line" ]] || continue
    path="${line:3}"
    [[ "$(owner_base "$path" "$CANDIDATES")" == "$base" ]] || return 1
  done < <(dirty_code)
  return 0
}

# Revert just the set's files (no list edit) so the candidate can be retried.
revert_set_files() {
  local line xy path
  while IFS= read -r line; do
    [[ -n "$line" ]] || continue
    xy="${line:0:2}"; path="${line:3}"
    case "$xy" in
      '??') rm -f "$REPO/$path" ;;
      *)    git -C "$REPO" checkout -q HEAD -- "$path" 2>/dev/null || rm -f "$REPO/$path" ;;
    esac
  done < <(dirty_code)
}

# Self-heal: a clean-or-resumable tree, else abort. Called at the top of each
# iteration. docs/_verdict is transient (gitignored) and always ignorable.
self_heal() {
  rm -f "$VERDICT"
  dirty_code | grep -q . || return 0   # clean → nothing to do

  local anchor base; anchor="$(top_anchor)"; base="$(rule_base "$anchor")"
  if [[ -n "$anchor" ]] && dirty_confined_to "$base"; then
    log "recovering interrupted iteration for '${base}' — reverting in-set files"
    revert_set_files
    dirty_code | grep -q . && die "tree still dirty after in-set revert — aborting"
  else
    git -C "$REPO" status --short >&2
    die "unexpected dirty tree (not confined to the top candidate) — aborting"
  fi
}

# Build the briefing text for the session and set BRIEFING_MODE (greenfield|delta).
BRIEFING_MODE=""
build_briefing() {
  local anchor="$1" kind="$2"
  local -a paths new=() modified=()
  mapfile -t paths < <(set_paths "$anchor")

  local p st
  for p in "${paths[@]}"; do
    st="$(git -C "$REPO" status --porcelain=v1 -- "$p")"
    [[ -z "$st" ]] && continue
    case "${st:0:2}" in
      '??') new+=("$p") ;;
      *)    modified+=("$p") ;;
    esac
  done

  if [[ ${#modified[@]} -gt 0 ]]; then BRIEFING_MODE="delta"; else BRIEFING_MODE="greenfield"; fi

  rlog CLASSIFY "mode=${BRIEFING_MODE} (new=${#new[@]}, modified=${#modified[@]})"
  local f
  for f in "${new[@]}"; do rlog CLASSIFY "  new:      ${f}"; done
  for f in "${modified[@]}"; do rlog CLASSIFY "  modified: ${f}"; done

  {
    echo "# Set briefing"
    echo "Anchor: ${anchor}"
    echo "Kind:   ${kind}"
    echo "Mode:   ${BRIEFING_MODE}"
    echo
    if [[ ${#new[@]} -gt 0 ]]; then
      echo "New files (greenfield — review from scratch):"
      printf '  - %s\n' "${new[@]}"
    fi
    if [[ ${#modified[@]} -gt 0 ]]; then
      echo "Modified files (DELTA — this rule is already live; judge ONLY the change below):"
      printf '  - %s\n' "${modified[@]}"
      echo
      echo "## Evolution's change vs the accepted/main version"
      echo '```diff'
      git -C "$REPO" diff -- "${modified[@]}"
      echo '```'
    fi
  }
}

# Run one sandboxed session. $1 anchor, $2 kind, $3 briefing text.
run_session() {
  local anchor="$1" kind="$2" briefing="$3" prompt
  prompt="$(cat "$PROMPT")"$'\n\n'"$briefing"$'\n\n'"MODE: ${BRIEFING_MODE}"$'\n'"ANCHOR: ${anchor}"$'\n'"KIND: ${kind}"

  local -a model_args=()
  [[ -n "$CLAUDE_MODEL" ]] && model_args=(--model "$CLAUDE_MODEL")

  rlog SESSION "starting claude (mode=${BRIEFING_MODE}, model=${CLAUDE_MODEL:-default}, prompt ${#prompt} chars)"
  rlog SESSION "----- agent transcript -----"
  local rc=0
  ( cd "$REPO" && claude -p "$prompt" --permission-mode acceptEdits \
      --allowedTools "$ALLOWED_TOOLS" "${model_args[@]}" ) || rc=$?
  G_SESSION_RC="$rc"
  rlog SESSION "----- end transcript (claude exit=${rc}) -----"
  [[ "$rc" -eq 0 ]] || log "warning: claude session exited non-zero (verdict still checked)"
}

# Per-kind ACCEPT re-verify gate. Returns 0 to accept, 1 to route to followup.
# On failure sets G_GATE_REASON to the specific check that failed.
gate_fail() { G_GATE_REASON="$1"; rlog GATE "FAIL ✗ $1"; log "gate: $1"; return 1; }
gate_accept() {
  local base="$1" kind="$2" rule="lib/${kind}/${base}.ex" t="test/${kind}"
  G_GATE_REASON=""; rm -f "$MIXLOG"
  rlog GATE "begin re-verify gate (kind=${kind})"

  # (a) the rule file must exist and NOT be a stub (the fix must be real).
  [[ -f "$REPO/$rule" ]]      || { gate_fail "rule file missing: $rule"; return 1; }
  rlog GATE "(a) rule file present: ${rule}"
  if is_unfixable_stub "$REPO/$rule"; then gate_fail "fix is not real (still a stub)"; return 1; fi
  rlog GATE "(a) fix is real (not a check-only stub): PASS ✓"

  # (b) test shape by kind.
  case "$kind" in
    pattern)
      [[ -f "$REPO/$t/${base}_check_test.exs" && -f "$REPO/$t/${base}_fix_test.exs" ]] \
        || { gate_fail "pattern needs ${base}_check_test.exs + ${base}_fix_test.exs"; return 1; }
      rlog GATE "(b) test shape: PASS ✓ — ${base}_check_test.exs + ${base}_fix_test.exs present"
      # Delete a superseded single <base>_test.exs now that the split pair exists,
      # BEFORE running mix test, so the suite count matches the committed state.
      if [[ -f "$REPO/$t/${base}_test.exs" ]]; then
        if git -C "$REPO" ls-files --error-unmatch "$t/${base}_test.exs" >/dev/null 2>&1; then
          git -C "$REPO" rm -q "$t/${base}_test.exs"
        else
          rm -f "$REPO/$t/${base}_test.exs"
        fi
        rlog GATE "(b) deleted superseded single ${base}_test.exs (split pair supersedes it)"
      fi ;;
    semantic)
      compgen -G "$REPO/$t/${base}*_check_test.exs" >/dev/null \
        && compgen -G "$REPO/$t/${base}*_fix_test.exs" >/dev/null \
        || { gate_fail "semantic needs ≥1 ${base}*_check_test + ≥1 ${base}*_fix_test"; return 1; }
      rlog GATE "(b) test shape: PASS ✓ — ${base}*_check_test + ${base}*_fix_test present" ;;
    syntax)
      { [[ -f "$REPO/$t/${base}_analyze_test.exs" && -f "$REPO/$t/${base}_fix_test.exs" ]] \
        || [[ -f "$REPO/$t/${base}_test.exs" ]]; } \
        || { gate_fail "syntax needs analyze+fix or a single ${base}_test.exs"; return 1; }
      rlog GATE "(b) test shape: PASS ✓ — analyze+fix or single test present" ;;
    *) gate_fail "unknown kind $kind"; return 1 ;;
  esac

  # (b2) informational: report the =~ / \n-escaped state of the fix tests.
  scan_fix_tests "$base" "$kind"

  # (c) confined diff: nothing outside the set changed.
  dirty_confined_to "$base" || { gate_fail "changes outside the set"; return 1; }
  rlog GATE "(c) confined diff: PASS ✓ — changed: $(dirty_code | sed 's/^...//' | tr '\n' ' ')"

  # (d) full suite green (last — the expensive check).
  rlog GATE "(d) mix test: running full suite…"
  ( cd "$REPO" && mix test >"$MIXLOG" 2>&1 ) \
    || { gate_fail "mix test failed (suite $(suite_summary))"; return 1; }
  rlog GATE "(d) mix test: PASS ✓ — $(suite_summary)"
  rlog GATE "RESULT: ACCEPT (all checks pass)"
  return 0
}

accept_commit() {
  local base="$1" kind="$2" anchor="$3" t="test/${kind}"
  # (the superseded single <base>_test.exs was already removed in the gate.)

  "$SCRIPT_DIR/remove_from_list_keep_files.sh" "$anchor" >/dev/null
  rlog ACCEPT "stripped set lines from candidates.md (kept files)"

  # Stage the rule, all its test files (incl. any deletion), and the list.
  git -C "$REPO" add -- "lib/${kind}/${base}.ex" >/dev/null 2>&1 || true
  git -C "$REPO" add -A -- "$t/${base}"* >/dev/null 2>&1 || true
  git -C "$REPO" add -- "$CANDIDATES" >/dev/null
  git -C "$REPO" commit -q -m "${base}: accepted"
  G_FILES="$(diffstat_head)"; G_SUITE="$(suite_summary)"
  rlog ACCEPT "committed '${base}: accepted' (${G_FILES}, suite ${G_SUITE})"
  do_push "${base}: accepted"
  rlog PUSH "${G_PUSH}"
}

followup() {
  local base="$1" anchor="$2" reason="$3"
  reason="$(echo "$reason" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
  [[ -n "$reason" ]] || reason="unspecified"

  local -a paths; mapfile -t paths < <(set_paths "$anchor")

  # Revert ALL of the iteration's dirty lib/test files (the copied set files plus
  # any split tests the agent created) and strip their lines from candidates.md.
  # Auto-detect (no args) so agent-created files are cleaned too; the iteration
  # started clean, so the dirty set is exactly this candidate's files.
  rlog FOLLOWUP "reason: ${reason}"
  "$SCRIPT_DIR/remove_from_list_revert_files.sh" >/dev/null 2>&1 || true
  rlog FOLLOWUP "reverted in-set files + stripped ${#paths[@]} set line(s) from candidates.md"

  {
    echo "## ${base} — $(date +%F)"
    echo "- Files:"; printf "  - \`%s\`\n" "${paths[@]}"
    echo "- Reason: ${reason}"
    echo
  } >> "$FOLLOWUP"

  git -C "$REPO" add -- "$CANDIDATES" "$FOLLOWUP" >/dev/null
  git -C "$REPO" commit -q -m "${base}: followup — ${reason}"
  G_FILES="reverted ${#paths[@]}f"
  rlog FOLLOWUP "committed '${base}: followup — ${reason}'"
  do_push "${base}: followup"
  rlog PUSH "${G_PUSH}"
}

# Orphan test anchor (a test/ line with no owning rule): straight to followup, no
# session, no file copy.
route_orphan() {
  local anchor="$1" base; base="$(rule_base "$anchor")"
  local tmp; tmp="$(mktemp)"
  grep -vxF "$anchor" "$CANDIDATES" > "$tmp" || true
  mv "$tmp" "$CANDIDATES"
  {
    echo "## ${anchor} — $(date +%F)"
    echo "- Reason: orphan test — no owning rule in tree or sister."
    echo
  } >> "$FOLLOWUP"
  git -C "$REPO" add -- "$CANDIDATES" "$FOLLOWUP" >/dev/null
  git -C "$REPO" commit -q -m "${base}: followup — orphan test"
  rlog FOLLOWUP "orphan test → followup.md, stripped from candidates.md, committed"
  do_push "orphan ${anchor}"
  rlog PUSH "${G_PUSH}"
}

# Does a candidate test anchor have an owning rule anywhere (queue, tree, sister)?
rule_exists_for() {
  local anchor="$1" kind base
  kind="$(rule_kind "$anchor")"; base="$(rule_base "$anchor")"
  [[ -n "$kind" ]] || return 1
  local rel="lib/${kind}/${base}.ex"
  grep -qxF "$rel" "$CANDIDATES" && return 0
  [[ -f "$REPO/$rel" || -f "$SISTER/$rel" ]]
}

main() {
  local iter=0 retry=0 prev_anchor=""
  while :; do
    self_heal
    if list_empty; then log "done — candidates.md empty"; break; fi
    if (( CAP > 0 && iter >= CAP )); then log "cap ${CAP} reached"; break; fi

    local anchor kind base rowlog
    anchor="$(top_anchor)"
    # retry counter is per-row: reset whenever the top candidate changes.
    [[ "$anchor" == "$prev_anchor" ]] || retry=0
    prev_anchor="$anchor"

    # reset per-row digest state
    G_ROW=$((iter + 1)); G_MODE=""; G_VERDICT=""; G_REASON=""
    G_FILES=""; G_SUITE=""; G_PUSH=""; G_LB="$(count_list)"; G_SESSION_RC=0

    # Orphan / global-suite test anchor → followup, no session.
    if [[ "$anchor" == test/* ]]; then
      if rule_exists_for "$anchor"; then
        die "test anchor '${anchor}' has an owning rule but sits above it in the list — fix ordering"
      fi
      G_BASE="$(rule_base "$anchor")"; G_KIND="$(rule_kind "$anchor")"; G_VERDICT="ORPHAN"
      ROWLOG="$LOGDIR/${G_BASE}.log"; : > "$ROWLOG"
      rlog START "row ${G_ROW}: orphan test anchor=${anchor} (no owning rule)"
      route_orphan "$anchor"
      G_LA="$(count_list)"
      rlog DONE "ORPHAN→followup | list ${G_LB}→${G_LA} | ${G_PUSH:-no-push}"
      row_summary
      iter=$((iter + 1)); continue
    fi

    kind="$(rule_kind "$anchor")"
    [[ -n "$kind" ]] || die "cannot derive kind from anchor: ${anchor}"
    base="$(rule_base "$anchor")"
    G_BASE="$base"; G_KIND="$kind"
    rowlog="$LOGDIR/${base}.log"; : > "$rowlog"
    ROWLOG="$rowlog"
    rlog START "row ${G_ROW}: anchor=${anchor} kind=${kind} (queue: ${G_LB} left)"
    log "▶ Started $(date '+%H:%M') — set '${base}' (${kind}), ${G_LB} left in queue${retry:+}$([[ $retry -gt 0 ]] && echo " [retry #${retry}]")  (log: ${rowlog})"

    rlog COPY "copying set from sister…"
    "$SCRIPT_DIR/copy_next_candidate.sh" >>"$rowlog" 2>&1 \
      || die "copy_next_candidate.sh failed for ${anchor} (see $rowlog)"
    rlog COPY "set files: $(set_paths "$anchor" | tr '\n' ' ')"

    # Pre-agent snapshot of the shipped fix tests (so the log shows what the agent
    # started with — e.g. how many =~ it needs to convert).
    rlog SCAN "shipped fix tests (pre-agent):"
    scan_fix_tests "$base" "$kind"

    # build_briefing runs in a subshell here, so read its mode back from the
    # briefing text (the body carries "Mode: <greenfield|delta>") and re-export it
    # for run_session's trailing MODE line.
    local briefing; briefing="$(build_briefing "$anchor" "$kind" 2>>"$rowlog")"
    G_MODE="$(awk '/^Mode:/{print $2; exit}' <<<"$briefing")"
    BRIEFING_MODE="$G_MODE"
    rlog BRIEF "briefing built (mode=${G_MODE}, $(wc -c <<<"$briefing") chars)"
    rm -f "$VERDICT"
    run_session "$anchor" "$kind" "$briefing" >>"$rowlog" 2>&1

    local verdict; verdict="$(head -n1 "$VERDICT" 2>/dev/null || true)"
    rlog VERDICT "${verdict:-<missing _verdict file>}"
    case "$verdict" in
      ACCEPT)
        if gate_accept "$base" "$kind"; then
          G_VERDICT="ACCEPT"; accept_commit "$base" "$kind" "$anchor"
        else
          G_VERDICT="FOLLOWUP"; G_REASON="failed gate: ${G_GATE_REASON}"
          followup "$base" "$anchor" "failed accept gate (${G_GATE_REASON})"
        fi ;;
      FOLLOWUP:*) G_VERDICT="FOLLOWUP"; G_REASON="${verdict#FOLLOWUP:}"
                  followup "$base" "$anchor" "${verdict#FOLLOWUP:}" ;;
      *)
        # No usable verdict → TRANSIENT agent error (crash, token limit, killed
        # mid-run), NOT a real decision. Do NOT followup. Revert the in-set files
        # and STAY on this row, retrying with backoff (15/30/45/60, then hourly)
        # until Claude recovers. The candidate is left untouched in candidates.md.
        retry=$((retry + 1))
        local mins=$(( retry * 15 )); (( mins > 60 )) && mins=60
        local secs=$(( mins * 60 ))
        # test hook: REVIEW_RETRY_STEP_S shortens the backoff (seconds per step).
        [[ -n "${REVIEW_RETRY_STEP_S:-}" ]] && secs=$(( retry * REVIEW_RETRY_STEP_S ))
        revert_set_files
        rm -f "$VERDICT"
        G_VERDICT="RETRY"; G_REASON="no verdict (agent error/token-limit, claude exit=${G_SESSION_RC})"
        G_LA="$(count_list)"
        rlog RETRY "no verdict — reverted in-set files; retry #${retry} in ${mins} min (staying on this row)"
        row_summary
        local rs; rs="$(date -d "+${mins} minutes +30 seconds" '+%H:%M' 2>/dev/null || date '+%H:%M')"
        log "⚠ No verdict from Claude on '${base}' (agent error/token-limit, exit=${G_SESSION_RC}) — NOT a followup; staying on this row."
        log "Retry #${retry} for '${base}' in ${mins} minutes (≈ ${rs}). Will keep retrying until Claude recovers; Ctrl-C to stop."
        sleep "$secs"
        continue ;;
    esac

    retry=0   # row completed (accepted or genuine followup) — clear retry backoff
    G_LA="$(count_list)"
    rlog DONE "${G_VERDICT}${G_REASON:+: $G_REASON} | files ${G_FILES} | suite ${G_SUITE:-n/a} | list ${G_LB}→${G_LA} | ${G_PUSH:-no-push}"
    row_summary
    rm -f "$VERDICT"
    iter=$((iter + 1))
    list_empty && { log "done — candidates.md empty"; break; }
    (( CAP > 0 && iter >= CAP )) && { log "cap ${CAP} reached"; break; }
    if (( WAIT_MIN > 0 )); then
      local resume; resume="$(date -d "+${WAIT_MIN} minutes +30 seconds" '+%H:%M' 2>/dev/null || date '+%H:%M')"
      log "Waiting ${WAIT_MIN} minutes before the next set ( ${G_LA} left in queue )…"
      log "Next set starts ≈ ${resume}. Not crashed — sleeping; Ctrl-C to stop."
      sleep "$((WAIT_MIN * 60))"
    fi
  done
}

# Run main unless sourced (sourcing exposes the functions for testing).
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main
fi
