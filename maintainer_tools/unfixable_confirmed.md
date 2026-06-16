# Confirmed unfixable / dropped — human-decided

Rules a human reviewed and decided to drop for good (no safe fix even on a narrow
core). Distil each reason into `CONTEXT.md` / the sister `prompt.md` so it is not
re-proposed.

## avoid_duplicate_enum_at — dropped 2026-06-16
- Files (sister `evolution`): `lib/pattern/avoid_duplicate_enum_at.ex` (+ check/fix/equivalence tests)
- Reason: re-attempt of the already-dropped `no_multiple_enum_at` family — it
  rewrites repeated `Enum.at(list, i)` into bindings/destructure, but `Enum.at`
  is **nil-safe past the end** while a destructure/index **crashes** on a short
  list (value→crash divergence). On top of that the synthetic `<i>_elem`
  bindings can **clobber existing in-scope variables**, and it emits
  **non-compiling code for inline `if`**. A safe version needs whole-scope
  variable analysis (a shared-helper concern), so there is no safe narrow core
  for a pattern rule. NO safe fix → dropped.

## no_if_boolean_result — dropped 2026-06-16
- Files (sister `evolution`): `lib/pattern/no_if_boolean_result.ex` (+ check/fix/equivalence tests)
- Reason: redundant, less-sound `no_if_true_false`. Its `cond or expr` / `cond and expr`
  rewrites are already handled by the live `no_if_true_false` (which gates the condition
  soundly via `condition_bool?`). The only cases this rule fires that `no_if_true_false`
  won't are its UNSOUND ones — `provably_boolean?` trusts bare `and`/`or` (but `true and 5
  == 5`, non-boolean → rewrite raises BadBooleanError where the `if` returns a value) and
  `?`-predicate calls (convention-trust → same BadBooleanError divergence on a non-boolean
  return). The lone sound-and-unique sliver (sound condition + non-boolean else branch) is
  a marginal `||`-style idiom, not the rule's intent. Safe core ⊆ no_if_true_false; any
  real gain is a shared-file fold. Dropped.

## no_if_empty_for_enum_min_max — DELTA REJECTED 2026-06-16 (rule stays live)
- The accepted rule matches only a BARE VARIABLE in `if Enum.empty?(v), do: d, else: Enum.min/max(v)`.
- Evolution's delta extended the match to `Enum.filter/2`/`Enum.reject/2` CALLS (same expr in
  guard + branch). UNSAFE: the original evaluates the call TWICE (empty? guard, then min/max
  branch); the rewrite evaluates it ONCE. With an impure/non-deterministic predicate the two
  filter results differ — proven: original raises `Enum.EmptyError`, rewrite returns a value.
  Purity isn't statically decidable, so there's no safe core beyond the bare-var version.
  Matches the `no_double_filter` convention: never a call, rule out side-effecting double eval.
  → Delta rejected; keep the accepted bare-var version.

## prefer_bitshift_over_math_pow_for_power_of2 — dropped 2026-06-16
- Files (sister `evolution`): `lib/pattern/prefer_bitshift_over_math_pow_for_power_of2.ex` (+ tests)
- Reason: `trunc(:math.pow(2, x))` → `1 <<< trunc(x)` is not behaviour-preserving.
  (1) `trunc` and `pow` don't commute on non-integer x: `trunc(2^2.5) = 5` vs
  `1 <<< trunc(2.5) = 4`. (2) Overflow: `trunc(:math.pow(2, 1024))` raises
  ArithmeticError while `1 <<< 1024` returns a bignum. Safe only for a
  non-negative integer x < 1024. The `< 1024` bound is unprovable for any
  variable (even with integer-type inference — `length(list)`/`rem`/a param can
  exceed it), so the only safe core is integer literals in [0,1023]
  (`trunc(:math.pow(2, 10))`), which nobody writes → degenerate. No
  non-degenerate safe core; dropped.

## prefer_chunk_over_indexed_reduce — dropped 2026-06-16
- Files (sister `evolution`): `lib/pattern/prefer_chunk_over_indexed_reduce.ex` (+ tests)
- Reason: overfit TEMPLATE substitution, not a transformation. It matches a "count
  local peaks" shape and swaps in a fixed `Enum.chunk_every(3,1,:discard) |> count`
  + boundary template, without verifying the code's actual init accumulator
  (assumes 0), branch return values (assumes acc+1/acc), or comparison (assumes
  value > neighbour) — so same-shaped code with a different init/return/operator is
  silently mis-rewritten. And even the EXACT canonical snippet diverges on a
  single-element list (`[{}]`/`[%{}]`/`[[]]` → orig 1, rewrite 0): the original's
  `value > Enum.at(list, 1)` is `{} > nil` which is true in term ordering (nil <
  tuple/map/list), so it counts the lone element; the rewrite doesn't. No
  narrowable core (a template swap can't be made behaviour-preserving without
  re-deriving the semantics it skips). Dropped — overfit snippet-match rules don't
  belong here.

## prefer_direct_list_return_in_accumulator — dropped 2026-06-16
- Files (sister `evolution`): `lib/pattern/prefer_direct_list_return_in_accumulator.ex` (+ tests)
- Reason: changes a function's RETURN SHAPE (`{acc, []}` → bare `acc`) plus its
  caller's `{v, _} = f(...)` → `v = f(...)`, but keys on one clause / one caller
  with no whole-module reconciliation. Breaks when other clauses/recursion do
  `{res, errs} = f(...)` (MatchError; BEFORE run(2)->[1,2], AFTER raises), other
  callers `{a,b} = f(...)` use the second element, or f is captured `&f/2`; arity
  untracked. A reliable narrow is only possible for `defp` (all callers visible)
  AND non-recursive (all clauses return literal `{_, []}`) AND every call site
  `{_,_} = f(...)` — which EXCLUDES the canonical recursive-accumulator case (its
  recursive clause needs internal-destructure body surgery, beyond a narrow) and
  fires on a niche non-recursive shape. High-effort, error-prone whole-module
  call-graph analysis for near-zero realistic firing → dropped.

## prefer_direct_string_check_over_complex_enum — dropped 2026-06-16
- Files (sister `evolution`): `lib/pattern/prefer_direct_string_check_over_complex_enum.ex` (+ tests)
- Reason: three independent problems, no safe core. (1) Overfit TEMPLATE — matches
  one specific `validate_pattern(string, count, divisor)` snippet, hardcoded down
  to var names `pattern`/`full_pattern`; not a transformation. (2) Deletes an
  arbitrary `Enum.all?(...)` as "dead" (value discarded), but the predicate can
  raise / have side effects → BEFORE raises, AFTER returns the comparison
  (totality trap on an unprovable arbitrary predicate). (3) `Integer.mod(a,b) →
  rem(a,b)` is NOT behaviour-preserving — floored vs truncated modulo differ on
  any negative operand (`Integer.mod(-7,3)=2` vs `rem(-7,3)=-1`). Each component is
  independently unsafe; even extracting just the modulo swap ships a bug. Dropped.

## prefer_enum_frequencies — dropped 2026-06-16
- Files (sister `evolution`): `lib/pattern/prefer_enum_frequencies.ex` (+ tests)
- Reason: not behaviour-preserving. `group_by(id,id) |> map(count)` and
  `Enum.frequencies` produce the same {key,count} pairs but ENUMERATE IN DIFFERENT
  ORDER for >32 distinct keys (proven with 40 string keys). The rule only fires
  when a downstream step erases the list-vs-map type difference — but those steps
  observe the order: `Enum.sort` is stable, so a tie-producing comparator (the
  canonical sort-by-frequency for top-k) breaks ties by input order, leaking the
  two enumeration orders into the result. Safe cores: order-independent downstream
  (Map.new/into %{}) DUPLICATES live `no_group_by_for_frequencies`; total-order
  downstream sort is undecidable/fragile to verify; ≤32 keys unprovable. No
  tractable non-duplicate safe core. Dropped.

## prefer_enum_frequencies_over_group_by — FOLDED into no_group_by_for_frequencies 2026-06-16
- Value-safe (map `==` is order-independent, unlike prefer_enum_frequencies #12),
  but it overlapped the live `no_group_by_for_frequencies`. Investigation found the
  live rule had a BUG: it only fired on the nested `Map.new(group_by(...), ...)` and
  the 3-step `enum |> group_by(kf) |> Map.new` forms — NOT the 2-step
  `Enum.group_by(enum, kf) |> Map.new(...)` form (its own moduledoc example didn't
  fire), and it always emitted `frequencies_by` even for an identity key_fn.
  FOLDED #13's coverage into the live rule instead of shipping a duplicate:
  added the 2-step piped form, `Enum.into(%{}, cb)` as a Map.new equivalent
  (count_collector), and identity key_fn → `Enum.frequencies/1` (frequencies_call).
  Live rule + its check/fix tests updated; full suite green. Standalone #13 dropped.

## prefer_float_round — dropped 2026-06-16
- Files (sister `evolution`): `lib/pattern/prefer_float_round.ex` (+ tests)
- Reason: `:erlang.round(x*100)/100` → `Float.round(x, 2)` is NOT behaviour-preserving.
  The two are different functions: the manual trick rounds `x*100` (FP pre-multiplication
  error) round-half-away-from-zero; `Float.round/2` rounds `x` round-half-to-even. They
  diverge on a DENSE float set wherever the 3rd decimal is ~5: 2.675→2.68 vs 2.67;
  2.005→2.01 vs 2.0; 0.045→0.05 vs 0.04; -2.675→-2.68 vs -2.67. Plus integer x: the trick
  returns a float, Float.round raises FunctionClauseError (value-vs-crash). No safe core —
  narrowing to provably-float x only removes the integer issue; the dense rounding
  divergence is the core behaviour and there's no statically-identifiable agreeing subset.
  (The rule's equivalence test cherry-picked 11 non-half inputs to hide it.) Dropped.
