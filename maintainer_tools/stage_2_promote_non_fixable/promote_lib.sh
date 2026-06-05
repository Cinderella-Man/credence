#!/usr/bin/env bash
#
# promote_lib.sh — shared helpers for the stage-2 stub-promotion loop.
# A standalone copy of stage 1's review_lib.sh (no cross-stage sourcing).
# Sourced by copy_next_candidate.sh and promote_loop.sh.
# No side effects on source; defines functions only.

# rule_kind <path> — echo the rule kind implied by a lib/<kind>/ or test/<kind>/
# path: pattern | semantic | syntax (empty for anything else).
rule_kind() {
  case "$1" in
    *lib/pattern/* | *test/pattern/*)   echo pattern ;;
    *lib/semantic/* | *test/semantic/*) echo semantic ;;
    *lib/syntax/* | *test/syntax/*)     echo syntax ;;
    *) echo "" ;;
  esac
}

# rule_base <rule_or_test_path> — echo the rule base (filename stem). If the path
# is a test file, strip the trailing _test plus any _check/_fix/_analyze segment.
rule_base() {
  local fname="${1##*/}" stem
  stem="${fname%.exs}"; stem="${stem%.ex}"
  if [[ "$stem" == *_test ]]; then
    stem="${stem%_test}"
    local q
    for q in _check _fix _analyze; do stem="${stem%"$q"}"; done
  fi
  echo "$stem"
}

# group_tests <base> <candidates_file> — echo the test lines in <candidates_file>
# owned by <base> under longest-rule-base-prefix-wins (a test belongs to the rule
# whose base is the LONGEST rule-base prefixing the test's basename at a "_"
# boundary). Stops a short base ("no_filter") from stealing a longer base's
# ("no_filter_then_map") tests.
group_tests() {
  local base="$1" file="$2"
  local -a rule_bases
  mapfile -t rule_bases < <(
    grep -E '^lib/.*\.ex$' "$file" | while IFS= read -r l; do
      local b="${l##*/}"; printf '%s\n' "${b%.ex}"
    done
  )
  grep -E '^test/.*_test\.exs$' "$file" | while IFS= read -r line; do
    local tname="${line##*/}" best="" rb
    case "$tname" in "${base}_"*) ;; *) continue ;; esac
    for rb in "${rule_bases[@]}"; do
      case "$tname" in "${rb}_"*) (( ${#rb} > ${#best} )) && best="$rb" ;; esac
    done
    [[ "$best" == "$base" ]] && printf '%s\n' "$line"
  done
}

# owner_base <path> <candidates_file> — echo the rule base that OWNS <path> under
# the same longest-prefix model as group_tests. For a lib/*.ex path that is the
# rule itself, that's its stem. For a test/*.exs path it is the longest rule-base
# (from <candidates_file>) prefixing the basename at a "_" boundary. Used by the
# loop to decide whether a dirty path belongs to the current set.
owner_base() {
  local path="$1" file="$2" bn
  bn="${path##*/}"
  case "$path" in
    lib/*.ex)
      echo "${bn%.ex}" ;;
    test/*.exs)
      local -a rule_bases
      mapfile -t rule_bases < <(
        grep -E '^lib/.*\.ex$' "$file" | while IFS= read -r l; do
          local b="${l##*/}"; printf '%s\n' "${b%.ex}"
        done
      )
      local best="" rb
      for rb in "${rule_bases[@]}"; do
        case "$bn" in "${rb}_"*) (( ${#rb} > ${#best} )) && best="$rb" ;; esac
      done
      echo "$best" ;;
    *) echo "" ;;
  esac
}

# is_unfixable_stub <rule_file> — the `unfixable_stub?` predicate.
# Return 0 (true) only when the rule is PROVABLY check-only: it has at least one
# fix clause and EVERY fix clause is the verbatim dead form. Strict and
# conservative — any clause that does real work (incl. any multiline body, which
# is never the one-liner dead form) drops the count below total and yields 1
# (false), leaving the rule for the loop's agent to judge. Zero false positives
# is the design goal; under-filtering is fine (the loop is the backstop).
#
#   pattern  → every `def fix_patches(..)` is `do: []`
#   semantic → every `def fix(..)`         is `do: source`   (fix/2)
#   syntax   → every `def fix(..)`         is `do: source`   (fix/1)
is_unfixable_stub() {
  local file="$1" kind total hit
  [[ -f "$file" ]] || return 1
  kind="$(rule_kind "$file")"
  case "$kind" in
    pattern)
      total="$(grep -cE 'def fix_patches\(' "$file")"
      hit="$(grep -cE 'def fix_patches\([^)]*\), *do: *\[\]' "$file")"
      ;;
    semantic | syntax)
      total="$(grep -cE 'def fix\(' "$file")"
      hit="$(grep -cE 'def fix\([^)]*\), *do: *source' "$file")"
      ;;
    *)
      return 1 ;;
  esac
  [[ "$total" -ge 1 && "$hit" -eq "$total" ]]
}
