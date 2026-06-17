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

## prefer_integer_digits_for_first_digit — dropped 2026-06-17
- Files (sister `evolution`): `lib/pattern/prefer_integer_digits_for_first_digit.ex` (+ check/fix/equivalence tests)
- Reason: float input diverges — string path (`n |> abs |> to_string |> String.first |> String.to_integer`) returns a digit (`3.14`→`3`) where `Integer.digits/1` raises FunctionClauseError (value-vs-crash). The base is always a runtime variable, never a provable integer at the AST; the fix also drops intermediate pipe ops (`div(3)`) by rebuilding from the leftmost base. Only safe gate (integer literal) is degenerate. Dropped.

## prefer_integer_to_binary_for_bit_length — dropped 2026-06-17
- Files (sister `evolution`): `lib/pattern/prefer_integer_to_binary_for_bit_length.ex` (+ check/fix/equivalence tests)
- Reason: `floor(:math.log(n)/:math.log(2)) + 1` ≠ `integer_to_binary(n,2) |> String.length` — smallest divergence at n=2^48−1 (log→49, true→48), recurring at every 2^k−1 for k≥48 (ordinary 48-bit ints, the exact regime bit-length is used). Added `when n<0` clause turns a crash into a value (domain change). Operand is a runtime var, unbounded below 2^48; literal-only gate is degenerate. Dropped.

## prefer_integer_undigits — dropped 2026-06-17
- Files (sister `evolution`): `lib/pattern/prefer_integer_undigits.ex` (+ check/fix/equivalence tests)
- Reason: `Enum.reduce(ds,0,fn d,acc->acc*10+d end)` vs `Integer.undigits(ds)` diverges — digit≥base `[12,3]`→123 vs ArgumentError; float elems→value vs FunctionClauseError; non-list enumerable (`1..3`)→value vs raise; map→ArithmeticError vs FunctionClauseError. Check fires on the reduce shape over a variable, never a provable in-range integer list; literal-list-only gate is degenerate. Dropped.

## prefer_pattern_matching_for_empty_string — dropped 2026-06-17
- Files (sister `evolution`): `lib/pattern/prefer_pattern_matching_for_empty_string.ex` (+ check/fix/equivalence/property tests)
- Reason: `String.trim(var) == ""` rewritten to a `""` pattern match diverges on whitespace — `String.trim(" ")==""` is true but `match?("", " ")` is false (orig returns `[]`, fix raises on the else path). The rule structurally requires `String.trim`, whose whitespace-collapsing semantics cannot be expressed as a `""` literal; no bare-`==""` core to retreat to. Dropped.

## prefer_prepend_in_accumulator — dropped 2026-06-17
- Files (sister `evolution`): `lib/pattern/prefer_prepend_in_accumulator.ex` (+ check/fix/equivalence tests)
- Reason: `List.last(acc)` reads the TAIL; the fix substitutes `head` (front) + flips `acc++[x]`→`[x|acc]` + drops `Enum.reverse`. `build_groups([1,2],[3])`: orig reads last=2, `3==2+1` true→`[[3,2,1]]`; fix reads head=1, `3==1+1` false→`[[1,2],[3]]`. Equivalent only for single-element seed accumulators, which is unprovable from the function body (callers out of scope). Dropped.

## prefer_remove_unused_private_fn_param — dropped 2026-06-17
- Files (sister `evolution`): `lib/pattern/prefer_remove_unused_private_fn_param.ex` (+ check/fix/equivalence tests)
- Reason: removing a defp param deletes the call-site arg expr (drops side effects — `compute(x, IO.puts("hi"))`→`compute(x)`); the call rewriter is arity-blind (foo/2+foo/3 → wrong-arity calls that don't compile), strands `&name/n` captures, and groups defp globally across modules. Value-safety needs all call sites statically visible (defeated by captures/`apply`/sibling arities). Same family as `remove-unused-private-fn-param-unsafe`. Dropped.

## prefer_reverse_for_palindrome_check — dropped 2026-06-17
- Files (sister `evolution`): `lib/pattern/prefer_reverse_for_palindrome_check.ex` (+ check/fix/equivalence tests)
- Reason: `recursive_case_body?` discards the comparison operator, so a `!=`/false-base lookalike is force-rewritten to `list == Enum.reverse(list)` — returns true on `[1,2,3,4]` vs fix's false. Even a locked core diverges on non-list input (`length(map)` raises vs fix returns false). Argument type unprovable; overfit to hardcoded names palindrome_check/palindrome_helper?. Dropped.

## prefer_string_at_for_char_access — dropped 2026-06-17
- Files (sister `evolution`): `lib/pattern/prefer_string_at_for_char_access.ex` (+ check/fix/equivalence tests)
- Reason: `x = List.to_string([y])` → `<<y::utf8>>` diverges whenever y is not an integer codepoint — `y="ab"`: `List.to_string(["ab"])=="ab"` (valid) vs `<<"ab"::utf8>>` raises ArgumentError. `code_var` is always a bound variable, never a provable 0..0x10FFFF integer; literal-only gate matches nothing. Also rebinds body_var globally ignoring shadowing. Dropped.

## prefer_string_capitalize — dropped 2026-06-17
- Files (sister `evolution`): `lib/pattern/prefer_string_capitalize.ex` (+ check/fix/equivalence tests)
- Reason: manual `String.upcase(String.first(s)) <> String.downcase(String.slice(s,1..))` ≠ `String.capitalize/1` under Unicode special-casing — ß→"SS" vs "Ss", ligature ﬁ→"FI" vs "Fi", digraph ǆ→"Ǆ" vs "ǅ". Divergence is driven by runtime string content, unprovable from the AST. Fix also hardcodes `capitalize_string` while firing on any function name, renaming other defps. Dropped.

## prefer_string_first_last — dropped 2026-06-17
- Files (sister `evolution`): `lib/pattern/prefer_string_first_last.ex` (+ check/fix/equivalence/property tests)
- Reason: empty-string divergence — `String.split_at("",1)→{"",""}` so orig `"" == String.last("")` = `""==nil` → false vs fix `String.first("")==String.last("")` = `nil==nil` → true. Emptiness unprovable from AST (subject is a runtime var); the case subject is unchecked so it fires on lookalikes. Dropped.

## prefer_tuple_for_random_access — dropped 2026-06-17
- Files (sister `evolution`): `lib/pattern/prefer_tuple_for_random_access.ex` (+ check/fix/equivalence tests)
- Reason: `Enum.fetch!(coll,i)` → `elem(List.to_tuple(coll),i)` diverges on negative index (`i=-1` returns vs raises), out-of-bounds (Enum.OutOfBoundsError vs ArgumentError), and non-list enumerables (range/map raise on List.to_tuple). The rule fires only when coll is a variable and i a loop variable from a range, so both type and sign are unprovable; list+literal-index gate matches nothing. (Memory: [[enum-fetch-to-elem-tuple-unsafe]].) Dropped.

## avoid_binary_mid_pattern — dropped 2026-06-17
- Files (sister `evolution`): `lib/semantic/avoid_binary_mid_pattern.ex` (+ check/fix tests)
- Reason: in `<<first, mid::binary, last>>`, `last` is an integer byte; the fix sets it to a 1-byte BINARY via `binary_part/3`, so `first == last` becomes int-vs-binary — `"aa"`: intended `97==97` true → fix `97 == "a"` false (true→false inversion). Type change inherent to binary_part; no value of str makes a binary equal an integer. Also leaves `mid` unbound and relaxes the ≥2-byte match. Dropped.

## avoid_remote_function_in_guard — dropped 2026-06-17
- Files (sister `evolution`): `lib/semantic/avoid_remote_function_in_guard.ex` (+ check/fix tests)
- Reason: two divergences. (A) head mismatch — `same_function?` checks name+arity only, merging clauses with different head patterns (f([h|_t],…)+f([],…) → FunctionClauseError on f([],0)). (B) guard error-swallowing — a guard that raises (x/0, `MapSet.size(:bad)`, even `Bitwise.band(:a,1)`) silently fails the guard → fallback, but lifted into `if` it propagates. Remote calls in guards are exactly the ops whose runtime errors guards swallow; lifting any into `if` diverges. No AST-provable non-raising subset. Dropped.

## RECOVERED 2026-06-17 (narrowed or folded — NOT dropped; do not re-propose as standalone)
These 7 candidates were salvaged this session and are now live on `evolution_accepted`:
- **prefer_enum_join** → folded into `UndefinedFunction` `@qualified_replacements`: `{"String","join",2} => {:rename,"Enum","join"}`. Standalone module redundant.
- **prefer_enum_slice_over_list_slice** → folded: `{"List","slice",3} => {:rename,"Enum","slice"}`.
- **prefer_map_size_kernel** → folded: `{"Map","size",1} => {:drop_module,"map_size"}` (existing bare-Kernel variant; "Map.size/1 is deprecated").
- **prefer_tl_over_enum_tail** → folded: `{"Enum","tail",1} => {:drop_module,"tl"}`.
- **prefer_map_size** → folded into `no_enum_count_for_length`: when the counted arg is `Map.keys(m)`, emit `map_size(m)` (=== for all inputs incl. BadMapError on non-maps).
- **prefer_negate_if_true_false** → kept as its own rule, narrowed to its UNIQUE territory (non-boolean else body OR non-provably-boolean condition) so it no longer double-fires with `no_if_true_false`. The negate-and-swap rewrite was already safe.
- **prefer_map_intersect_over_mapset_intersection** → kept, narrowed: full two-statement block shape (check==fix), single-use intersection var, bare-var maps, and a PURE merge over count1/count2+literals (excludes element refs and makes the MapSet-vs-Map.intersect key-order difference unobservable). Large-map (>32 key) equivalence verified.
