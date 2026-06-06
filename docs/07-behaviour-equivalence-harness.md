# Behaviour-equivalence test suite — prove every rule's fix preserves behaviour

## Context
~32 rules in `maintainer_tools/unfixable_confirmed.md` + ~44 in `followup.md` were
rejected because a fix **changed behaviour on an input the author never hand-tested**
— a runtime divergence between `eval(original)` and `eval(fixed)` on some witness
(value-kind change, negative index, non-list enumerable raises, multi-codepoint
grapheme, exception type/order, double-eval, sort stability, dropped accumulator,
empty/nil edges). The existing per-rule tests (`_check_test.exs` + `_fix_test.exs`)
are example-based **source-string `==`** checks — they only cover inputs the author
imagined, so they miss exactly these.

**This is NOT a new "harness" or judge.** It is a third kind of per-rule test case,
living in `test/pattern/`, run by plain `mix test` alongside `_check`/`_fix`: run the
before- and after-code over a curated battery of adversarial inputs and assert
identical outcomes (incl. exception parity). Its job in Credence: a **permanent
regression safety net** over all 125 shipped rules (and any future rule).

Because these tests run over **already-shipped** code, the backfill will surface
shipped rules that diverge. **A divergence is a real bug** (decision below): narrow
the rule's safe core or drop the unsafe case — never weaken/hide the test
([[rule-evolution-methodology]]).

**Impact on rule creation (note only — out of scope for this repo):** once the
meta-gate requires an equivalence test per rule, the sister-repo authoring loop,
seeing the gate fail, will write these tests up front — catching behaviour-changing
fixes at creation instead of at review. That benefit is a side effect of the gate
existing here; this document does not modify the creation repo.

**Exemplar already in-tree:** `test/pattern/no_manual_frequencies_fix_test.exs:114-225`
(`eval1` + `assert_preserves` over `@term_lists`/`@string_lists`). This plan
generalizes that one block into shared, mandatory, gate-enforced support.

## Decisions (locked)
1. **Purpose:** regression safety net inside `mix test`; not a separate harness/judge. Creation-repo benefit is a note.
2. **Divergence on a shipped rule = a bug.** Fix/narrow/drop the rule; never `@tag`-skip or weaken the test. Meta-gate stays *soft* (excluded) during backfill so `main` stays mergeable, flips *hard* once the divergence list is empty.
3. **Three coverage tiers** (every rule lands in exactly one — see table):
   - **T1 expression** — fix rewrites a self-contained expression → wrap before/after in `fn <vars> -> expr end`, apply per input.
   - **T2 module-call** — fix is def/module-structural (inline defp, case→heads, manual recursion→Enum, cross-statement) → compile the whole before- and after-**module**, invoke the target function over inputs.
   - **T3a cosmetic** — provably no runtime effect (param rename, attr move, doc text, typespec) → `mark_equivalence_cosmetic(reason)`. Before and after are behaviourally identical.
   - **T3b unconstructible** — behavioural but no self-contained callable example (cross-module/macro/compile-time) → `mark_equivalence_unconstructible(reason)`.
   - **T3c repair** — the firing precondition is a *broken* input (does-not-compile, e.g. a hallucinated guard or a missing `require Logger`; **or** always-fails — compiles but raises on *every* input, e.g. an arg-order bug like `s |> Regex.replace(...)`) → `mark_equivalence_repair(reason)`. **Deliberately NOT behaviour-preserving** — sound because the "before" has no input that yields a valid result; the fix is a *correction*. This is the principled home for the whole "fix broken → working" family (which by definition changes behaviour). The reason must state the broken precondition (and, for always-fails, that *no* input avoids the crash). A rule whose "before" returns a valid—even if undesired—value on some input is NOT a repair: it is a behaviour change and must be narrowed, gated, or dropped (e.g. `no_map_get_sentinel`, dropped). `unconstructible` is the preferred wording for the does-not-compile flavour and stays a distinct mark.
4. **No ETS / no global attestation.** Anti-stub teeth come from `assert_equivalent` itself (asserts rule fires + a rewrite happened + battery ≥ 3). Meta-gate only checks per-rule file existence + that the file references the rule.
5. **In-process eval + `try/rescue/catch`** (no spawn/timeout). Outcome tagged `{:ok,v}` | `{:raise,Module}` | `{:throw|:exit,term}`. Exception compared **module-only** (`compare_messages: true` opt-in). Per-rule timeout wrapper documented as an escape hatch, unused by default.
   - **Value comparison is strict `===`, not `==`** (upgraded after the exemplar's `==`): `6 == 6.0` is true, so `==` would miss int↔float value-kind changes — the doc's #1 rejection class. `===` catches them. Re-verified: all prior filled rules stay green under `===`.
6. **Effect probe is a helper mode, not a phase.** `probe_effects: true` injects an effect-recording expr into the rule's predicate/transform hole (in-eval, via process dict) and asserts effect-trace equality (order + count). Used by the 26 PROBE rules.
7. **Curated batteries only** gate; StreamData stays additive/non-gating (last phase).
8. **Backfill authored** by a throwaway scaffold script under `maintainer_tools/` (reads `default_rules/0`, lifts `_check_test.exs` snippets into skeletons, stamps guessed tier), then a human/agent fill pass tier-by-tier. No `mix` task in `lib`, no loop, no shared-doc edit.

## Files
- add `test/support/behaviour_equivalence.ex` — `Credence.BehaviourEquivalence`: `assert_equivalent/2`, T2 `assert_equivalent_module/2`, `mark_equivalence_cosmetic/1`, `mark_equivalence_unconstructible/1`, `eval_outcome/2`, effect probe. (`test/support` already in `elixirc_paths(:test)`.)
- add `test/support/equivalence_batteries.ex` — curated dimensions by data-shape; reuse `assumption_generators.ex:single_codepoint_string`.
- add `test/equivalence_meta_test.exs` — gate (mirror `test/assumptions_meta_test.exs`): per rule in `Credence.Pattern.default_rules()`, `test/pattern/<snake>_equivalence_test.exs` exists AND references the rule.
- add `test/pattern/<base>_equivalence_test.exs` ×125 (snippets from `_check_test.exs`).
- modify `test/pattern/no_manual_frequencies_fix_test.exs` — port exemplar block to the helper (or move into its new `_equivalence_test.exs`).
- reference (unmodified): `lib/rule_helpers.ex:295` (`apply_rule_fix/3`), `lib/pattern.ex:145` (`default_rules/0`).
- **NOT modified:** `credence_evolution/prompt.md` (other repo, out of scope).

## Support module — `Credence.BehaviourEquivalence`
- `assert_equivalent(before_expr, opts)`, opts = `rule:` module, `vars:` (ordered free-var names; single scalar auto-wrapped), `inputs:` (battery list), `probe_effects:`, `compare_messages:`, `tiny_battery_ok:`. Steps:
  1. assert `rule.check(parse(before)) != []` (rule fires — anti-dead-snippet),
  2. `fixed = RuleHelpers.apply_rule_fix(rule, before)`; assert `fixed != before` (rewrite happened),
  3. assert `length(inputs) >= 3` unless `tiny_battery_ok:`,
  4. compile `fn <vars> -> before end` / `fn <vars> -> fixed end` once each; for every input assert `eval_outcome(orig,in) == eval_outcome(fixed,in)`.
- `assert_equivalent_module(before_module_src, opts)` (T2): opts add `call:` (`{fun, arity}` or builder) — compile both module sources under unique names, apply `fun` over each battery input, compare `eval_outcome`.
- `eval_outcome/2` — `try/rescue/catch` → `{:ok,v}` | `{:raise,mod}` | `{:throw,t}` | `{:exit,t}`. Suppress eval warnings via `ExUnit.CaptureIO` only if noisy.

## Coverage worklist — all 125 rules
Counts (after deep-dive confirmation of every opt-out + borderline):
**T1 = 86, T2 = 37, T3a = 2, T3b = 0.** PROBE (effect-trace) flag on **26**.
Deep-dive converted **6 former opt-outs into genuine behavioural tests** and
**confirmed 1 unsafe shipped rule** (`redundant_list_guard`, below). Only 2 truly-inert
opt-outs remain; nothing is unconstructible.

### Confirmed divergences (shipped-rule bugs found during classification)
- **`redundant_list_guard` — was UNSAFE, now RESOLVED (narrowed via assumption).** Dropping
  `is_list(tail)` from a cons-head guard diverges on the improper list `[1 | 2]` (guarded →
  `:fallthrough`; ungated → `{:matched, 1, 2}`), verified by compiling+running both modules.
  Since the cons pattern never forces `tail` to be a list, there is no clause-shape safe core —
  so the fix is gated behind a new **`proper_lists`** assumption (default on; off under `:strict`),
  exactly mirroring `single_codepoint_graphemes`. Implemented: switch added to
  `Credence.Assumptions`, `assumptions/0` + honest moduledoc/message on the rule,
  `AssumptionGenerators.proper_list/0`, `redundant_list_guard_property_test.exs` (promise proof),
  and the equivalence test now passes in-domain (proper lists) + an out-of-domain `assert_raise`
  demo. Confirmed end-to-end: `:strict` keeps the guard (`Applied: []`), default removes it.
- **`no_sort_then_at` — was UNSAFE, now RESOLVED (empty-safe fix).** `Enum.sort(c) |> Enum.at(0)`
  returns `nil` on an empty collection, but the fix `Enum.min(c)` raises `Enum.EmptyError`
  (same for `at(-1)` → `Enum.max`); non-empty inputs (incl. ties + `1`/`1.0`) all matched.
  Fixed by emitting the empty_fallback form `Enum.min(c, fn -> nil end)` / `Enum.max(c, fn -> nil end)` —
  the maintainer's existing idiom (`no_if_empty_for_enum_min_max`), behaviour-preserving for every
  input with no assumption. Updated: rule fix + moduledoc, ~all `no_sort_then_at_fix_test` expectations,
  equivalence test (battery leads with `[]`). **Follow-on:** sibling `no_sort_for_top_k` (and any
  `sort |> hd/first/at` rule) likely shares the empty hazard — check during its fill.
- **`unnecessary_grapheme_chunking` — was UNSAFE, now RESOLVED (`//1` step).** The fix's range
  `for i <- 0..(String.length(s) - n)` descends when `len < n` (`0..-1` = `[0,-1]`), emitting bogus
  slices instead of `[]`. Fixed by emitting a stepped range `0..(...)//1` (empty for negative end,
  matching `chunk_every(_, n, 1, :discard)`). Behaviour-preserving for every input incl. multi-codepoint
  graphemes; no assumption. Updated rule + moduledoc + fix-test expectations + equivalence test (battery
  covers `len<n`, `len==n`, NFD).
- **`no_sort_for_top_k` — was UNSAFE, now RESOLVED (narrowed + empty-safe).** Two bugs: `sort |> take(1)`
  → `Enum.min` changed return type (list `[min]` vs scalar `min`) — wrong on every input; `hd`/`at(0)`
  diverged on `[]`. Fixed by narrowing to the **`Enum.at(0)` terminal only** (dropped `take(1)` and `hd`
  and their `reverse|>` variants — no behaviour-preserving min form exists for them) and emitting the
  empty_fallback `Enum.min(c, fn -> nil end)` / `Enum.max(...)`. Updated rule + moduledoc + check_test
  (take(1)/hd moved to negative cases) + fix_test + equivalence test. Note: the fallback must be built
  via `Sourceror.parse_string!("fn -> nil end")` — a hand-built `{:fn,...}` AST crashes the formatter
  inside `patches_from_ast_transform` (this rule's render path; `no_sort_then_at` uses postwalk so its
  hand-built node is fine).
- **`prefer_desc_sort_over_negative_take` — was UNSAFE, now RESOLVED (added reverse).** `sort |> take(-3)`
  (n largest ascending) → `sort(:desc) |> take(3)` (descending) reversed the order. Fixed by appending
  `|> Enum.reverse()`, which restores ascending order — behaviour-preserving and still cheaper (`take(n)`
  from the front + reversing n beats `take(-n)` walking the whole list). Updated rule (rebuild pipeline +
  insert reverse) + moduledoc + fix_test + equivalence test + 2 showcase golden tests.
- **`no_keyword_get_integer_key` — REINSTATED as a REPAIR rule (T3c, always-fails).** `Keyword.get(l, <int>)`
  always raises `FunctionClauseError` (the `is_atom(key)` guard) — re-probed exhaustively: 24/24 list×key
  combinations crash, **0** produce a value. The rule fires only on integer *literals* (2-arg form). Since the
  "before" has no valid behaviour on any input, the fix (`-1`→`List.last`, `0`→`List.first`, `n`→`Enum.at`,
  the Python-index intent) is a *correction*, not a behaviour-preserving rewrite — exactly the repair
  category. It was dropped earlier under the old ad-hoc handling; recovered from `103db1b^` and marked
  `mark_equivalence_repair`. (This is the precedent the repair policy now governs uniformly.)
- **`no_identity_float_coercion` + `prefer_erlang_float` — MERGED into `prefer_erlang_float`.**
  The two encoded opposite theories of the same `expr * 1.0` pattern: one *removed* it (turning
  `6.0`→`6` — a value-kind bug), the other *wrapped* it in `:erlang.float/1` (preserving the float).
  Wrapping is the behaviour-preserving one, so `prefer_erlang_float` now handles **all** operand shapes
  (bare var + compound) → `:erlang.float(operand)`, and `no_identity_float_coercion` is deleted
  (124→123 rules; drops its priority-coordination hack). Value-kind is now fully preserved. The only
  residual is the exception *module* on a non-number operand (`ArithmeticError` vs `ArgumentError`) on
  already-crashing code — **maintainer accepted this (error type doesn't matter), so no assumption added.**
  Equivalence test uses a numeric battery (where value-kind risk lives) + a moduledoc note on the
  non-number edge. Updated rule + moduledoc + both rules' check/fix tests merged + 4 showcase golden tests.
- **`no_manual_max` + `no_manual_min` — was UNSAFE on strict forms, now NARROWED.** Both fired on
  strict (`>`/`<`) and non-strict (`>=`/`<=`) comparison forms, but `max`/`min` use `>=`/`<=` and keep
  the first arg on a tie. So `if a > b, do: a, else: b` → `max(a, b)` diverged on equal-value-different-type
  — `max(1, 1.0) == 1` but the manual form yields `1.0` (caught only by the new strict `===`). Narrowed
  both rules to the **non-strict forms only** (the subset that equals `max`/`min` exactly). Updated both
  rules' moduledocs + check/fix tests (strict positives → negatives) + 1 integration golden test.
- **`no_enum_count_for_length` — was UNSAFE (enumerable-type), now NARROWED (no new switch).**
  `Enum.count(x)` → `length(x)` only when `x` is a list (`length(1..5)` raises; `Enum.count(1..5)` is
  `5`). Maintainer chose narrow-over-assumption: the rule now fires only when the arg is **provably a
  list** — a list literal, a `++`, or a (possibly piped) call to a list-returning function (whitelist:
  `Enum.map/filter/sort/...`, `String.graphemes/split/...`, `Map.keys/values`, `List.*`, ...). A bare
  `Enum.count(var)` no longer fires. Added `provably_list?/1` + a `@list_returning` whitelist; updated
  the rule's test (bare-var positives → negatives, structural-context tests given provably-list args)
  + 3 golden tests (bare-var `Enum.count` retained). Gotcha: Sourceror wraps list literals as
  `{:__block__, _, [[...]]}`, so `provably_list?` unwraps that.
- **`no_manual_enum_uniq` — DROPPED (over-eager heuristic, unsafe in almost every shape).** It rewrote a
  manual-uniq `Enum.reduce` → `Enum.uniq(list)` across shapes that are NOT behaviour-preserving — verified:
  bare reduce → `{seen, acc}` tuple vs a list; `reduce |> elem(0)` → reversed list (`[3,2,1]` vs `[1,2,3]`,
  the acc is prepend-built); `reduce |> Enum.reverse()` → `Protocol.UndefinedError` (reverse on a tuple)
  vs a list. Only the full `reduce |> elem(list_idx) |> Enum.reverse()` pipeline is correct, and ~15 of
  the rule's ~22 fix tests asserted the broken shapes. Narrowing to the one safe idiom would gut it and
  require rewriting most of its corpus, so dropped (like `no_keyword_get_integer_key`). Deleted rule +
  check/fix/equivalence tests + 1 dedicated integration test; retargeted the `applied_rules` trace test;
  renamed a stale negative test. 123→122 rules.
- **`prefer_enum_slice` — was UNSAFE on negative/variable amounts, now NARROWED.** `Enum.drop(l, s) |>
  Enum.take(n)` → `Enum.slice(l, s, n)` is equivalent only for **non-negative** `s`, `n`. It fired on
  negatives (`drop(-1) |> take(2)` → `slice(-1, 2)`: `[4]` vs `[1,2]`; `take(-2)` → `slice(_, -2)` raises)
  and on variable amounts (could be negative at runtime). Narrowed to fire only when both amounts are
  **non-negative integer literals** (added `slice_safe?`/`non_neg_int?`). Updated rule + moduledoc +
  check/fix tests (variable-amount positives → literals; field-access + negative cases → negatives).
- **`no_explicit_max_reduce` + `no_explicit_min_reduce` — DROPPED (unsafe, no safe core).** They fire
  only on the 3-arg `Enum.reduce(list, 0, fn x, acc -> max(x, acc) end)` and rewrite to `Enum.max(list)`,
  **dropping the init** — but the init seeds the fold (`reduce([-2,-3], 0, max)` = `0` vs `Enum.max` = `-2`),
  and max/min have **no identity literal** (unlike sum's `0`/product's `1`). Even the 2-arg form (which
  they don't match) diverges from `Enum.max` on value-kind ties (`[1,1.0]` → reduce `1.0` vs `Enum.max` `1`).
  Safe only under a 2-arg rewrite + a number-kind assumption — not worth it; dropped like
  `no_manual_enum_uniq`. (`sum`/`product` reduce are safe — they aggregate, no element-selection, and
  `0`/`1` are identities.) 122→120 rules.
- **`no_map_then_aggregate` — was UNSAFE on max/min, now NARROWED to `:sum`.** `Enum.map(f) |> Enum.sum()`
  → `Enum.reduce(coll, 0, fn x, acc -> acc + f.(x) end)` is correct (identity init, mapper on every
  element). But `Enum.map(f) |> Enum.max()`/`min()` fused to `Enum.reduce/2` whose seed is the *first
  unmapped element* (`[5] |> map(f) |> max()` → `f.(5)`, but the fused reduce gave `5`). Max/min have no
  identity to seed a mapped reduce, so selection can't be fused — `@aggregators` narrowed to `[:sum]`,
  moduledoc + check/fix tests updated (max/min → negatives, structural tests → sum). Same selection-vs-
  aggregation lesson as the dropped `no_explicit_max_reduce`.
- **`hallucinated_guard` — UNCONSTRUCTIBLE.** Replaces a hallucinated guard (`is_pos_integer(x)` →
  `is_integer(x) and x > 0`); the original uses an undefined macro and does not compile, so there is no
  runnable before-code. `mark_equivalence_unconstructible`.
- **`no_map_keys_or_values_for_iteration` — was BROADLY UNSAFE, now NARROWED.** It rewrote
  `Enum.<op>(Map.keys/values(m), f)` → `Enum.<op>(m, fn {k,v} -> ... end)` for ~25 ops, but `Map.keys/1`/
  `Map.values/1` iterate in a *different order* than direct `Enum`-over-map once a map has > 32 keys
  (verified: `Enum.map(Map.values(big40), …)` gives a different list order). Order-dependent ops (`map`,
  `flat_map`, `reduce`, `find`, `at`, `take`, `join`, `group_by`, `each`'s effect order) diverge, and
  `random`/`sample`/`shuffle` are non-deterministic. Narrowed `@fixable_funcs` to the order-independent
  set `[all? any? count empty? frequencies frequencies_by]`; map/filter check tests → negatives.
  (`no_map_keys_enum_lookup` was already restricted to the order-independent `all?`-with-lookup form — safe.)
- **`no_anon_fn_application_in_pipe` — was a BUG (malformed output), now FIXED.** `x |> (fn s -> ... end).()`
  → the old `patches_from_postwalk` patch landed at the `.()` call node, whose Sourceror range starts at
  the `fn` keyword and **excludes the wrapping `(`**, stranding it → the uncompilable `x |> (then(fn ... end)`.
  Rewrote `fix_patches` to patch the `.()` node directly with its range **extended one column left** to
  swallow the `(`, rendered via `render_replacement/2` (layout-meta stripped, so multi-line fns re-render
  cleanly). Verified valid for single / chained / multi-line / in-module forms; a non-pipe `(fn).()` is
  correctly left untouched. Equivalence test filled (value-equivalent — the fn is applied once either way).
- **`no_manual_list_last` — autofix diverged on `[]`, now FIXED.** The hand-rolled `f([val]) -> val;
  f([_|rest]) -> f(rest)` raises on `[]`, but the autofix's `List.last([])` returns **`nil`** — a real
  behaviour change. (The detection requires exactly those 2 clauses, so it can never see a safe `[]→nil`
  base clause.) Changed the autofix — def body, nested calls, and the pipe form (now `|> Enum.reverse() |> hd()`)
  — to `hd(Enum.reverse(list))`, which raises on `[]` like the original (`ArgumentError` vs
  `FunctionClauseError` — error-type-only on the degenerate input). This is what the rule's own moduledoc
  recommended. Updated the fix tests' golden outputs.
- **`no_guard_equality_for_pattern_match` — was UNSAFE on number literals, now NARROWED to atom/string.**
  `def f(x) when x == 0` → head `f(0)` diverges on `0.0`: the guard's `==` matches `0.0`, the pattern head's
  `===` does not, so a float-equal value routes to a different clause. Atoms/strings have no cross-type
  value-equal partner, so `==` and pattern-match agree. Dropped integer (and float) from `fixable_literal`;
  converted the integer-based check/fix tests to atoms (and the integer-specific cases to negatives).
- **`no_map_get_sentinel` — DROPPED (behaviour-changing by design).** `Map.get(map, :key, -1); if val != -1`
  → the fix distinguishes a missing key from a present `-1`, so on `%{key: -1}` the original returns
  `:missing` but the fix returns `-1`. The rule's whole purpose is to *fix* the Python sentinel-collision
  idiom, so it cannot be behaviour-preserving — out of Credence's mandate. Deleted rule + tests.
- **`no_multiple_enum_at` — DROPPED (nil→crash on short lists).** Multiple `Enum.at(list, i)` → a destructure
  (`[a, b | _] = list`). `Enum.at` is nil-safe past the end, but the destructure raises `MatchError` on a
  list shorter than the indices (verified on `[1]`/`[]`). No length guarantee is available, so the fusion
  can't preserve behaviour. Deleted rule + tests.
- **`no_piped_regex_replace` — REPAIR rule (always-fails).** Re-investigated: the only firing shape,
  `value |> Regex.replace(~r/.../, repl)`, desugars to `Regex.replace(value, regex, repl)` — `value`
  lands in the regex slot, so it raises `FunctionClauseError` on **every** input (all strings, empty
  string, even a `%Regex{}` — no input yields a valid result). The fix `value |> String.replace(...)` is
  the correct call. Not behaviour-preserving (crash → work); marked `mark_equivalence_repair` (T3c).
  (Earlier "SAFE/T2" note was wrong — there is no valid before-behaviour.)

### T2 module-call (37) — compile before/after module, invoke fn over battery
Structural / cross-statement: no_case_on_param_dispatch, no_destructure_reconstruct,
no_double_filter, no_double_sort_same_list, no_enum_at_midpoint_access,
no_guard_equality_for_pattern_match, no_hd_tl_when_cons_bound, no_is_nil_guard,
no_is_prefix_for_non_guard, no_length_based_indexing, no_length_guard_to_pattern,
no_list_append_in_recursion, no_list_concat_with_recursive_result, no_list_to_tuple_for_access,
no_manual_count_with_predicate ⚑, no_manual_find ⚑, no_manual_list_last,
no_manual_list_reduce ⚑, no_map_get_sentinel, no_map_update_then_fetch,
no_multiple_enum_at, no_nested_enum_on_same_enumerable, no_redundant_comparison_guard,
no_redundant_negated_guard, no_repeated_div_rem, no_trivial_delegation,
no_underscore_function_name, no_unnecessary_catch_all_raise, prefer_guard_over_if.
Converted from opt-out (deep-dive): **inconsistent_param_names** (param rename across
clauses/body — miss/collision changes return), **non_grouped_clauses** (clause reorder with
NO overlap guard — can change pattern-match dispatch), **no_missing_require_logger** (before
crashes `UndefinedFunctionError`, after returns), **no_attr_before_defmodule** (doc attachment
via `Code.fetch_docs/1`), **no_piped_regex_replace** (safe), **redundant_list_guard** (unsafe — above).
Doc-observation sub-case (compile module, compare `Code.fetch_docs/1` instead of a return value):
**no_trailing_newline_in_doc**, **prefer_heredoc_for_multi_line_doc** (buggy strip/unescape
corrupts the stored docstring — low runtime risk but cheaply witnessable).

### T3a cosmetic (2) — `mark_equivalence_cosmetic` (proven inert)
no_doc_false_on_private (`@doc` on `defp` is compile-time-discarded — no emitted code changes),
no_literal_list_typespec (`@spec` is compile-only; the original doesn't even compile).

### T3b unconstructible (0)
None — deep-dive converted both former candidates to T2.

### PROBE ⚑ rules (26) — need `probe_effects: true` (eval-order/double-eval)
no_anon_fn_application_in_pipe, no_case_destructure_in_pipe, no_eager_with_index_in_reduce,
no_explicit_max_reduce, no_explicit_min_reduce, no_explicit_product_reduce,
no_explicit_sum_reduce, no_filter_then_count, no_filter_then_first,
no_find_value_default_case, no_group_by_for_frequencies, no_if_empty_for_enum_min_max,
no_list_append_in_reduce, no_manual_count_with_predicate, no_manual_find,
no_manual_list_reduce, no_map_keys_enum_lookup, no_map_keys_or_values_for_iteration,
no_map_then_aggregate, no_reduce_for_group_by, no_reduce_for_map_building,
no_string_concat_in_loop, no_take_while_length_check, no_zip_then_map,
prefer_map_put_new, use_map_join.

### T1 expression (86) — `fn <vars> -> expr end`
All remaining rules. High-risk first (taxonomy witnesses): no_enum_at_negative_index,
no_enum_drop_negative, no_enum_take_negative (bounds/negatives); no_codepoint_string_reverse,
no_manual_string_reverse, unnecessary_grapheme_chunking, no_grapheme_palindrome_check,
no_string_length_for_char_check, avoid_graphemes_* (Unicode); no_sort_then_at,
no_sort_then_reverse, no_sort_for_top_k, prefer_desc_sort_over_negative_take (sort stability);
no_redundant_case_nil_clause, no_map_keys_for_membership, no_keyword_get_integer_key,
no_list_delete_at_length, no_list_delete_at_with_length, no_list_pop_at_for_access
(nil/empty edges); no_identity_float_coercion, prefer_erlang_float (value-kind).
Remainder: avoid_graphemes_enum_count(_with_predicate), avoid_graphemes_length,
hallucinated_guard, no_capture_fn_apply, no_case_boolean_result, no_case_true_false,
no_case_tuple_guard_dispatch, no_chunk_by_identity_for_dedup, no_cond_two_clauses,
no_dead_map_update, no_empty_map_new, no_enum_count_for_length, no_enum_into_empty_mapset,
no_fetch_then_update, no_identity_function_in_enum, no_if_true_false, no_kernel_op_in_pipeline,
no_length_comparison_for_empty, no_list_duplicate_flatten, no_list_duplicate_join,
no_list_fold, no_manual_enum_uniq, no_manual_frequencies, no_manual_max, no_manual_min,
no_map_put_get_increment, no_param_rebinding, no_reduce_while_without_halt,
no_redundant_assignment, no_redundant_binary_syntax, no_redundant_dedup_before_mapset,
no_redundant_enum_join_separator, no_redundant_list_traversal, no_redundant_to_list,
no_tautological_if, no_uniq_then_count, no_unless_else, prefer_enum_reverse_two,
prefer_enum_slice, prefer_enum_split, prefer_regex_match, no_kernel_shadowing
(var shadows `Kernel.max/2`; wrap lambda), use_map_join handled under PROBE.
(`redundant_list_guard` moved to T2 — confirmed unsafe, see divergences above.)

(Full machine-readable tier+probe+freevars table emitted by the scaffold script;
above is the human worklist.)

## Phasing (gate flips hard only at the end)
1. **Support + battery + 6 proof tests — DONE (all modes proven, full suite green: 4488/0).**
   - `test/support/behaviour_equivalence.ex` — `assert_equivalent/2` (T1), `assert_equivalent_module/2`
     (T2, compiles before/after under unique names, arity-aware args), `assert_effect_trace_equivalent/2`
     (PROBE, process-dict trace), `eval_outcome/2` (exception parity), `mark_equivalence_cosmetic/1`,
     `mark_equivalence_unconstructible/1`. Anti-stub teeth (fires + rewrote + battery ≥ 3) verified
     by negative controls.
   - `test/support/equivalence_batteries.ex` — `term_lists`, `signed_integers`, `unicode_strings`,
     `single_codepoint_strings`, `multi_codepoint_strings`, `stability_lists`.
   - Proof tests: `no_enum_at_negative_index` (T1), `no_codepoint_string_reverse` (T1 — **dual
     exemplar**: passes on single-codepoint strings, and the suite *catches* the divergence on
     multi-codepoint graphemes, demonstrating why the rule carries `single_codepoint_graphemes`),
     `no_sort_then_reverse` (T1 stability), `no_trivial_delegation` (T2), `use_map_join` (PROBE),
     `redundant_list_guard` (T2 — divergence demo: pins the confirmed bug via `assert_raise` until narrowed).
   - Note: `apply_rule_fix/3` bypasses assumption gating, so the suite tests the fix unconditionally
     (correct — an assumption-gated rule must still be witnessed safe *within* its domain).
2. **Backfill — scaffold DONE; fill IN PROGRESS.** `maintainer_tools/gen_equivalence_skeletons.exs`
   generated all 119 missing `*_equivalence_test.exs` (6 exemplars preserved) → **125/125 files exist**.
   Each skeleton is stamped with its confirmed tier, seeded with firing snippets lifted from the
   `_check_test.exs`, tagged `@moduletag :equivalence_todo` (excluded via `test_helper.exs`, so the
   suite stays green: 4493 tests / 117 excluded). The 2 cosmetics are pre-filled and pass now.
   Remaining work = the fill pass: replace each TODO snippet/battery and drop the tag, highest-risk
   T1 first, then T2, then probe. Each divergence on a shipped rule → narrow/drop (decision 2).
   **Filled so far (16/125):** 6 exemplars + 10 backfill. Batch 1: `no_enum_take_negative`,
   `no_enum_drop_negative` (bounds, safe), `no_manual_string_reverse` (Unicode, safe),
   `no_redundant_case_nil_clause` (nil/term-ordering, safe), `no_sort_then_at` (empty → fixed).
   Batch 2: `no_grapheme_palindrome_check`, `no_string_length_for_char_check` (Unicode, safe),
   `unnecessary_grapheme_chunking` (len<n → fixed via `//1`), `no_sort_for_top_k` (narrowed to at(0)
   + empty_fallback), `prefer_desc_sort_over_negative_take` (added trailing reverse).
   Batch 3 (after the strict-`===` upgrade): `no_list_delete_at_length`, `no_map_keys_for_membership`
   (safe); `no_keyword_get_integer_key` dropped here (later REINSTATED as a T3c repair rule — see Batch 13);
   `no_identity_float_coercion` +
   `prefer_erlang_float` MERGED (wrap via `:erlang.float`, value-kind preserved, no assumption).
   2 cosmetics done. Suite green: 4418 tests / 102 excluded (**123 rules**).
   Batch 4 (value-kind + enumerable-type): `no_uniq_then_count`, `no_redundant_to_list`,
   `no_redundant_dedup_before_mapset` (safe — `Enum.uniq`/`MapSet` both strict `===`); `no_manual_max`
   + `no_manual_min` NARROWED to non-strict forms (strict `>`/`<` diverged on `max(1,1.0)`). Suite green:
   4422 tests / 97 excluded.
   Batch 5 (enumerable-type + eval-order): `no_list_fold` (safe — `foldr` fix reverses to keep order),
   `no_map_put_get_increment`, `no_reduce_while_without_halt`, `no_redundant_enum_join_separator` (safe);
   `no_enum_count_for_length` NARROWED to provably-list args (enumerable-type). Suite green: 4429 / 92 excluded.
   Batch 6 (10 rules): `no_empty_map_new`, `no_enum_into_empty_mapset`, `no_redundant_binary_syntax`,
   `no_identity_function_in_enum`, `no_cond_two_clauses`, `no_list_duplicate_join`,
   `no_chunk_by_identity_for_dedup`, `no_kernel_op_in_pipeline` (safe); `no_length_comparison_for_empty`
   (safe on `length`'s proper-list domain); `no_manual_enum_uniq` DROPPED (over-eager — unsafe in ~all
   shapes; only the full `reduce |> elem |> reverse` idiom was correct). Harness gained zero-var support
   (`to_args/2` for `vars: []`). Suite green: 4399 / 82 excluded.
   Batch 7 (10 rules): `no_if_true_false`, `no_unless_else`, `no_tautological_if` (already narrowed to
   pure-total conditions), `no_redundant_assignment`, `no_dead_map_update`, `no_case_true_false`,
   `no_capture_fn_apply`, `no_list_duplicate_flatten`, `prefer_enum_reverse_two` (safe);
   `prefer_enum_slice` NARROWED to non-negative literal amounts (negative/variable diverged from `slice/3`).
   Suite green: 4413 / 72 excluded.
   Batch 8 (10 rules): `no_explicit_sum_reduce`, `no_explicit_product_reduce` (safe — aggregate),
   `no_kernel_shadowing`, `no_param_rebinding` (safe alpha-renames), `no_list_delete_at_with_length`,
   `no_list_pop_at_for_access`, `prefer_regex_match`, `no_fetch_then_update` (safe);
   `no_explicit_max_reduce` + `no_explicit_min_reduce` DROPPED (init contamination + value-kind ties,
   no identity literal). Suite green: 4390 / 62 excluded.
   Batch 9 (10 rules): `avoid_graphemes_enum_count`, `avoid_graphemes_length`,
   `avoid_graphemes_enum_count_with_predicate`, `no_manual_frequencies`, `no_filter_then_count`,
   `no_string_concat_in_loop`, `no_zip_then_map`, `no_take_while_length_check` (safe — probe rules whose
   pred/mapper order is preserved by construction); `hallucinated_guard` UNCONSTRUCTIBLE;
   `no_map_then_aggregate` NARROWED to `:sum` (max/min selection had an unmapped reduce/2 seed).
   Suite green: 4400 / 52 excluded.
   Batch 10 (10 PROBE rules): `no_filter_then_first`, `no_find_value_default_case`,
   `no_if_empty_for_enum_min_max`, `no_list_append_in_reduce`, `no_reduce_for_map_building`,
   `prefer_map_put_new` (safe — doesn't fire on side-effecting value), `no_map_keys_enum_lookup`
   (safe — order-independent `all?`), `no_reduce_for_group_by` (safe — full reduce|>Map.new(reverse) = group_by);
   `no_map_keys_or_values_for_iteration` NARROWED to order-independent ops (>32-key map order divergence);
   `no_anon_fn_application_in_pipe` was a malformed-output BUG, FIXED (patch range extended to include the
   parenthesized fn's `(`). Suite green: 4410 / 42 excluded.
   Batch 11 (10 T2 module-call rules): `no_manual_count_with_predicate`, `no_manual_find`,
   `no_manual_list_reduce`, `no_case_on_param_dispatch`, `prefer_enum_split`, `no_redundant_negated_guard`,
   `no_redundant_comparison_guard`, `no_is_nil_guard`, `no_double_filter` (all safe — verified by compiling
   before/after modules and invoking the entry fn over adversarial batteries);
   `no_manual_list_last` autofix diverged on `[]` (`List.last` → `nil` vs manual raise), FIXED to
   `hd(Enum.reverse/1)`. Suite green: 4420 / 32 excluded.
   Batch 12 (10 T2 rules): `no_case_boolean_result`, `no_hd_tl_when_cons_bound`, `no_length_guard_to_pattern`,
   `no_repeated_div_rem`, `no_nested_enum_on_same_enumerable`, `prefer_guard_over_if` (narrowed to
   non-raising guard-legal conditions — verified it won't fire on `if hd(x) > 0`), `no_double_sort_same_list`
   (`sort(:desc)` ≡ `reverse(sort)` even on value-kind ties) (all safe);
   `no_guard_equality_for_pattern_match` NARROWED to atom/string (number literal → `0.0` value-kind);
   `no_map_get_sentinel` DROPPED (sentinel-collision behaviour-change), `no_multiple_enum_at` DROPPED
   (`Enum.at` nil-safe → destructure crashes on short lists). Suite green: 4340 / 22 excluded.
   **Bugs found: 17 fixed/narrowed in-session, 5 dropped, 1 merged, 1 reinstated-as-repair** (the `===`
   upgrade keeps exposing value-kind/enumerable-type/bounds/order bugs; plus a malformed-output fix-renderer
   bug and empty/short-list autofix divergences). Rule count 125→119.
   (Dropped: `no_manual_enum_uniq`, `no_explicit_max_reduce`, `no_explicit_min_reduce`, `no_map_get_sentinel`,
   `no_multiple_enum_at`. `no_keyword_get_integer_key` was dropped then reinstated as a T3c repair rule.)
   (Every PROBE rule so far preserves eval order — none needed the effect-trace mode; `prefer_map_put_new`
   and `prefer_guard_over_if` self-narrow away from side-effecting/raising inputs. T2 guard/clause rewrites
   verified safe via module-invoke.)
   Batch 13 (10 rules): cosmetic (T3a) — `no_trailing_newline_in_doc`, `prefer_heredoc_for_multi_line_doc`,
   `no_attr_before_defmodule`, `inconsistent_param_names`, `no_underscore_function_name`,
   `no_is_prefix_for_non_guard`; unconstructible (T3b) — `no_missing_require_logger`; safe T2 —
   `no_map_update_then_fetch`, `no_destructure_reconstruct`; **introduced the T3c REPAIR category** and
   marked `no_piped_regex_replace` (always-fails). Then **REINSTATED `no_keyword_get_integer_key`** (recovered
   from `103db1b^`) as a repair rule after re-probing it crashes on 24/24 inputs. Suite green: 4383 / 12 excluded.
   Rule count 118→119.
   **Policy:** "fix broken → working" rules are a recognised, behaviour-CHANGING family — documented via
   `mark_equivalence_repair` (or `unconstructible` for the compile-broken flavour), never silently dropped.
   The repair test must prove the broken precondition (here: no input avoids the crash); a "before" that
   returns a valid value on *any* input is a behaviour change, not a repair.
   Batch 14 (final 12 rules — clears the skeleton backlog): safe T2 — `no_case_tuple_guard_dispatch`,
   `no_group_by_for_frequencies`, `no_list_append_in_recursion`, `no_list_concat_with_recursive_result`,
   `non_grouped_clauses` (relative clause order preserved), `no_case_destructure_in_pipe`,
   `no_eager_with_index_in_reduce`, `no_redundant_list_traversal` (min+max → `Enum.min_max`),
   `no_length_based_indexing` (→ `List.last`), `no_unnecessary_catch_all_raise` (list domain; error-type-only
   on non-lists); DROPPED `no_enum_at_midpoint_access` and `no_list_to_tuple_for_access` (both the
   `elem`-vs-`Enum.at` nil/crash mismatch — same hazard as `no_multiple_enum_at`).

   **★ BACKFILL COMPLETE — 0 skeletons, 0 excluded. Every rule has a real equivalence test.**
   Final: **17 fixed/narrowed in-session, 7 dropped, 1 merged, 1 reinstated-as-repair.** Rule count 125→117.
   Suite: **4344 tests, 0 failures, 0 warnings, 0 excluded.**
   Dropped: `no_manual_enum_uniq`, `no_explicit_max_reduce`, `no_explicit_min_reduce`, `no_map_get_sentinel`,
   `no_multiple_enum_at`, `no_enum_at_midpoint_access`, `no_list_to_tuple_for_access`. Merged:
   `no_identity_float_coercion`→`prefer_erlang_float`. Reinstated as repair: `no_keyword_get_integer_key`.
3. ~~Backfill T2 / PROBE~~ — **done** (all tiers filled; PROBE rules verified to preserve eval order via
   value tests, effect-trace mode unused).
4. ~~Stamp T3a/T3b~~ — **done**, plus the new **T3c repair** tier; all flagged divergences resolved
   (fixed / narrowed / dropped / reinstated), none pinned.
5. **Flip gate hard — ★ DONE.** `test/equivalence_meta_test.exs` is live: it discovers every
   `Credence.Pattern.Rule` and asserts each has a test module `Credence.Pattern.<Name>EquivalenceTest`
   (coverage checked by module name — no filename guessing), plus that no equivalence test is still tagged
   `:equivalence_todo`. The `:equivalence_todo` exclude was dropped from `test_helper.exs` (`ExUnit.start()`
   with no excludes), so a newly-added rule shipped without a real equivalence test now **fails the suite**.
   Teeth verified: hiding one rule's test makes the gate fail naming that rule; restoring greens it.
   Suite green with no excludes: **4347 tests, 0 failures**.
- StreamData layer (additive, fixed-seed, non-gating) — optional, future enhancement now that the gate holds.

## Verification
- **Catches divergence (real example, resolved):** `redundant_list_guard` over the improper-list
  witness `[1 | 2]` (`:fallthrough` vs `{:matched,1,2}`) failed equivalence; after narrowing behind
  the `proper_lists` assumption it passes in-domain (proper lists) and the out-of-domain `assert_raise`
  demo pins the divergence. Also craft `no_enum_take_negative` with a count that swaps halves / a
  sort rule on equal-key tuples → must fail with witness.
- **Exception parity:** snippet where original raises `ArithmeticError` and fixed `ArgumentError`
  must fail — proves `eval_outcome` compares raises module-only.
- **Effect probe:** a reorder/double-eval snippet must fail on trace mismatch.
- **Anti-stub:** an empty `<base>_equivalence_test.exs` or `[]`/`<3` battery must fail
  (helper assertion + meta-gate file/reference check).
- **Historical regression check:** for ≥5 rules in `unfixable_confirmed.md`/`followup.md`,
  write the equivalence test against their *original (rejected)* fix and confirm the battery
  reproduces the documented divergence — i.e. the suite would have caught each.
- `mix test` green after each phase; hard-flip green only at 100% backfill + empty divergence list.

## Unresolved questions
1. **T2 callable synthesis:** for def/module rules whose `_check` snippet is a fragment (not a
   full module), do we (a) hand-wrap each into a minimal callable `defmodule`, or (b) have the
   scaffold script synthesize a wrapper from the rule's expected shape? (a) is safer, (b) scales.
2. **Battery↔tier defaults:** should the scaffold auto-attach default battery dimensions per
   rule from its `assumptions/0` (so fill = confirm), or leave batteries blank (so fill = author)?
3. ~~`redundant_list_guard` fix~~ — RESOLVED: narrowed behind the new `proper_lists` assumption
   (default on, off under `:strict`); tests green. Loop firing confirmed: the rule-creation/review
   flow runs `:default`, where `proper_lists` is on, so the rule fires unchanged.
4. **Divergence worklist home:** track shipped-rule divergences found during backfill in
   `maintainer_tools/` (alongside unfixable/followup), or in this repo's docs?
5. **Doc-observation rules worth it?** `no_trailing_newline_in_doc` / `prefer_heredoc_for_multi_line_doc`
   are testable via `Code.fetch_docs/1` but carry near-zero runtime risk — keep as T2-doc tests, or
   accept as cosmetic to save effort?
