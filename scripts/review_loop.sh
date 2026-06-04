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
#   wait_min   minutes to sleep between iterations (default 2)
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
WAIT_MIN="${2:-2}"

ALLOWED_TOOLS="Read Edit Write Grep Glob Bash(mix test:*) Bash(mix format:*) Bash(elixir:*)"

for f in "$CANDIDATES" "$FOLLOWUP" "$PROMPT"; do
  [[ -f "$f" ]] || { echo "error: required file not found: $f" >&2; exit 1; }
done
[[ -d "$SISTER" ]] || { echo "error: sister dir not found: $SISTER" >&2; exit 1; }

log() { printf '[review_loop] %s\n' "$*"; }
die() { printf '[review_loop] FATAL: %s\n' "$*" >&2; exit 1; }

list_empty()  { ! grep -q -v '^[[:space:]]*$' "$CANDIDATES"; }
top_anchor()  { grep -m1 -v '^[[:space:]]*$' "$CANDIDATES" || true; }

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

  ( cd "$REPO" && claude -p "$prompt" --permission-mode acceptEdits \
      --allowedTools "$ALLOWED_TOOLS" "${model_args[@]}" ) || \
    log "warning: claude session exited non-zero (verdict still checked)"
}

# Per-kind ACCEPT re-verify gate. Returns 0 to accept, 1 to route to followup.
gate_accept() {
  local base="$1" kind="$2" rule="lib/${kind}/${base}.ex" t="test/${kind}"

  # (a) the rule file must exist and NOT be a stub (the fix must be real).
  [[ -f "$REPO/$rule" ]]      || { log "gate: rule file missing: $rule"; return 1; }
  if is_unfixable_stub "$REPO/$rule"; then log "gate: fix is not real (still a stub)"; return 1; fi

  # (b) test shape by kind.
  case "$kind" in
    pattern)
      [[ -f "$REPO/$t/${base}_check_test.exs" && -f "$REPO/$t/${base}_fix_test.exs" ]] \
        || { log "gate: pattern needs ${base}_check_test.exs + ${base}_fix_test.exs"; return 1; } ;;
    semantic)
      compgen -G "$REPO/$t/${base}*_check_test.exs" >/dev/null \
        && compgen -G "$REPO/$t/${base}*_fix_test.exs" >/dev/null \
        || { log "gate: semantic needs ≥1 ${base}*_check_test + ≥1 ${base}*_fix_test"; return 1; } ;;
    syntax)
      { [[ -f "$REPO/$t/${base}_analyze_test.exs" && -f "$REPO/$t/${base}_fix_test.exs" ]] \
        || [[ -f "$REPO/$t/${base}_test.exs" ]]; } \
        || { log "gate: syntax needs analyze+fix or a single ${base}_test.exs"; return 1; } ;;
    *) log "gate: unknown kind $kind"; return 1 ;;
  esac

  # (c) confined diff: nothing outside the set changed.
  dirty_confined_to "$base" || { log "gate: changes outside the set — rejecting"; return 1; }

  # (d) full suite green (last — the expensive check).
  ( cd "$REPO" && mix test >/tmp/review_loop_mixtest.log 2>&1 ) \
    || { log "gate: mix test failed (see /tmp/review_loop_mixtest.log)"; return 1; }

  return 0
}

accept_commit() {
  local base="$1" kind="$2" anchor="$3" t="test/${kind}"

  # pattern: delete a superseded single <base>_test.exs now that the split exists.
  if [[ "$kind" == pattern && -f "$REPO/$t/${base}_test.exs" ]]; then
    rm -f "$REPO/$t/${base}_test.exs"
  fi

  "$SCRIPT_DIR/remove_from_list_keep_files.sh" "$anchor" >/dev/null

  # Stage the rule, all its test files (incl. the deletion), and the list.
  git -C "$REPO" add -- "lib/${kind}/${base}.ex" >/dev/null 2>&1 || true
  git -C "$REPO" add -A -- "$t/${base}"* >/dev/null 2>&1 || true
  git -C "$REPO" add -- "$CANDIDATES" >/dev/null
  git -C "$REPO" commit -q -m "${base}: accepted"
  git -C "$REPO" push -q || log "warning: push failed for '${base}: accepted' (commit is local)"
  log "ACCEPTED ${base} (${kind})"
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
  "$SCRIPT_DIR/remove_from_list_revert_files.sh" >/dev/null 2>&1 || true

  {
    echo "## ${base} — $(date +%F)"
    echo "- Files:"; printf "  - \`%s\`\n" "${paths[@]}"
    echo "- Reason: ${reason}"
    echo
  } >> "$FOLLOWUP"

  git -C "$REPO" add -- "$CANDIDATES" "$FOLLOWUP" >/dev/null
  git -C "$REPO" commit -q -m "${base}: followup — ${reason}"
  git -C "$REPO" push -q || log "warning: push failed for '${base}: followup' (commit is local)"
  log "FOLLOWUP ${base} — ${reason}"
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
  git -C "$REPO" push -q || log "warning: push failed for orphan '${anchor}' (commit is local)"
  log "FOLLOWUP (orphan) ${anchor}"
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
  local iter=0
  while :; do
    self_heal
    if list_empty; then log "done — candidates.md empty"; break; fi
    if (( CAP > 0 && iter >= CAP )); then log "cap ${CAP} reached"; break; fi

    local anchor kind base
    anchor="$(top_anchor)"

    # Orphan / global-suite test anchor → followup, no session.
    if [[ "$anchor" == test/* ]]; then
      if rule_exists_for "$anchor"; then
        die "test anchor '${anchor}' has an owning rule but sits above it in the list — fix ordering"
      fi
      route_orphan "$anchor"
      iter=$((iter + 1)); continue
    fi

    kind="$(rule_kind "$anchor")"
    [[ -n "$kind" ]] || die "cannot derive kind from anchor: ${anchor}"
    base="$(rule_base "$anchor")"
    log "set '${base}' (${kind}) — iteration $((iter + 1))"

    "$SCRIPT_DIR/copy_next_candidate.sh" || die "copy_next_candidate.sh failed for ${anchor}"

    local briefing; briefing="$(build_briefing "$anchor" "$kind")"
    rm -f "$VERDICT"
    run_session "$anchor" "$kind" "$briefing"

    local verdict; verdict="$(head -n1 "$VERDICT" 2>/dev/null || true)"
    case "$verdict" in
      ACCEPT)
        if gate_accept "$base" "$kind"; then
          accept_commit "$base" "$kind" "$anchor"
        else
          followup "$base" "$anchor" "failed accept gate"
        fi ;;
      FOLLOWUP:*) followup "$base" "$anchor" "${verdict#FOLLOWUP:}" ;;
      *)          followup "$base" "$anchor" "missing or unparseable verdict" ;;
    esac

    rm -f "$VERDICT"
    iter=$((iter + 1))
    list_empty && { log "done — candidates.md empty"; break; }
    (( CAP > 0 && iter >= CAP )) && { log "cap ${CAP} reached"; break; }
    sleep "$((WAIT_MIN * 60))"
  done
}

# Run main unless sourced (sourcing exposes the functions for testing).
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main
fi
