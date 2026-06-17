# Followup — rules needing human attention

Stage 1 (`stage_1_promote_fixable_rules/review_loop.sh`) appends one section per
set it could not safely promote: no safe fix, duplicate, needs a shared-file
change, type change, or inconclusive. Each entry lists the set's files and the
one-line reason. Work these by hand later.

_No open items._

<!--
Resolved 2026-06-17 — test/pattern/assumptions_filtering_test.exs: NOT an orphan.
It is an end-to-end integration test for the assumptions/switch-filter subsystem
(`:strict`/`:default`/per-switch promises) through the public API — the loop's
per-rule orphan detector false-positived because there is no same-named rule
file. Passes (9 tests) and carries unique coverage (config-precedence changing
real `fix` output; the "filtered rule named in an explicit rules: list warns but
stays filtered" path). Kept. Optional tidy: move to test/ level (alongside
assumptions_test.exs / credence_test.exs) and rename the module off `.Pattern`
so a future scan won't re-flag it.
-->

## avoid_graphemes_enum_count — 2026-06-17
- Files:
  - `lib/pattern/avoid_graphemes_enum_count.ex`
  - `test/pattern/avoid_graphemes_enum_count_check_test.exs`
  - `test/pattern/avoid_graphemes_enum_count_equivalence_test.exs`
  - `test/pattern/avoid_graphemes_enum_count_fix_test.exs`
- Reason: duplicate of no_enum_count_for_length (already flags+fixes Enum.count on String.graphemes/1 as provably-list → length(...)), which with avoid_graphemes_length already reaches the same String.length(x) endpoint; fold/drop needs a cross-file change.

## test/pattern/avoid_graphemes_enum_count_equivalence_test.exs — 2026-06-17
- Reason: orphan test — no owning rule in tree or sister.

