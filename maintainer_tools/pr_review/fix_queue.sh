#!/usr/bin/env bash
#
# fix_queue.sh — the fix ledger (fixes.json): one entry per reviewed file whose
# verdict was FINDINGS. The ledger is DERIVED from manifest.json + findings.md
# (`sync` backfills anything missing), so it can be rebuilt at any point and the
# review loop never needs to know the fix pipeline exists. fix_loop.sh drains
# `status: pending` entries.
#
# Entry key: (path, reviewed_at) — one entry per review of a file, so a file
# that is fixed, refreshed and re-reviewed gets a NEW entry (round 2, 3, …).
# Rounds above FIX_MAX_ROUNDS enqueue as `error` ("round cap") instead of
# pending: review↔fix ping-pong must converge, not spin. A human can override
# with `requeue`.
#
# Usage: fix_queue.sh sync                      # backfill fixes.json
#        fix_queue.sh status                    # digest (read-only, no lock)
#        fix_queue.sh requeue --errors | --skipped | <path>...
# Env:   FIX_MAX_ROUNDS (3)
#        FIX_MIN_SEVERITY (concern) — lowest severity that earns a fix session.
#          A round of pure nits is recorded as `skipped`, not scheduled: it is
#          not worth a ~13-minute session plus a ~4-minute gate, and scheduling
#          it also re-stales the file and buys another review. `nit` restores
#          the old behaviour of fixing everything.
#
# Sourceable: `source fix_queue.sh` defines the functions without running
# anything (fix_loop.sh does this and calls sync_queue under its own lock).
set -uo pipefail

FQ_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FIXES="$FQ_SCRIPT_DIR/fixes.json"
FQ_MANIFEST="$FQ_SCRIPT_DIR/manifest.json"
FQ_FINDINGS="$FQ_SCRIPT_DIR/findings.md"
FIX_MAX_ROUNDS="${FIX_MAX_ROUNDS:-3}"
FIX_MIN_SEVERITY="${FIX_MIN_SEVERITY:-concern}"

fq_log() { printf '[fix_queue] %s\n' "$*"; }
fq_die() { printf '[fix_queue] FATAL: %s\n' "$*" >&2; exit 1; }

fixes_init() {
  [[ -f "$FIXES" ]] && return 0
  printf '{"schema": 1, "entries": []}\n' > "$FIXES"
}

# Atomic fixes.json update (jq → tmp in the same dir → mv), like manifest_set.
fixes_jq() { # $1 = jq program, rest = jq args
  local prog="$1"; shift
  local tmp; tmp="$(mktemp "$FQ_SCRIPT_DIR/.fixes.XXXXXX.json")"
  if jq "$@" "$prog" "$FIXES" > "$tmp"; then
    mv "$tmp" "$FIXES"
  else
    rm -f "$tmp"; fq_die "jq fixes.json update failed"
  fi
}

# fixes_update <path> <reviewed_at> <jq program body> [jq args...]
# Applies the program to the one entry keyed by (path, reviewed_at).
fixes_update() {
  local p="$1" ra="$2" prog="$3"; shift 3
  fixes_jq "(.entries[] | select(.path == \$fq_p and .reviewed_at == \$fq_ra)) |= ($prog)" \
    --arg fq_p "$p" --arg fq_ra "$ra" "$@"
}

# findings_section <path> — echo the LAST review section for <path> from
# findings.md (fix-round resolution sections do not match: their header tail is
# not "(<origin>, <category>)"). Empty output = no section found.
findings_section() {
  awk -v p="$1" '
    /^## / {
      insec = 0
      prefix = "## " p " — "
      if (index($0, prefix) == 1 \
          && $0 ~ /\((added|modified|renamed|deleted|unchanged_rule), [a-z_]+\)$/) {
        insec = 1; buf = ""; next
      }
    }
    insec { buf = buf $0 "\n" }
    END { printf "%s", buf }
  ' "$FQ_FINDINGS"
}

# section_severities <section-text> — one severity per line, in bullet order.
section_severities() {
  grep -E '^- (blocker|concern|nit):' <<<"$1" | sed -E 's/^- ([a-z]+):.*/\1/' || true
}

# schedulable <severities, one per line> — is anything here at or above
# FIX_MIN_SEVERITY? Validates the setting on every call so a typo fails loudly
# at the first row rather than silently scheduling (or skipping) everything.
schedulable() {
  case "$FIX_MIN_SEVERITY" in
    nit)     return 0 ;;
    concern) grep -qE '^(blocker|concern)$' <<<"$1" ;;
    blocker) grep -qE '^blocker$'            <<<"$1" ;;
    *) fq_die "FIX_MIN_SEVERITY must be nit, concern or blocker (got '$FIX_MIN_SEVERITY')" ;;
  esac
}

fixes_append() { # path reviewed_at round severities_json status error(json string or null literal)
  fixes_jq '.entries += [{
      path: $p, reviewed_at: $ra, round: $round, severities: $sevs,
      status: $st, attempts: 0, outcomes: [], commits: [], gate: null,
      needs_human: false, error: $err, enqueued_at: $ts, resolved_at: null}]' \
    --arg p "$1" --arg ra "$2" --argjson round "$3" --argjson sevs "$4" \
    --arg st "$5" --argjson err "$6" --arg ts "$(date -Is)"
}

# sync_queue — every manifest row with verdict FINDINGS gets exactly one ledger
# entry per review. Idempotent; safe to run any time the loop is not.
sync_queue() {
  fixes_init
  [[ -f "$FQ_MANIFEST" ]] || fq_die "no manifest.json — run generate_manifest.sh first"
  local rows path ra
  rows="$(jq -r '.files[] | select(.status == "done" and .verdict == "FINDINGS")
                 | [.path, .reviewed_at] | @tsv' "$FQ_MANIFEST")"
  [[ -z "$rows" ]] && return 0
  while IFS=$'\t' read -r path ra; do
    [[ -n "$path" ]] || continue
    jq -e --arg p "$path" --arg ra "$ra" \
      'any(.entries[]; .path == $p and .reviewed_at == $ra)' "$FIXES" | grep -q true && continue

    # A path already parked at the round cap does not mint a FRESH abandoned
    # entry every time a sibling's commit re-stales it and the reviewer runs
    # again. The cap asked for a human; until one arrives, every later review of
    # this file produces findings nobody will act on, and each one used to land
    # as another `error` row. That is how close_unclosed_doc_heredoc.ex collected
    # rounds 4, 5 AND 6 in the 2026-08-19 run — three abandoned entries, and
    # three ~6-minute review sessions spent to create them.
    #
    # Clear it deliberately with: fix_queue.sh requeue <path>
    if jq -e --arg p "$path" \
         'any(.entries[]; .path == $p and .status == "error"
                          and ((.error // "") | startswith("round cap")))' \
         "$FIXES" | grep -q true; then
      fq_log "not enqueued (already parked at the round cap, awaiting a human): $path"
      continue
    fi

    local nprev round sec sevs sevs_json
    nprev="$(jq --arg p "$path" '[.entries[] | select(.path == $p)] | length' "$FIXES")"
    round=$((nprev + 1))
    sec="$(findings_section "$path")"
    if [[ -z "$sec" ]]; then
      fixes_append "$path" "$ra" "$round" '[]' error \
        '"findings.md has no review section for this file — cannot brief a fix session"'
      fq_log "enqueue SKIPPED (no findings section): $path"
      continue
    fi
    sevs="$(section_severities "$sec")"
    if [[ -z "$sevs" ]]; then
      fixes_append "$path" "$ra" "$round" '[]' error \
        '"no severity bullets parsed from the findings section"'
      fq_log "enqueue SKIPPED (no bullets parsed): $path"
      continue
    fi
    sevs_json="$(jq -R . <<<"$sevs" | jq -cs .)"

    # A round carrying nothing at or above FIX_MIN_SEVERITY is recorded, not
    # scheduled. In the 2026-08-19 run 13 of 30 completed rounds were nits only,
    # and each cost a ~13-minute fix session plus a ~4-minute full-suite gate —
    # 181 minutes, a quarter of the night, for findings the ledger itself grades
    # "harmless if ignored". The findings stay in findings.md; sweep them in one
    # batch at the end rather than one session each.
    #
    # The second-order saving is the larger one: a skipped round commits nothing,
    # so nothing goes stale, so no re-review is triggered either.
    if ! schedulable "$sevs"; then
      fixes_append "$path" "$ra" "$round" "$sevs_json" skipped \
        "\"nothing at or above '$FIX_MIN_SEVERITY' — findings recorded in findings.md, no fix session scheduled\""
      fq_log "not scheduled (all below $FIX_MIN_SEVERITY): $path (round $round, $(wc -l <<<"$sevs") findings)"
      continue
    fi

    if (( round > FIX_MAX_ROUNDS )); then
      fixes_append "$path" "$ra" "$round" "$sevs_json" error \
        "\"round cap ($FIX_MAX_ROUNDS) reached — review and fix keep disagreeing about this file; a human must look. Override with: fix_queue.sh requeue $path\""
      # needs_human is what status.sh actually surfaces; the manifest row stays
      # `done`, so requeue.sh --errors (which selects MANIFEST rows with
      # status == "error") never matched these and never will.
      fixes_update "$path" "$ra" '.needs_human = true'
      fq_log "enqueued as ERROR (round cap): $path (round $round)"
    else
      fixes_append "$path" "$ra" "$round" "$sevs_json" pending null
      fq_log "enqueued: $path (round $round, $(wc -l <<<"$sevs") findings)"
    fi
  done <<<"$rows"
}

queue_status() {
  [[ -f "$FIXES" ]] || { echo "no fixes.json yet — nothing enqueued"; return 0; }
  jq -r '
    (.entries | length) as $n |
    ([.entries[] | select(.status == "pending")] | length) as $p |
    ([.entries[] | select(.status == "done")]    | length) as $d |
    ([.entries[] | select(.status == "error")]   | length) as $e |
    ([.entries[] | select(.status == "skipped")] | length) as $s |
    ([.entries[] | select(.status == "skipped") | .severities[]] | length) as $sf |
    ([.entries[] | .outcomes[]] | group_by(.outcome) | map("\(length) \(.[0].outcome)") | join(" · ")) as $oc |
    "fixes — \($n) entr\(if $n == 1 then "y" else "ies" end): \($p) pending · \($d) done · \($e) error\(if $s > 0 then " · \($s) skipped" else "" end)",
    (if $s > 0 then
      "  skipped:    \($s) round\(if $s == 1 then "" else "s" end) below the severity floor, holding \($sf) finding\(if $sf == 1 then "" else "s" end) — recorded in findings.md, never scheduled.",
      "              sweep them with: FIX_MIN_SEVERITY=nit ./fix_queue.sh requeue --skipped"
     else empty end),
    (if $d > 0 then "  outcomes:   \(if $oc == "" then "none recorded" else $oc end)" else empty end),
    (if any(.entries[]; .needs_human) then
      "  needs a human (deferred findings):",
      (.entries[] | select(.needs_human) | "    \(.path) (round \(.round)) — \([.outcomes[] | select(.outcome == "deferred")] | length) deferred")
     else empty end),
    (if $e > 0 then
      "  errors (fix_queue.sh requeue --errors to retry):",
      (.entries[] | select(.status == "error") | "    \(.path) (round \(.round)) — \(.error)")
     else empty end)
  ' "$FIXES"
}

requeue_fixes() {
  [[ -f "$FIXES" ]] || fq_die "no fixes.json"
  local reset='.status = "pending" | .attempts = 0 | .error = null | .outcomes = [] | .commits = [] | .gate = null | .needs_human = false | .resolved_at = null'
  case "$1" in
    --errors)
      # Entries with zero parsed findings can never brief a session — reviving
      # them would only bounce back to error; they stay parked.
      local skipped
      skipped="$(jq '[.entries[] | select(.status == "error" and (.severities | length) == 0)] | length' "$FIXES")"
      fixes_jq "(.entries[] | select(.status == \"error\" and (.severities | length) > 0)) |= ($reset)"
      fq_log "requeued every error entry$( ((skipped > 0)) && echo " (skipped $skipped with no parsed findings — fix findings.md, delete the entry, resync)")" ;;
    --skipped)
      # The end-of-campaign nit sweep. These were never scheduled because they
      # carry nothing at or above FIX_MIN_SEVERITY, so reviving them under the
      # default floor would have sync_queue skip them straight back. Run this
      # with the floor lowered:  FIX_MIN_SEVERITY=nit ./fix_queue.sh requeue --skipped
      if [[ "$FIX_MIN_SEVERITY" != nit ]]; then
        fq_die "requeue --skipped needs FIX_MIN_SEVERITY=nit, or these entries are simply skipped again (currently '$FIX_MIN_SEVERITY')"
      fi
      local n
      n="$(jq '[.entries[] | select(.status == "skipped")] | length' "$FIXES")"
      (( n > 0 )) || { fq_log "no skipped entries to requeue"; return 0; }
      fixes_jq "(.entries[] | select(.status == \"skipped\")) |= ($reset)"
      fq_log "requeued $n skipped entr$( ((n == 1)) && echo y || echo ies) — run fix_loop.sh with FIX_MIN_SEVERITY=nit too, or sync_queue will re-skip any new rounds" ;;
    *)
      local p
      for p in "$@"; do
        jq -e --arg p "$p" 'any(.entries[]; .path == $p)' "$FIXES" | grep -q true \
          || fq_die "not in fixes.json: $p"
      done
      # Requeue only the LATEST entry per path — older rounds are history.
      for p in "$@"; do
        local ra
        ra="$(jq -r --arg p "$p" '[.entries[] | select(.path == $p)] | max_by(.round) | .reviewed_at' "$FIXES")"
        jq -e --arg p "$p" --arg ra "$ra" \
          'any(.entries[]; .path == $p and .reviewed_at == $ra and (.severities | length) > 0)' "$FIXES" | grep -q true \
          || fq_die "the latest entry for $p has no parsed findings — fix findings.md, delete the entry, then fix_queue.sh sync"
        fixes_update "$p" "$ra" "$reset"
        fq_log "requeued: $p"
      done ;;
  esac
}

fq_main() {
  command -v jq >/dev/null || fq_die "jq not found"
  case "${1:-}" in
    sync)
      exec 9>"$FQ_SCRIPT_DIR/.lock"
      flock -n 9 || fq_die "review_loop/fix_loop is running — stop it first"
      sync_queue ;;
    status) queue_status ;;
    requeue)
      shift; [[ $# -ge 1 ]] || fq_die "usage: fix_queue.sh requeue --errors | --skipped | <path>..."
      exec 9>"$FQ_SCRIPT_DIR/.lock"
      flock -n 9 || fq_die "review_loop/fix_loop is running — stop it first"
      requeue_fixes "$@" ;;
    *) echo "usage: fix_queue.sh sync | status | requeue (--errors | --skipped | <path>...)" >&2; exit 2 ;;
  esac
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  fq_main "$@"
fi
