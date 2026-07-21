# Shared-file deltas — handled by hand, not by the review loops

These six files differ between this tree and the sister (`../credence_evolution`,
branch `evolution`) but are **not** per-rule candidate sets: `rule_kind` cannot
route them, and doc 04's queue contract excludes them. They were removed from
`candidates.md` (docs/16 Phase 0.3) and are applied manually per docs/16 Phase 2.
Tick each item off here (change `- [ ]` to `- [x]` with the commit SHA) as it
lands.

## Apply now — before any semantic candidate is reviewed

- [x] (`3a64b6f`) `lib/semantic.ex` — sister commit `5fac292` (row 36): `match_rules/1` →
  `match_rules/2` (receives `source`) + optional per-rule
  `should_report?(diagnostic, source)` callback (via `function_exported?/2`,
  defaulting to true). **Must land before stage 1 reaches the semantic rows** —
  new semantic rules depend on the extension point; without it their tests fail
  and produce spurious FOLLOWUPs.
- [x] (`3a64b6f`) `lib/dsl_guard.ex` — sister commit `42866b8`: deletes an unreachable
  `from_query?` fallback; simplifies an `is_atom(ctx) or is_nil(ctx)` guard
  (nil is an atom — dead branch); one `do:` reformat. No behaviour change.
- [x] (`3a64b6f`) `lib/rule_helpers.ex` — sister commit `42866b8`: deletes the unreachable
  `dsl_partition/4` fallback clause. No behaviour change.
- [x] (`3a64b6f`) `test/dsl_safety_classification_test.exs` — adds `@verified_dsl_safe`
  entries for `prefer_stdlib_gcd` and `no_defp_already_defined_as_def`.
  Safe to pre-apply: the stale-entry check only fires for rules whose fixtures
  were exercised, so entries for not-yet-accepted rules are inert.

## Queue provenance — do NOT regenerate candidates.md this cycle

The staged `candidates.md` (from `b3d7abd`, minus the six files above) is
**authoritative**. `generate_candidates.sh` would rebuild it 15 lines short: its
resolved-base subtraction keys on "base ever had a decision commit", so the
**11 re-review bases** — cycle-1-accepted rules that received new sister deltas
since (`no_destructure_reconstruct`, `no_list_pop_at_for_access`,
`prefer_function_clauses_for_list_patterns`, `prefer_reduce_while_with_halt_value`,
`no_capture_as_bitwise_and`, `no_underscore_in_expression`,
`prefer_explicit_range_step`, `require_defmodule_wrapper`, `undefined_function`,
`unused_variable`, `fix_div_rem`) — would be silently dropped. Verified by
`--dry-run` set-comparison on 2026-07-21. Use `--dry-run` only.

## Deferred — companion commit at rule acceptance

- [ ] `test/credence_test.exs` + `test/fix_showcase_test.exs` — both relax an
  `issues == []` assertion to
  `issues == [:no_private_fn_called_from_macro_quote]` (the new rule reports a
  genuinely-unused defp whose fix is a no-op). **Pre-applying fails the suite**
  (the rule doesn't exist here yet), and the loop's confined-diff gate rightly
  stops the session from touching global tests.
  **Trigger:** the moment stage 1 ACCEPTs `no_private_fn_called_from_macro_quote`,
  apply both hunks as a companion commit (the gate's full `mix test` for that
  row will otherwise go red). If the rule is instead rejected, drop the hunks
  and record the sister's relaxation in the rejection entry.
