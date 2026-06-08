#!/usr/bin/env bash
#
# resurrect_lib.sh — shared helpers for the stage-3 followup-resurrection loop.
# Standalone (no cross-stage sourcing). Sourced by resurrect_loop.sh. No side
# effects on source; defines functions only. The loop drains followup.md directly
# (no flat queue), so the queue-specific helpers (group_tests/owner_base) are gone;
# what remains is path→kind/base classification and the unfixable-stub predicate.

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
