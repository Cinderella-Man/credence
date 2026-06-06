#!/usr/bin/env bash
#
# resurrect_loop.sh — orchestrator for the stage-3 followup-resurrection loop.
#
# A share-nothing re-examination of the rules rejected into ../followup.md by
# stages 1 and 2. The loop drains followup.md DIRECTLY — there is no intermediate
# flat queue. A "row" is one resurrectable `## <base>` section of followup.md (it
# has a `lib/(pattern|semantic|syntax)/*.ex` path, the rule exists in $SISTER, and
# it bears no DONE/REJECTED marker). Each row drives one fresh, sandboxed (no-git)
# Claude session; the wrapper owns ALL git.
#
# The session's output channel is ../_verdict. It is ONE line for ACCEPT /
# UNFIXABLE / KEEP; for PROPOSE_SWITCH_NEW it is a header line FOLLOWED BY a design
# payload (`### Assumption` + `### Rule` sections); for PROPOSE_SWITCH_REUSE it is a
# header line followed by an `### Rule` section only. A FIVE-way verdict, all of
# which (except KEEP) remove the resolved `## <base>` section from followup.md:
#
#   ACCEPT                       → gate → keep files (rule lands in the tree),
#                                  drain section, commit "<base>: resurrected", push.
#                                  Record = the tree + git log (no ledger file).
#   PROPOSE_SWITCH_NEW: n | why  → revert; append the `### Assumption` block to
#                                  ../proposed_assumptions.md AND a mapping row to
#                                  ../proposed_rules_requiring_assumptions.md; drain
#                                  section; commit "<base>: switch proposed (n)".
#   PROPOSE_SWITCH_REUSE: n | why→ revert; append a mapping row ONLY (n must head the
#                                  catalog); drain section; commit
#                                  "<base>: reuses proposed switch (n)".
#   UNFIXABLE: why               → revert; append ../stage3_unfixable.md; drain
#                                  section; commit "<base>: confirmed unfixable (stage 3)".
#   KEEP: why                    → revert; LEAVE the section in followup.md (it is the
#                                  human-attention residue) and skip it for the rest
#                                  of this run. No ledger, no commit.
#   gate-fail / unrecognized     → routed to KEEP (never a silent promote).
#   no verdict (crash/token-limit) OR a confused-session signal → TRANSIENT: revert,
#                                  stay on the row, retry with backoff.
#
# followup.md drains to only the entries Stage 3 cannot act on (KEEP'd + the
# skip-listed narrative entries: global suites, DONE/REJECTED blocks, orphans).
#
# Usage:   resurrect_loop.sh [cap] [wait_min]
#   cap        max iterations (0 = run until nothing resurrectable is left; default 0)
#   wait_min   minutes to sleep between iterations (default 15)
# Env:
#   SISTER=/path     sister checkout (default ../credence_evolution)
#   CLAUDE_MODEL     optional --model for the session
#   LIST=1           print the pending resurrectable rows and exit (no session)
#
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$SCRIPT_DIR"/../.. && pwd)"
# shellcheck source=resurrect_lib.sh
source "$SCRIPT_DIR/resurrect_lib.sh"

FOLLOWUP="$REPO/maintainer_tools/followup.md"          # the queue: drained as we go
STAGE1_CANDIDATES="$REPO/maintainer_tools/candidates.md"
STAGE2_CANDIDATES="$REPO/maintainer_tools/unfixable_unreviewed.md"
PROPOSED_ASSUMPTIONS="$REPO/maintainer_tools/proposed_assumptions.md"
PROPOSED_RULES="$REPO/maintainer_tools/proposed_rules_requiring_assumptions.md"
STAGE3_UNFIXABLE="$REPO/maintainer_tools/stage3_unfixable.md"
ASSUMPTIONS_LIB="$REPO/lib/assumptions.ex"
VERDICT="$REPO/maintainer_tools/_verdict"
PROMPT="$SCRIPT_DIR/resurrect_prompt.md"
SISTER="${SISTER:-$(cd "$REPO/.." && pwd)/credence_evolution}"
CLAUDE_MODEL="${CLAUDE_MODEL:-}"

CAP="${1:-0}"
WAIT_MIN="${2:-15}"

ALLOWED_TOOLS="Read Edit Write Grep Glob Bash(mix test:*) Bash(mix format:*) Bash(elixir:*)"

for f in "$FOLLOWUP" "$PROPOSED_ASSUMPTIONS" "$PROPOSED_RULES" "$STAGE3_UNFIXABLE" \
         "$ASSUMPTIONS_LIB" "$PROMPT"; do
  [[ -f "$f" ]] || { echo "error: required file not found: $f" >&2; exit 1; }
done
[[ -d "$SISTER" ]] || { echo "error: sister dir not found: $SISTER" >&2; exit 1; }

# Startup guard: stage 3 runs only after BOTH upstream queues have drained
# (followup.md is appended by stages 1 AND 2 — review only after they settle).
for q in "$STAGE1_CANDIDATES" "$STAGE2_CANDIDATES"; do
  if grep -q -v '^[[:space:]]*$' "$q" 2>/dev/null; then
    echo "error: upstream not done — $q is non-empty." >&2
    echo "       Drain stages 1 AND 2 before running stage 3." >&2
    exit 1
  fi
done

log() { printf '[resurrect_loop] %s\n' "$*"; }
die() { printf '[resurrect_loop] FATAL: %s\n' "$*" >&2; exit 1; }

ROWLOG=""
rlog() { [[ -n "$ROWLOG" ]] && printf '[%s] %-9s %s\n' "$(date +%H:%M:%S)" "$1" "${*:2}" >> "$ROWLOG"; return 0; }

# --- followup.md queue ---------------------------------------------------------
# KEEP'd bases: left in followup.md, skipped for the rest of this run.
declare -A SKIP=()
# The current row's set, set by next_set.
NEXT_BASE=""; NEXT_RULE=""; declare -a NEXT_TESTS=()

# Split followup.md into `## ` sections, NUL-delimited (one record per section).
split_sections() {
  awk '
    /^## / { if (n) printf "%s\0", buf; buf=$0"\n"; n=1; next }
    n      { buf=buf $0 "\n" }
    END    { if (n) printf "%s\0", buf }
  ' "$FOLLOWUP"
}

# Echo the `## <base> …` section body of followup.md (header to the next `## `).
followup_section() {
  awk -v base="$1" '
    $0 ~ ("^## " base "([ \t]|$)") { grab=1; print; next }
    /^## /                         { grab=0 }
    grab                           { print }
  ' "$FOLLOWUP"
}
# The one-line `- Reason:` of a section (for the mapping row's "Original reason").
followup_reason() {
  followup_section "$1" | grep -m1 -E '^-[[:space:]]*Reason:' | sed -E 's/^-[[:space:]]*Reason:[[:space:]]*//'
}
# Remove the resolved `## <base> …` section from followup.md (clean whole-section
# delete). Read the section's reason BEFORE calling this — it is gone afterwards.
clear_followup_section() {
  local base="$1" tmp; tmp="$(mktemp)"
  awk -v base="$base" '
    $0 ~ ("^## " base "([ \t]|$)") { skip=1; next }
    /^## /                         { skip=0 }
    !skip                          { print }
  ' "$FOLLOWUP" > "$tmp" && mv "$tmp" "$FOLLOWUP"
}

# Emit "base<TAB>rule" for each resurrectable, non-SKIP section, in file order:
# bears no DONE/REJECTED marker, has a lib/(pattern|semantic|syntax)/*.ex path,
# and that rule exists in $SISTER.
each_resurrectable() {
  local section header base rule
  while IFS= read -r -d '' section; do
    [[ -n "$section" ]] || continue
    header="$(printf '%s\n' "$section" | head -n1)"
    base="${header#\#\# }"; base="${base%%[[:space:]]*}"
    [[ -n "$base" ]] || continue
    [[ -n "${SKIP[$base]:-}" ]] && continue
    printf '%s\n' "$section" | grep -qE 'REJECTED|DONE' && continue
    rule="$(printf '%s\n' "$section" | grep -oE 'lib/(pattern|semantic|syntax)/[A-Za-z0-9_./-]+\.ex' | head -1)"
    [[ -n "$rule" ]] || continue
    [[ -f "$SISTER/$rule" ]] || continue
    printf '%s\t%s\n' "$base" "$rule"
  done < <(split_sections)
}
count_pending() { each_resurrectable | grep -c . || true; }
# Load the first pending row into NEXT_*. Returns 1 when nothing is left.
next_set() {
  local line; line="$(each_resurrectable | head -1)"
  [[ -n "$line" ]] || return 1
  NEXT_BASE="${line%%$'\t'*}"; NEXT_RULE="${line#*$'\t'}"
  mapfile -t NEXT_TESTS < <(
    followup_section "$NEXT_BASE" \
      | grep -oE 'test/(pattern|semantic|syntax)/[A-Za-z0-9_./-]+_test\.exs' | awk '!seen[$0]++')
  return 0
}
# The set's relative paths (rule + tests), one per line.
set_paths() { printf '%s\n' "$NEXT_RULE"; [[ ${#NEXT_TESTS[@]} -gt 0 ]] && printf '%s\n' "${NEXT_TESTS[@]}"; }

# Copy the current set from the sister checkout into the tree.
copy_set() {
  local rel src dst copied=0 missing=0
  for rel in "$NEXT_RULE" "${NEXT_TESTS[@]}"; do
    src="$SISTER/$rel"; dst="$REPO/$rel"
    if [[ -f "$src" ]]; then
      mkdir -p "$(dirname "$dst")"; cp "$src" "$dst"; rlog COPY "  copied  $rel"; copied=$((copied+1))
    else
      rlog COPY "  MISSING $rel (not in \$SISTER)"; missing=$((missing+1))
    fi
  done
  rlog COPY "copied ${copied} file(s)$([[ $missing -gt 0 ]] && echo ", ${missing} missing")"
}

# Informational scan (verbatim stage 2).
WEASEL_RE='^[[:space:]]*(assert|refute)[[:space:]].*(String\.(contains\?|match\?|starts_with\?|ends_with\?|split)|Regex\.(match\?|run|scan))'
NLSTR_RE='[^"]\\n'
scan_fix_tests() {
  local base="$1" kind="$2" t="test/${kind}" ft n p m tot=0 totp=0 totnl=0
  for ft in "$REPO/$t/${base}"*_fix_test.exs "$REPO/$t/${base}_test.exs"; do
    [[ -f "$ft" ]] || continue
    n="$(grep -c '=~' "$ft" 2>/dev/null)"; n="${n:-0}"
    p="$(grep -cE "$WEASEL_RE" "$ft" 2>/dev/null)"; p="${p:-0}"
    m="$(grep -cE "$NLSTR_RE" "$ft" 2>/dev/null)"; m="${m:-0}"
    tot=$((tot + n)); totp=$((totp + p)); totnl=$((totnl + m))
    rlog SCAN "$(basename "$ft"): ${n} =~, ${p} partial-match assert, ${m} \\n-escaped string(s)"
  done
  if (( tot == 0 && totp == 0 && totnl == 0 )); then
    rlog SCAN "fix tests CLEAN — exact whole-string == compares only"
  else
    rlog SCAN "TOTAL ${tot} =~ + ${totp} partial-match assert(s) + ${totnl} \\n-escaped string(s)"
  fi
}

LOGDIR="$SCRIPT_DIR/.review_logs"
mkdir -p "$LOGDIR"
MIXLOG=/tmp/resurrect_loop_mixtest.log

G_ROW=0; G_BASE=""; G_KIND=""; G_MODE=""; G_VERDICT=""; G_REASON=""
G_FILES=""; G_SUITE=""; G_PUSH=""; G_LB=0; G_LA=0; G_GATE_REASON=""; G_SESSION_RC=0
G_TRANSIENT=""

suite_summary() {
  local line tests fails
  [[ -f "$MIXLOG" ]] || { echo ""; return; }
  line="$(grep -oE '[0-9]+ tests?, [0-9]+ failures?' "$MIXLOG" | tail -1)"
  [[ -n "$line" ]] || { echo ""; return; }
  tests="$(grep -oE '^[0-9]+' <<<"$line")"
  fails="$(grep -oE '[0-9]+ failures?' <<<"$line" | grep -oE '[0-9]+')"
  if [[ "$fails" == 0 ]]; then echo "${tests}✓"; else echo "${tests}/${fails}✗"; fi
}

diffstat_head() {
  local stat ins del nf
  stat="$(git -C "$REPO" show --shortstat --format= HEAD | tail -1)"
  ins="$(grep -oE '[0-9]+ insertion' <<<"$stat" | grep -oE '[0-9]+')"
  del="$(grep -oE '[0-9]+ deletion'  <<<"$stat" | grep -oE '[0-9]+')"
  nf="$(git -C "$REPO" show --stat --format= HEAD | grep -c '|')"
  echo "${nf}f +${ins:-0}/-${del:-0}"
}

do_push() {
  if git -C "$REPO" push -q; then G_PUSH="pushed"
  else G_PUSH="local"; log "warning: push failed for $1 (commit is local)"; fi
}

row_summary() {
  local sym
  case "$G_VERDICT" in
    ACCEPT)        sym="✓" ;;
    PROPOSE_NEW)   sym="⊕" ;;
    PROPOSE_REUSE) sym="⊜" ;;
    UNFIXABLE)     sym="⊘" ;;
    KEEP)          sym="✗" ;;
    RETRY)         sym="↻" ;;
    *)             sym="?" ;;
  esac
  local line="${sym} row ${G_ROW}  ${G_BASE} (${G_KIND}${G_MODE:+/$G_MODE})  ${G_VERDICT}"
  [[ -n "$G_REASON" ]] && line+=": ${G_REASON:0:90}"
  [[ -n "$G_FILES"  ]] && line+="  | ${G_FILES}"
  [[ -n "$G_SUITE"  ]] && line+="  | suite ${G_SUITE}"
  line+="  | pending ${G_LB}→${G_LA}"
  [[ -n "$G_PUSH"   ]] && line+="  | ${G_PUSH}"
  printf '%s\n' "$line"
}

dirty_code() { git -C "$REPO" status --porcelain=v1 | grep -E ' (lib|test)/' || true; }

# True if every dirty lib/test path belongs to <base> (basename is <base>.ex or
# starts with "<base>_"). Single-base check — no global rule list needed.
confined_to_base() {
  local base="$1" line path bn
  while IFS= read -r line; do
    [[ -n "$line" ]] || continue
    path="${line:3}"; bn="${path##*/}"
    case "$bn" in "${base}.ex" | "${base}_"*) ;; *) return 1 ;; esac
  done < <(dirty_code)
  return 0
}

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

self_heal() {
  rm -f "$VERDICT"
  dirty_code | grep -q . || return 0
  # The interrupted row is the current top section (SKIP is fresh on restart).
  if next_set && confined_to_base "$NEXT_BASE"; then
    log "recovering interrupted iteration for '${NEXT_BASE}' — reverting in-set files"
    revert_set_files
    dirty_code | grep -q . && die "tree still dirty after in-set revert — aborting"
  else
    git -C "$REPO" status --short >&2
    die "unexpected dirty tree (not confined to the top resurrectable section) — aborting"
  fi
}

BRIEFING_MODE=""
build_briefing() {
  local base="$1" kind="$2"
  local -a paths new=() modified=()
  mapfile -t paths < <(set_paths)

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

  {
    echo "# Set briefing"
    echo "Anchor: ${NEXT_RULE}"
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
    echo
    echo "## Original followup entry — why this rule was rejected (your starting hypothesis)"
    followup_section "$base"
    echo
    echo "## Approved safety switches — lib/assumptions.ex (the rubric for what a VALID assumption is)"
    echo '```elixir'
    cat "$ASSUMPTIONS_LIB"
    echo '```'
    echo
    echo "## Pending proposed assumptions — the dedup catalog"
    echo "If one of these promises, UNCHANGED, fully covers your rule's residual divergence,"
    echo "REUSE it (PROPOSE_SWITCH_REUSE) — do NOT redesign it. Otherwise propose a NEW one."
    if grep -qE '^## ' "$PROPOSED_ASSUMPTIONS" 2>/dev/null; then
      echo
      cat "$PROPOSED_ASSUMPTIONS"
    else
      echo "_(catalog empty — any switch you need is NEW.)_"
    fi
  }
}

run_session() {
  local kind="$1" briefing="$2" prompt
  prompt="$(cat "$PROMPT")"$'\n\n'"$briefing"$'\n\n'"MODE: ${BRIEFING_MODE}"$'\n'"ANCHOR: ${NEXT_RULE}"$'\n'"KIND: ${kind}"

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

# --- ACCEPT re-verify gate -----------------------------------------------------
gate_fail() { G_GATE_REASON="$1"; rlog GATE "FAIL ✗ $1"; log "gate: $1"; return 1; }
gate_accept() {
  local base="$1" kind="$2" rule="lib/${kind}/${base}.ex" t="test/${kind}"
  G_GATE_REASON=""; rm -f "$MIXLOG"
  rlog GATE "begin re-verify gate (kind=${kind})"

  [[ -f "$REPO/$rule" ]]      || { gate_fail "rule file missing: $rule"; return 1; }
  rlog GATE "(a) rule file present: ${rule}"
  if is_unfixable_stub "$REPO/$rule"; then gate_fail "fix is not real (still a stub)"; return 1; fi
  rlog GATE "(a) fix is real (not a check-only stub): PASS ✓"

  case "$kind" in
    pattern)
      [[ -f "$REPO/$t/${base}_check_test.exs" && -f "$REPO/$t/${base}_fix_test.exs" ]] \
        || { gate_fail "pattern needs ${base}_check_test.exs + ${base}_fix_test.exs"; return 1; }
      rlog GATE "(b) test shape: PASS ✓ — _check + _fix present"
      if [[ -f "$REPO/$t/${base}_test.exs" ]]; then
        if git -C "$REPO" ls-files --error-unmatch "$t/${base}_test.exs" >/dev/null 2>&1; then
          git -C "$REPO" rm -q "$t/${base}_test.exs"
        else
          rm -f "$REPO/$t/${base}_test.exs"
        fi
        rlog GATE "(b) deleted superseded single ${base}_test.exs"
      fi ;;
    semantic)
      compgen -G "$REPO/$t/${base}*_check_test.exs" >/dev/null \
        && compgen -G "$REPO/$t/${base}*_fix_test.exs" >/dev/null \
        || { gate_fail "semantic needs ≥1 ${base}*_check_test + ≥1 ${base}*_fix_test"; return 1; }
      rlog GATE "(b) test shape: PASS ✓" ;;
    syntax)
      { [[ -f "$REPO/$t/${base}_analyze_test.exs" && -f "$REPO/$t/${base}_fix_test.exs" ]] \
        || [[ -f "$REPO/$t/${base}_test.exs" ]]; } \
        || { gate_fail "syntax needs analyze+fix or a single ${base}_test.exs"; return 1; }
      rlog GATE "(b) test shape: PASS ✓" ;;
    *) gate_fail "unknown kind $kind"; return 1 ;;
  esac

  if grep -qE 'def assumptions, do: \[:' "$REPO/$rule"; then
    [[ -f "$REPO/$t/${base}_property_test.exs" ]] \
      || { gate_fail "rule declares assumptions/0 but ${t}/${base}_property_test.exs is missing"; return 1; }
    rlog GATE "(b+) assumptions/0 declared → property test present: PASS ✓"
  fi

  scan_fix_tests "$base" "$kind"

  confined_to_base "$base" || { gate_fail "changes outside the set"; return 1; }
  rlog GATE "(c) confined diff: PASS ✓ — changed: $(dirty_code | sed 's/^...//' | tr '\n' ' ')"

  rlog GATE "(d) mix test: running full suite…"
  ( cd "$REPO" && mix test >"$MIXLOG" 2>&1 ) \
    || { gate_fail "mix test failed (suite $(suite_summary))"; return 1; }
  rlog GATE "(d) mix test: PASS ✓ — $(suite_summary)"
  rlog GATE "RESULT: ACCEPT (all checks pass)"
  return 0
}

# --- verdict payload helpers (design block = _verdict lines 2..EOF) ------------
trim()      { printf '%s' "$1" | sed -E 's/^[[:space:]]*//; s/[[:space:]]*$//'; }
name_of()   { trim "${1%%|*}"; }
reason_of() { case "$1" in *'|'*) trim "${1#*|}" ;; *) echo "" ;; esac; }
catalog_has() { grep -qE "^## $1([[:space:]]|$)" "$PROPOSED_ASSUMPTIONS" 2>/dev/null; }
design()      { tail -n +2 "$VERDICT" 2>/dev/null; }
has_section() {
  design | awk -v want="$1" '
    /^### / { h=$0; sub(/^### /,"",h); sub(/[[:space:]].*$/,"",h); if (h==want) f=1 }
    END     { exit(f?0:1) }'
}
extract_section() {
  design | awk -v want="$1" '
    /^### / { h=$0; sub(/^### /,"",h); sub(/[[:space:]].*$/,"",h); inq=(h==want); next }
    inq     { print }'
}

# Append a per-rule row to the mapping file. Args: base name reason path...
append_mapping_row() {
  local base="$1" name="$2" reason="$3"; shift 3
  local -a paths=("$@")
  {
    echo "## ${base} — $(date +%F)"
    echo "- Assumption: ${name}"
    echo "- Files:"; printf "  - \`%s\`\n" "${paths[@]}"
    echo "- Original reason: ${reason:-unspecified}"
    extract_section Rule
    echo
  } >> "$PROPOSED_RULES"
}

# --- ACCEPT handler -----------------------------------------------------------
accept_commit() {
  local base="$1" kind="$2" t="test/${kind}"
  clear_followup_section "$base"
  git -C "$REPO" add -- "lib/${kind}/${base}.ex" >/dev/null 2>&1 || true
  git -C "$REPO" add -A -- "$t/${base}"* >/dev/null 2>&1 || true
  git -C "$REPO" add -- "$FOLLOWUP" >/dev/null
  git -C "$REPO" commit -q -m "${base}: resurrected"
  G_FILES="$(diffstat_head)"; G_SUITE="$(suite_summary)"
  rlog ACCEPT "committed '${base}: resurrected' (${G_FILES}, suite ${G_SUITE})"
  do_push "${base}: resurrected"
  rlog PUSH "${G_PUSH}"
}

# --- PROPOSE_SWITCH_NEW handler. Returns 1 (transient) on a confused session. --
propose_new() {
  local base="$1" payload="$2"
  local name reason; name="$(name_of "$payload")"; reason="$(reason_of "$payload")"
  G_TRANSIENT=""
  [[ -n "$name" ]]        || { G_TRANSIENT="NEW with empty switch name"; return 1; }
  if catalog_has "$name"; then G_TRANSIENT="NEW names an existing catalog entry '${name}' (use REUSE)"; return 1; fi
  has_section Assumption  || { G_TRANSIENT="NEW missing '### Assumption' design block"; return 1; }
  has_section Rule        || { G_TRANSIENT="NEW missing '### Rule' mapping block"; return 1; }

  local -a paths; mapfile -t paths < <(set_paths)
  rlog PROPOSE "NEW switch '${name}': ${reason}"
  revert_set_files

  {
    echo "## ${name} — $(date +%F)"
    extract_section Assumption
    echo
  } >> "$PROPOSED_ASSUMPTIONS"
  append_mapping_row "$base" "$name" "$(followup_reason "$base")" "${paths[@]}"
  clear_followup_section "$base"

  git -C "$REPO" add -- "$PROPOSED_ASSUMPTIONS" "$PROPOSED_RULES" "$FOLLOWUP" >/dev/null
  git -C "$REPO" commit -q -m "${base}: switch proposed (${name})"
  G_FILES="reverted ${#paths[@]}f, +catalog +mapping"; G_REASON="${name}: ${reason}"
  rlog PROPOSE "committed '${base}: switch proposed (${name})'"
  do_push "${base}: switch proposed (${name})"
  rlog PUSH "${G_PUSH}"
  return 0
}

# --- PROPOSE_SWITCH_REUSE handler. Returns 1 (transient) on a confused session. -
propose_reuse() {
  local base="$1" payload="$2"
  local name reason; name="$(name_of "$payload")"; reason="$(reason_of "$payload")"
  G_TRANSIENT=""
  [[ -n "$name" ]]          || { G_TRANSIENT="REUSE with empty switch name"; return 1; }
  catalog_has "$name"       || { G_TRANSIENT="REUSE names unresolved catalog entry '${name}'"; return 1; }
  if has_section Assumption; then G_TRANSIENT="REUSE carries an '### Assumption' block (reuse, don't redesign)"; return 1; fi
  has_section Rule          || { G_TRANSIENT="REUSE missing '### Rule' mapping block"; return 1; }

  local -a paths; mapfile -t paths < <(set_paths)
  rlog PROPOSE "REUSE switch '${name}': ${reason}"
  revert_set_files

  append_mapping_row "$base" "$name" "$(followup_reason "$base")" "${paths[@]}"
  clear_followup_section "$base"

  git -C "$REPO" add -- "$PROPOSED_RULES" "$FOLLOWUP" >/dev/null
  git -C "$REPO" commit -q -m "${base}: reuses proposed switch (${name})"
  G_FILES="reverted ${#paths[@]}f, +mapping"; G_REASON="${name}: ${reason}"
  rlog PROPOSE "committed '${base}: reuses proposed switch (${name})'"
  do_push "${base}: reuses proposed switch (${name})"
  rlog PUSH "${G_PUSH}"
  return 0
}

# --- UNFIXABLE handler ---------------------------------------------------------
unfixable_record() {
  local base="$1" reason="$2"
  reason="$(trim "$reason")"; [[ -n "$reason" ]] || reason="unspecified"
  local -a paths; mapfile -t paths < <(set_paths)
  revert_set_files
  {
    echo "## ${base} — $(date +%F)"
    echo "- Files:"; printf "  - \`%s\`\n" "${paths[@]}"
    echo "- Reason: ${reason}"
    echo
  } >> "$STAGE3_UNFIXABLE"
  clear_followup_section "$base"
  git -C "$REPO" add -- "$STAGE3_UNFIXABLE" "$FOLLOWUP" >/dev/null
  git -C "$REPO" commit -q -m "${base}: confirmed unfixable (stage 3)"
  G_FILES="reverted ${#paths[@]}f"
  rlog UNFIXABLE "committed '${base}: confirmed unfixable (stage 3)'"
  do_push "${base}: confirmed unfixable (stage 3)"
  rlog PUSH "${G_PUSH}"
}

# --- KEEP handler — revert, leave in followup.md, skip for the rest of the run --
keep_skip() {
  local base="$1" reason="$2"
  reason="$(trim "$reason")"; [[ -n "$reason" ]] || reason="unspecified"
  revert_set_files
  SKIP["$base"]=1
  G_FILES="reverted, left in followup.md"
  rlog KEEP "left '${base}' in followup.md (no ledger); skipped for this run — ${reason}"
}

list_pending() {
  local line base rule n=0
  while IFS= read -r line; do
    [[ -n "$line" ]] || continue
    base="${line%%$'\t'*}"; rule="${line#*$'\t'}"
    n=$((n+1)); printf '%3d  %-50s %s\n' "$n" "$base" "$rule"
  done < <(each_resurrectable)
  echo "— ${n} resurrectable section(s) pending in followup.md"
}

main() {
  local iter=0 retry=0 prev_base=""
  while :; do
    self_heal
    if ! next_set; then log "done — nothing resurrectable left in followup.md"; break; fi
    if (( CAP > 0 && iter >= CAP )); then log "cap ${CAP} reached"; break; fi

    local base="$NEXT_BASE" rule="$NEXT_RULE" kind rowlog
    kind="$(rule_kind "$rule")"
    [[ -n "$kind" ]] || die "cannot derive kind from rule: ${rule}"
    [[ "$base" == "$prev_base" ]] || retry=0
    prev_base="$base"

    G_ROW=$((iter + 1)); G_BASE="$base"; G_KIND="$kind"; G_MODE=""; G_VERDICT=""; G_REASON=""
    G_FILES=""; G_SUITE=""; G_PUSH=""; G_LB="$(count_pending)"; G_SESSION_RC=0; G_TRANSIENT=""

    rowlog="$LOGDIR/${base}.log"; : > "$rowlog"; ROWLOG="$rowlog"
    rlog START "row ${G_ROW}: rule=${rule} kind=${kind} (pending: ${G_LB})"
    log "▶ Started $(date '+%H:%M') — set '${base}' (${kind}), ${G_LB} pending$([[ $retry -gt 0 ]] && echo " [retry #${retry}]")  (log: ${rowlog})"

    rlog COPY "copying set from sister…"
    copy_set
    rlog COPY "set files: $(set_paths | tr '\n' ' ')"

    rlog SCAN "shipped fix tests (pre-agent):"
    scan_fix_tests "$base" "$kind"

    local briefing; briefing="$(build_briefing "$base" "$kind" 2>>"$rowlog")"
    G_MODE="$(awk '/^Mode:/{print $2; exit}' <<<"$briefing")"
    BRIEFING_MODE="$G_MODE"
    rlog BRIEF "briefing built (mode=${G_MODE}, $(wc -c <<<"$briefing") chars)"
    rm -f "$VERDICT"
    run_session "$kind" "$briefing" >>"$rowlog" 2>&1

    local verdict; verdict="$(head -n1 "$VERDICT" 2>/dev/null || true)"
    rlog VERDICT "${verdict:-<missing _verdict file>}"

    local do_transient=0 transient_why=""
    if [[ -z "$verdict" ]]; then
      do_transient=1; transient_why="no verdict (agent error/token-limit, claude exit=${G_SESSION_RC})"
    else
      case "$verdict" in
        ACCEPT)
          if gate_accept "$base" "$kind"; then
            G_VERDICT="ACCEPT"; accept_commit "$base" "$kind"
          else
            G_VERDICT="KEEP"; G_REASON="failed gate: ${G_GATE_REASON}"
            keep_skip "$base" "failed accept gate (${G_GATE_REASON})"
          fi ;;
        PROPOSE_SWITCH_NEW:*)
          if propose_new "$base" "${verdict#PROPOSE_SWITCH_NEW:}"; then G_VERDICT="PROPOSE_NEW"
          else do_transient=1; transient_why="confused session: ${G_TRANSIENT}"; fi ;;
        PROPOSE_SWITCH_REUSE:*)
          if propose_reuse "$base" "${verdict#PROPOSE_SWITCH_REUSE:}"; then G_VERDICT="PROPOSE_REUSE"
          else do_transient=1; transient_why="confused session: ${G_TRANSIENT}"; fi ;;
        UNFIXABLE:*)
          G_VERDICT="UNFIXABLE"; G_REASON="${verdict#UNFIXABLE:}"
          unfixable_record "$base" "${verdict#UNFIXABLE:}" ;;
        KEEP:*)
          G_VERDICT="KEEP"; G_REASON="${verdict#KEEP:}"
          keep_skip "$base" "${verdict#KEEP:}" ;;
        *)
          G_VERDICT="KEEP"; G_REASON="unrecognized verdict"
          keep_skip "$base" "unrecognized verdict: ${verdict}" ;;
      esac
    fi

    if (( do_transient )); then
      retry=$((retry + 1))
      local mins=$(( retry * 15 )); (( mins > 60 )) && mins=60
      local secs=$(( mins * 60 ))
      [[ -n "${REVIEW_RETRY_STEP_S:-}" ]] && secs=$(( retry * REVIEW_RETRY_STEP_S ))
      revert_set_files
      rm -f "$VERDICT"
      G_VERDICT="RETRY"; G_REASON="$transient_why"; G_LA="$(count_pending)"
      rlog RETRY "${transient_why} — reverted; retry #${retry} in ${mins} min"
      row_summary
      local rs; rs="$(date -d "+${mins} minutes +30 seconds" '+%H:%M' 2>/dev/null || date '+%H:%M')"
      log "⚠ Transient on '${base}' (${transient_why}) — staying on this row. Retry #${retry} in ${mins} min (≈ ${rs}). Ctrl-C to stop."
      sleep "$secs"
      continue
    fi

    retry=0
    G_LA="$(count_pending)"
    rlog DONE "${G_VERDICT}${G_REASON:+: $G_REASON} | files ${G_FILES} | suite ${G_SUITE:-n/a} | pending ${G_LB}→${G_LA} | ${G_PUSH:-no-push}"
    row_summary
    rm -f "$VERDICT"
    iter=$((iter + 1))
    next_set || { log "done — nothing resurrectable left in followup.md"; break; }
    (( CAP > 0 && iter >= CAP )) && { log "cap ${CAP} reached"; break; }
    if (( WAIT_MIN > 0 )); then
      local resume; resume="$(date -d "+${WAIT_MIN} minutes +30 seconds" '+%H:%M' 2>/dev/null || date '+%H:%M')"
      log "Waiting ${WAIT_MIN} minutes before the next set ( ${G_LA} pending )… Next ≈ ${resume}. Ctrl-C to stop."
      sleep "$((WAIT_MIN * 60))"
    fi
  done
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  if [[ -n "${LIST:-}" ]]; then list_pending; else main; fi
fi
