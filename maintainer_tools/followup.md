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
