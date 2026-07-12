> **Provenance & verification status (added 2026-07-11 by the coordinating
> session before hand-off).** This report was produced by an autonomous
> research agent (Claude Opus) auditing the rule set read-only. It is preserved
> verbatim below; read it with these corrections from the empirical scrutiny in
> `docs/14-proposal-scrutiny.md`:
>
> - **§5.1 (`no_sort_then_reverse`) and §5.3 (`no_double_sort_same_list`) are
>   REFUTED.** On Elixir 1.20.2, `Enum.sort(l) |> Enum.reverse()` is
>   `===`-identical to `Enum.sort(l, :desc)` across 625 brute-forced tie-heavy
>   int/float lists — `:desc` reverses tie groups exactly as
>   reverse-of-ascending does. The agent reasoned from an assumed-stable
>   `:desc`; execution disproved it. Both rules are safe today (a stdlib
>   sentinel test is recommended — docs/12 C1).
> - **§5.2 (`no_sort_then_at`) is CONFIRMED** (`sort |> at(-1)` → `Enum.max`
>   diverges on `[1, 1.0]`: `1.0` vs `1`), and the same bug was later found in
>   **`NoSortForTopK`** (not covered by this audit) via the battery probe
>   (docs/14 E1). Exact repair: strict sorter `Enum.max(c, &>/2, fn -> nil
>   end)` — verified 0 divergences over the complete int/float divergence
>   class.
> - §3's "blind spot" diagnosis (stability_lists vs term_lists) is correct but
>   incomplete: `no_sort_then_at`'s test *does* use `term_lists()` — the hole
>   is that `term_lists()`' only mixed-kind entry ties at the *minimum*
>   (docs/14 E1 has the full account).
> - Inventory counts (146 rules, priorities, assumptions) were consistent with
>   the pipeline agent's report up to definitional differences (e.g. "4 rules
>   declare non-empty assumptions" here vs "6 declare the callback" there —
>   two declare `[]` explicitly).
> - Everything else (provenance archaeology, overlap clusters, followup-commit
>   catalogue, over-fit findings) was spot-checked but not exhaustively
>   re-verified; treat file:line cites as accurate as of 2026-07-11.

---

# Credence Rule Quality Audit

Read-only audit of the lint/fix rule set. Scope: `lib/pattern/` (146 rules + `rule.ex`),
`lib/syntax/` (19 rules + `rule.ex`), `lib/semantic/` (16 rules + `rule.ex`).
Goal: characterize the quality distribution of auto-generated rules and find concrete
defect patterns. No files were modified; no `mix test` was run.

Headline findings:
- The pipeline runs 139/146 pattern rules at the **default priority 500**, so their
  relative order is decided by **alphabetical module name** (`Enum.sort_by(&{&1.priority(), &1})`),
  not by design. Ordering-dependent clusters rely on this accident.
- **Three of the oldest hand-written sort rules share one undeclared semantic defect**:
  they treat `Enum.sort |> Enum.reverse` as equal to `Enum.sort(:desc)` (and vice-versa),
  which diverges on lists mixing value-equal ints and floats (`[1, 1.0]`). The
  behaviour-equivalence harness that should catch it uses an input generator
  (`stability_lists`) that omits the exact `[1, 1.0]` trap the sibling generator
  (`term_lists`) was built to carry.
- The dominant defect signature in **auto-generated** rules is **over-fitting**: several
  June-burst rules match one exact multi-clause snippet (a specific LeetCode-style
  problem) and will essentially never fire on real code.
- Test infrastructure is unusually strong (mandatory check/fix/equivalence triplet per
  rule, byte-exact fix compare, adversarial equivalence eval with `===`), which is why
  most shipped rules are correct; the escaped defects cluster where that harness has a
  blind spot.

---

## 1. Inventory & distributions

Per-rule metadata was extracted by grep/awk over `lib/pattern/*.ex`. Full table omitted
for length; the distributions:

### Priority histogram (146 rules)

| priority | count | rules |
| -------- | ----- | ----- |
| 500 (default) | 139 | the bulk |
| 501 | 3 | `no_explicit_product_reduce`, `no_explicit_sum_reduce`, `prefer_heredoc_for_multi_line_doc` |
| 499 | 1 | `no_identity_function_in_enum` |
| 510 | 1 | `no_chunk_by_identity_for_dedup` |
| 520 | 1 | `no_identity_enum_map` |
| 50 | 1 | `no_piped_regex_replace` |

**Tiebreak.** `Credence.RuleHelpers.discover_rules/1` sorts by `&{&1.priority(), &1}`
(`lib/rule_helpers.ex:23`). The second tuple element is the module atom, so equal
priorities fall back to **alphabetical module name**. With 139 rules tied at 500, almost
all inter-rule ordering is alphabetical, i.e. incidental. The handful of non-default
priorities are deliberate nudges (e.g. `no_identity_function_in_enum` at 499 runs before
the 500 block; the identity/dedup family is spread 499/510/520). `no_piped_regex_replace`
at 50 runs very early. Only 7 rules opt out of the default — everything else that
*needs* to run in a specific order relative to a 500-peer is relying on the alphabet.

### Fix style
All 146 pattern rules implement `fix_patches/2` (byte-range patches). **Zero** implement a
whole-text `fix/2` — the `Credence.Pattern.Rule` behaviour (`lib/pattern/rule.ex:58`) only
declares `fix_patches/2`; whole-text `fix/2` exists only in the Syntax phase.

### Moduledoc
**146/146** pattern rules have a real `@moduledoc` (none `@moduledoc false`, none missing).
Doc quality is generally high — most include `## Bad` / `## Good` and an explicit
"why the rewrite is safe / not flagged" section. This is a strong point of the set.

### Assumptions (safety switches)
Only two switches exist (`lib/assumptions.ex`): `single_codepoint_graphemes` (default on),
`proper_lists` (default on). Only **4** rules declare a non-empty `assumptions/0`:
- `:single_codepoint_graphemes` → `avoid_graphemes_enum_count_with_predicate`,
  `no_codepoint_string_reverse`, `prefer_graphemes_for_character_uniqueness`
- `:proper_lists` → `redundant_list_guard`

Two rules redundantly declare `assumptions, do: []` (already the default) —
`no_piped_regex_replace` and one other — a trivial style inconsistency.

### unsafe_in_dsl (Ash/Ecto/Nx guard)
14 rules declare a non-default `unsafe_in_dsl/0`; the other 132 default to `[]`:
- `:all` (5): `no_if_true_false`, `no_kernel_op_in_pipeline`, `no_manual_max`,
  `no_manual_min`, `prefer_reduce_while_with_halt_value`
- `:nx_defn` (3): `no_tautological_if`, `prefer_function_capture`, `prefer_multi_clause_reduce_fn`
- `:ash_expr` (2): `no_cond_two_clauses`, `no_string_length_for_char_check`
- `[:ash_expr, :ecto_query]` (1): `prefer_erlang_float`
- `[:ash_expr, :nx_defn]` (1): `prefer_negate_if_true_false`

### LOC
Range 64 (`prefer_enum_reverse_two`) to **631** (`no_manual_count_with_predicate`). Other
outliers: `prefer_guard_over_if` (553), `no_redundant_list_traversal` (523),
`no_map_keys_or_values_for_iteration` (516), `prefer_function_clauses_for_list_patterns`
(495), `no_manual_find` (477), `no_manual_list_reduce` (445). The largest files are
overwhelmingly from the June auto-generation bursts and correlate with the most complex
(and historically buggiest — §4) rules.

---

## 2. Overlap / interaction clusters

The pipeline reduces rules sequentially, **re-parsing between every rule**
(`lib/pattern.ex:79-104`). So two rules never patch the same bytes in one pass; the real
risks are (a) *ordering dependency* — one rule's output is another's input, and the order
is alphabetical-by-accident — and (b) *redundancy* — several rules converging on the same
endpoint via wasted passes.

### Cluster A — grapheme/count → `String.length` (redundant, ordering-fragile)

Three rules can all act on `String.graphemes(text) |> Enum.count()`:
- `avoid_graphemes_enum_count` → `String.length(text)` (`lib/pattern/avoid_graphemes_enum_count.ex`)
- `no_enum_count_for_length` → `length(String.graphemes(text))` — because `String.graphemes`
  is in its `@list_returning` allow-list (`lib/pattern/no_enum_count_for_length.ex:50`)
- `avoid_graphemes_length` → `String.length(text)` — matches `length(String.graphemes(x))`
  (`lib/pattern/avoid_graphemes_length.ex`)

**Do they double-fire?** Not in one pass. On `Enum.count(String.graphemes(text))` both
`avoid_graphemes_enum_count` and `no_enum_count_for_length` fire in `check`. Which one's
fix lands first is decided alphabetically: `AvoidGraphemesEnumCount` < `NoEnumCountForLength`,
so the grapheme rule runs first, produces `String.length(text)`, and the count rule then
sees no `Enum.count` and is inert. **The correct outcome depends on the alphabet.** Had the
rule been named `NoGraphemesEnumCount`, `no_enum_count_for_length` would win the first pass
(`length(String.graphemes(text))`), and `avoid_graphemes_length` would finish the job on a
later pass — same endpoint, different path, one extra pass.

This exact convergence is documented by the maintainer in commit `8b750fe`:
*"avoid_graphemes_enum_count: followup — duplicate of no_enum_count_for_length … which with
avoid_graphemes_length already reaches the same String.length(x) endpoint; fold/drop needs a
cross-file change."* The redundancy is known and unresolved. Endpoint is correct, but three
rules cover one transform through a fixpoint that only terminates cleanly because of the
re-parse loop + alphabetical order.

### Cluster B — sort rules (semantic overlap + shared defect)

`no_sort_then_reverse`, `no_double_sort_same_list`, `no_sort_then_at`, `no_sort_for_top_k`,
`prefer_desc_sort_over_negative_take`. Two of these perform **inverse** transforms:
- `no_sort_then_reverse`: `Enum.sort(x) |> Enum.reverse()` → `Enum.sort(x, :desc)`
- `no_double_sort_same_list`: `desc = Enum.sort(arr, :desc)` → `desc = Enum.reverse(asc)`
  (given a sibling `asc = Enum.sort(arr)`) — i.e. the reverse rewrite direction.

They match disjoint shapes (adjacent pipe vs two bound assignments), so they don't
oscillate, but they encode **opposite** claims of the same (false) equivalence — see §5 for
the shared int/float defect. This is an interaction worth flagging: the codebase asserts
`sort|>reverse ≡ sort(:desc)` in one rule and its inverse in another, both undefended.

### Cluster C — `if … true/false` collapse (well-coordinated, positive example)

`no_if_true_false` and `prefer_negate_if_true_false` both target
`if cond do false else X end`. They are **deliberately partitioned**:
`prefer_negate_if_true_false.anti_pattern?/2` calls `handled_by_no_if_true_false?/2`
(`lib/pattern/prefer_negate_if_true_false.ex:140-142`) and bails whenever the condition is
provably boolean and the else body is boolean — exactly `no_if_true_false`'s territory. So:
- provably-boolean condition + boolean branches → `no_if_true_false` collapses to a bare
  boolean expression;
- non-boolean condition or non-boolean else body → `prefer_negate_if_true_false` does the
  negate-and-swap (keeping `false` to preserve the boolean return).

I could not construct an input where both fire. Their DSL guards differ correctly too
(`no_if_true_false` is `:all` because it emits bare `and/or/not`; `prefer_negate` is
`[:ash_expr, :nx_defn]` because it emits `!`). **This is the model the rest of the set
should follow.** (One maintenance smell: `condition_bool?/1` and `boolean_expr?/1` are
copy-pasted verbatim into both files — the second file even documents the duplication at
line 148.)

### Cluster D — reduce → `Enum.X` (breadth, historically fragile)

`no_explicit_sum_reduce`, `no_explicit_product_reduce`, `no_list_append_in_reduce`,
`no_reduce_for_map_building`, `no_reduce_for_group_by`, `no_manual_list_reduce`,
`prefer_multi_clause_reduce_fn`, `no_eager_with_index_in_reduce`,
`prefer_reduce_while_with_halt_value`, `no_reduce_while_without_halt`. No same-pass
double-fire found (each keys on a distinct reduce shape), but this family is where the
evolution branch rejected the most variants (§4): `no_list_append_in_reduce` was reverted
for check/fix disagreement, and sibling reduce rules (`no_explicit_max_reduce`,
`no_explicit_min_reduce`, `no_manual_enum_uniq`) were deleted outright.

---

## 3. Consistency audit (~30 rules skimmed)

**Issue metadata: line only.** Every pattern/semantic/syntax Issue builds
`meta: %{line: …}` (146/146 pattern rules). No rule populates a column, so all downstream
consumers get line-granularity positions only. Consistent, but coarse.

**Message style: inconsistent.** Two coexisting styles, sometimes within one cluster:
- terse single sentence — `prefer_map_intersect_over_mapset_intersection`:
  `"Use \`Map.intersect/3\` instead of MapSet intersection pipeline on map keys."`
- multi-line heredoc with `# Before` / `# After` code blocks — `avoid_graphemes_enum_count`,
  `no_manual_max` (`build_message/0` returns a 4-line heredoc).

~128/146 use heredoc-form messages; the rest are one-liners. No functional impact, but a
rule author has no single template to follow.

**Naming convention.** Files are snake_case, modules CamelCase, the Issue `:rule` atom
matches the file stem — consistent. Prefix convention (`no_` / `prefer_` / `avoid_`) is
*mostly* followed; outliers that break it: `non_grouped_clauses`, `redundant_list_guard`,
`hallucinated_guard`, `unnecessary_grapheme_chunking`, `use_map_join`,
`remove_unreachable_clauses_after_catchall`. Cosmetic.

**Test structure — a genuine strength.** `Credence.RuleTestCompletenessTest` enforces a
mandatory triplet per rule: `<name>_check_test.exs`, `<name>_fix_test.exs`,
`<name>_equivalence_test.exs` (that is why there are ~445 test files for 146 rules). Meta
tests (`fix_meta_test`, `check_meta_test`, `equivalence_meta_test`,
`rule_test_completeness_test`, `no_parser_calls_in_rule_tests_test`) guard against stubs and
naming drift. Specifics from the six-plus files I opened:

- **Fixture style / byte-exactness.** `Credence.RuleCase.fix/3` (`test/support/rule_case.ex`)
  returns the exact bytes the pipeline ships — no re-formatting — and `confirm_fix/2`
  compares byte-exact modulo trailing newline. Documented rationale: re-formatting would
  *launder* a rule that re-indents lines it never touched.
- **Idempotency & compile-checking.** `RuleCase` exposes `valid_syntax?/1` and `compiles?/1`
  (the latter via `Code.compile_string`). The production pipeline itself reverts any fix
  whose output does not compile (`lib/pattern.ex:135` → `apply_or_revert/6`), so
  "fix output compiles" is enforced at runtime for every rule, not just in tests.
- **Non-firing on look-alikes — deep.** `no_uniq_then_count_check_test.exs` has 6 firing +
  **8 non-firing** cases: `Enum.uniq_by`, `Enum.count(predicate)`, already-target
  `MapSet.new |> MapSet.size`, wrong-arity `Enum.uniq(:by)`, bare `Enum.uniq`, etc. 236/445
  test files contain negative-assertion phrasing (`refute` / "does not" / "no issue").
- **Behaviour equivalence — real eval, `===`.** `Credence.BehaviourEquivalence`
  (`test/support/behaviour_equivalence.ex`) compiles before/after and evaluates over an
  adversarial input set, comparing with **strict `===`** so int↔float changes are caught
  (line 88: *"value-kind (int↔float) changes are exactly what this suite must catch"*), plus
  exception-parity and an anti-stub "inputs must discriminate ≥2 outcomes" gate.

**The blind spot that let a real defect through (see §5).** The equivalence harness is only
as good as its input generators. `no_sort_then_reverse_equivalence_test.exs` feeds
`EquivalenceInputs.stability_lists()`, whose entries are all **identical-value integer**
lists: `[], [1,1,1], [3,1,2,1,3,2], [2,2,1,1,3,3], [5,4,3,2,1], [1,2,3,4,5],
Enum.map(1..50, &rem(&1,3))`. For identical duplicates, `sort|>reverse` and `sort(:desc)`
are `===`-equal (indistinguishable elements), so the test passes. The **same support file**
defines `term_lists()` which *deliberately* includes `[1, 1.0, 1, 1.0, 2]` with the comment
*"value-kind trap: 1 and 1.0 are distinct as keys, equal-not-identical in <"*. The
stability tests reach for the wrong generator, so the trap the project already owns never
runs against the sort rules.

---

## 4. Git archaeology (provenance & escaped-defect rates)

### (a) Provenance — how rules arrived

Bucketing every current pattern rule by its first-add commit date (`git log --follow
--diff-filter=A`):

| era | count | merge vehicle |
| --- | ----- | ------------- |
| ≤ 2026-05-14 (pre-evolution, hand-written/curated) | 60 | direct commits + PRs #1–#3 |
| 2026-06-03 … 06 (evolution burst 1) | 47 | PR **#14** `evolution_accepted` (2026-06-08) |
| 2026-06-16 … 17 (evolution burst 2) | 39 | PR **#17** `evolution_accepted` (2026-06-17) |

So **~86 of 146 (59%) arrived via the two `evolution_accepted` merges** — the LLM-harness
output — and ~60 (41%) predate them. Burst 2 is unmistakably automated: ~30 `prefer_*`
rules landed between 22:10 and 01:26 on 2026-06-16/17, each with its full test triplet,
minutes apart.

### (b) Escaped defects — rules fixed after landing

**DSL-guard retrofit (largest escaped-defect class).** The `unsafe_in_dsl/0` guard did not
exist until 2026-06-29 (`ce7b766`) and PR **#20** `fix-unsafe-macro-refactorings`
(2026-07-02). All 14 DSL-guarded rules — `no_manual_max`, `no_if_true_false`,
`no_kernel_op_in_pipeline`, `prefer_erlang_float`, etc. — **shipped and fired inside
Ash/Ecto/Nx blocks for weeks** before the guard was added. `git log -S 'def unsafe_in_dsl,
do: :all' -- no_manual_max.ex` shows the declaration first appears in `ce7b766`, ~2 months
after the rule was born (2026-04-25). This is a systemic escaped defect: the whole class of
"rewrite changes a DSL-reinterpreted construct" was invisible to the generator until a
human noticed it in production.

**Named post-landing bugfixes** (from commit messages):
- `prefer_erlang_float` — fixed at least twice: `8213b98` *"set to be before other rules —
  fix to regression of fix to PR #4"*, then PR #20 added the `[:ash_expr, :ecto_query]` guard.
- `no_map_keys_or_values_for_iteration` — `fc249cc` bugfix, then `0009ad3` *"bugfixed thanks
  to #11"*; also `f45bb0e` (evolution) *"hand-rolled paren scanner miscounts char-literal
  `?)` — regresses valid input `&(&1 == ?))` … now emits non-compiling `end))`"*.
- `no_length_comparison_for_empty` — `4450c13` bugfix.
- `AvoidGraphemesEnumCount` — `d89971e` *"split into two rules and bugfixed"*.
- `no_string_length_for_char_check` — `0151f4a` bugfix.

**Churn proxy** (`git log --follow` commit count per file) — the most-fixed rules are
mostly the *old* ones, which have had the longest to accumulate bugfixes:
`no_map_keys_or_values_for_iteration` (24), `no_sort_then_at` (18),
`no_redundant_enum_join_separator` (16), `no_nested_enum_on_same_enumerable` (16),
`no_map_then_aggregate` (16). (Counts include formatting/refactor commits, so this is a
rough proxy.)

### (c) Rules deleted after landing

**40** pattern-rule files have been deleted over the project's history. Notable batches:
- `aa56849` (2026-05-19) *"Massive rewrite, warning rules pushed out"* — removed ~16
  detect-only/loop rules (`no_enum_at_in_loop`, `no_list_append_in_loop`, `no_map_as_set`,
  `no_repeated_enum_traversal`, …). Policy: Pattern rules must fix, not just warn
  (`lib/pattern/rule.ex:6`).
- `5efef5b` (2026-06-16) *"First batch — deleted rules"* — 9 rules including
  `no_enum_at_negative_index`, `no_kernel_shadowing`, `no_param_rebinding`,
  `no_trivial_delegation`, `inconsistent_param_names`.
- Behavioral-test rounds (2026-06-06) deleted `no_explicit_max_reduce`,
  `no_explicit_min_reduce`, `no_manual_enum_uniq`, `no_map_get_sentinel`,
  `no_multiple_enum_at`.

**The richest escaped-defect signal is the 105 `"followup —"` rejection commits** on the
evolution branch — the harness documenting a generated rule it then rejected. These are a
catalogue of exactly how auto-generated rules go wrong. Representative examples (verbatim
gist), grouped by failure mode:

- **Sort stability / arity assumptions** — `no_sort_with_key_comparator`: *"strict `</>`
  comparators aren't stable like sort_by's `<=/>=` … and the tuple pattern `{_,_,w1}` raises
  FunctionClauseError on wrong-arity tuples while `&elem(&1,2)` silently succeeds."*
- **Error semantics on non-integers / negatives** — `no_rem_for_parity_check`: *"`rem(x,2)`
  raises ArithmeticError on non-integers while Integer.is_even/is_odd returns false, and the
  `==1/!=1` cases are wrong for negative integers."*
- **Unicode equivalence** — `prefer_string_capitalize`: *"diverges on Unicode special-casing
  (ß→SS vs Ss, ligature ﬁ→FI vs Fi)."* — `no_string_split_whitespace_regex`: *"String.split/1
  … Unicode-whitespace semantics that no `~r/\s/` regex matches."*
- **Scope / unbound-variable** — `no_single_use_binding`: *"removes a binding still
  referenced later … → unbound-var CompileError."*
- **check/fix disagreement** — `no_list_append_in_reduce`, `prefer_map_intersect…`: check
  fires on cases the fix won't touch.
- **fix renames unrelated callees** — `prefer_string_capitalize`: *"fix hardcodes
  `capitalize_string(string)` while the check fires on any function name, renaming other
  defps and breaking their callers."*
- **Text-surgery on unparseable source** — a whole rejected class
  (`no_markdown_code_fences`, `prefer_cond_do_keyword`, `no_while_keyword`,
  `no_spec_do_block`, `no_for_comprehension_by_step`, …): *"line-regex … corrupts content
  inside @moduledoc heredocs (proven) … syntax phase has no per-rule parse-revert."*

Two of that last class (`no_markdown_code_fences`, `prefer_cond_do_keyword`) **do ship on
main** — but as **hardened rewrites**, not the rejected line-regex (see §6). So the
evolution "followup" rejections are the harness's self-filter; a rejected *concept* was
sometimes re-implemented safely by hand.

---

## 5. Deep critique of 12 rules

Rated **solid** / **minor risk** / **real defect**. Citations are `file:line`.

### 5.1 `no_sort_then_reverse` — REAL DEFECT (int/float tie), core rule (2026-04-24)
File claims *"Sorting ascending then reversing is equivalent to `Enum.sort(list, :desc)`"*
(`lib/pattern/no_sort_then_reverse.ex:6-8`) with no assumption. `Enum.sort/1` is a **stable**
sort; `Enum.sort(list, :desc)` also keeps equal elements in original order; but
`Enum.sort(list) |> Enum.reverse()` *reverses* the order of each tie-group. For elements
that are order-equal but `===`-distinct (only ints vs value-equal floats), the two differ.

Concrete input (fires via the pipe branch, `check/2` line 36-46; fix line 90-95):
```
[1, 1.0] |> Enum.sort() |> Enum.reverse()   # original ⇒ [1.0, 1]
[1, 1.0] |> Enum.sort(:desc)                # fix      ⇒ [1, 1.0]
```
`[1.0, 1] !== [1, 1.0]`. Behaviour changed. Escapes because its equivalence test feeds
`stability_lists()` (identical dups only) instead of `term_lists()` (§3).

### 5.2 `no_sort_then_at` — REAL DEFECT (max/last tie), core rule (2026-04-24)
Maps `Enum.sort(c) |> Enum.at(-1)` (ascending, last) to `Enum.max(c, fn -> nil end)`
(`lib/pattern/no_sort_then_at.ex:207`). `Enum.at(-1)` after a stable sort returns the
**last** among equal-maximal elements; `Enum.max` returns the **first** maximal element.
```
Enum.sort([1, 1.0]) |> Enum.at(-1)   # original ⇒ 1.0  (stable sort keeps [1,1.0], last = 1.0)
Enum.max([1, 1.0], fn -> nil end)    # fix      ⇒ 1    (first maximal)
```
`1.0 !== 1`. Real divergence on mixed int/float; undeclared, no assumption. (The `:asc,
:first`→`Enum.min` direction happens to agree, because `Enum.min` and `at(0)` both pick the
first minimal — so only the max/last direction is wrong.) Note this rule already carries a
dedicated regression test file `test/no_sort_then_at_kth_largest_regression_test.exs`, so it
is known-fragile.

### 5.3 `no_double_sort_same_list` — REAL DEFECT (same class, inverse direction), 2026-04-25
Rewrites `desc = Enum.sort(arr, :desc)` → `desc = Enum.reverse(asc)` where `asc =
Enum.sort(arr)` (`lib/pattern/no_double_sort_same_list.ex:73-88`). This is the exact inverse
of 5.1 and carries the same defect:
```
arr = [1, 1.0]
Enum.sort(arr, :desc)          # original desc ⇒ [1, 1.0]
Enum.reverse(Enum.sort(arr))   # fix desc      ⇒ [1.0, 1]
```
Diverges on the same input. Three sibling rules encode the false `sort|>reverse ≡ sort(:desc)`
equivalence with no guarding assumption.

> These three are the strongest concrete finding: an undeclared, cross-rule semantic bug in
> the oldest hand-written code, masked by an input-generator gap. A one-line assumption
> (e.g. a `homogeneous_numeric_ordering` switch) or adding `term_lists()` to the three
> equivalence tests would surface it.

### 5.4 `no_manual_max` — SOLID, core rule (2026-04-25)
Only rewrites the **non-strict** forms `if a >= b, do: a, else: b` → `max(a, b)`
(`lib/pattern/no_manual_max.ex:129-137`), with an explicit, correct analysis that the strict
`>` form diverges from `max/2` on `max(1, 1.0)` ties (moduledoc lines 30-34). DSL guard
`:all` is correct (`max/2` is not a query operator; element-wise in Nx). This is the *right*
way to handle the tie problem the sort rules got wrong — notable that the same repo contains
both the careful and the careless treatment.

### 5.5 `no_enum_count_for_length` — SOLID (with cluster caveat), 2026-04-26
Fires only on a **provably-list** argument (literal, `++`, or an allow-listed list-returning
call — `lib/pattern/no_enum_count_for_length.ex:45-54, 139-157`), correctly avoiding
`length(1..5)` raising where `Enum.count` would not. Also folds `Enum.count(Map.keys(m))` →
`map_size(m)` and notes `===` parity incl. BadMapError (line 94-100). Correct. Caveat: it is
one leg of the redundant grapheme/count cluster (§2A).

### 5.6 `no_if_true_false` — SOLID, evolution burst 1 (2026-06-04)
Gates every rewrite on `condition_bool?/1` (`lib/pattern/no_if_true_false.ex:135-162`) with
a precise rationale that `if x do true else false end` returns `true` for truthy non-boolean
`x` while bare `x` returns `x`, and `x and expr` would `BadBooleanError` (lines 129-134).
All six collapse forms preserve short-circuit evaluation order. DSL `:all` correct. A model
LLM-generated rule.

### 5.7 `prefer_negate_if_true_false` — SOLID (coordination), burst 2 (2026-06-17)
Correctly partitioned against 5.6 (§2C); DSL guard `[:ash_expr, :nx_defn]` correct because
it introduces `!` (which Ash reinterprets as `%Ash.Query.Call{name: :!}`), and it explains
why Ecto is *omitted* (Ecto compile-errors on `!`, already caught by the compile gate —
lines 41-43). Careful.

### 5.8 `no_uniq_then_count` — SOLID, burst 2 (2026-06-06)
`enum |> Enum.uniq() |> length()` → `enum |> MapSet.new() |> MapSet.size()`. The moduledoc
proves exactness via `===`/map-key equality — *"`1` and `1.0` stay distinct under both … the
number of distinct elements is identical"* (`lib/pattern/no_uniq_then_count.ex:23-30`). This
is the same int/float reasoning the sort rules lack — an auto-generated rule that got the
value-kind analysis **right**. Excludes `Enum.count(predicate)` and `uniq_by` correctly.

### 5.9 `no_double_filter` — SOLID / minor, burst 2 (2026-06-05)
Two adjacent complementary `Enum.filter` on the same **variable** → `Enum.split_with`
(`lib/pattern/no_double_filter.ex`). Narrowing is careful: capture predicates over a
`simple_operand?` only (literal/bare var, never a call — rules out double-eval side effects,
lines 152-161), complement operator table (`>=`/`<`, `>`/`<=`, `==`/`!=`), adjacency,
distinct binds. Split_with preserves order like filter — correct. **Minor risk:** the fix
text-slices the source with a single-line `slice/2` (lines 173-176); a predicate or source
spanning two lines would mis-slice. Given the operand constraints this is unlikely but
undefended. Comments between the two statements would also be dropped.

### 5.10 `no_zip_then_map` — SOLID, burst 2 (2026-06-05)
`Enum.zip(a,b) |> Enum.map(fn {x,y} -> body end)` → `Enum.zip_with(a, b, fn x, y -> body
end)`. Requires a single-clause fn whose param is a 2-tuple of **plain variables**
(`find_2tuple_vars/1` rejects `{x, 0}` and multi-clause fns — lines 178-196), excludes
guarded fns and the genuine `Enum.zip/1`-at-pipe-head (lines 220-232). Semantically exact
(both truncate to the shorter enumerable). Correct.

### 5.11 `prefer_map_intersect_over_mapset_intersection` — MINOR (over-fit), burst 2 (2026-06-17)
Correct after its evolution-branch rework (bare-var operands, `pure_merge?` gate,
`var_used_once?`, `sort` vs `sort_by(key)` justified by unique keys —
`lib/pattern/prefer_map_intersect_over_mapset_intersection.ex:96-118, 270-283`). But the
matcher (`extract_mapset_pipeline_vars/1`, lines 160-186) hard-codes an **exact four-stage
pipeline** `Map.keys |> MapSet.new |> MapSet.intersection(MapSet.new(Map.keys)) |>
MapSet.to_list` followed by an **exact** two-`Map.fetch!`-plus-merge `Enum.map`. This is one
specific word-frequency-intersection snippet. Any whitespace-level structural variation
(different pipe direction, `MapSet.intersection` args swapped, a `min` inlined) misses. Near
-zero real-world generality; a maintenance liability more than a risk. (Also the moduledoc
claims Elixir 1.14; `Map.intersect/3` is 1.15.)

### 5.12 `prefer_lookup_for_digit_conversion` — MINOR (over-fit), burst 2 (2026-06-16)
Detects **exactly 16** `defp name(0..15), do: "0".."F"` clauses and collapses to
`defp name(remainder) when remainder in 0..15, do: "0123456789ABCDEF" |> String.at(remainder)`.
Correctness is actually good — the guard `when remainder in 0..15` is added deliberately to
preserve the original `FunctionClauseError` domain (out-of-range/`5.0` still fails identically),
and duplicate-clause first-match-wins is handled (`lib/pattern/prefer_lookup_for_digit_conversion.ex:158-169,
205-215`). But it fires only on the precise, complete hex table
(`complete_hex_mapping?` requires `mapping == @expected_values`, line 243-245). Like 5.11,
this solves one canned exercise, not a class of code. `prefer_string_slice_for_trim_last_char`
is a third instance of the same over-fit shape (matches an exact 3-clause `case
String.graphemes` — correct, but a single snippet).

**Rating tally:** 3 real defects (all the old sort cluster, one shared bug), 6 solid,
3 minor (over-fit / slicing). The real defects are concentrated in **hand-written 2026-04**
code; the auto-generated burst rules are mostly correct but skew toward **over-fitting**.

---

## 6. Syntax + Semantic rules (brief pass)

### Syntax (`lib/syntax/`, 19 rules)
The Syntax phase runs a rule's `analyze/fix` **only when the whole file fails to parse**
(`lib/syntax.ex:14-16`) and, per the evolution followups, has **no per-rule parse-revert** —
so text-surgery rules are inherently the riskiest in the codebase and must each self-guard.

- `no_markdown_code_fences` — strip ```` ``` ```` wrapper lines. **Ships hardened**: only the
  first/last non-blank line is eligible (**anchor** guard) and the strip is committed only
  if the result then parses (**parse gate**) — `lib/syntax/no_markdown_code_fences.ex:78-117`.
  This directly answers the rejected line-regex version (`96e1f44`). Solid.
- `prefer_cond_do_keyword`, `no_else_if`, `prefer_spec_arrow_operator`,
  `no_fn_with_capture`, `no_unclosed_fn_delimiter`, `close_unclosed_fn_delimiter`,
  `close_unclosed_doc_heredoc`, `fix_missing_module_end` — structural repairs of specific
  parse failures.
- **Python-ism repairs** (LLM cross-language bleed): `fix_python_modulo` (`a % b`→`rem`),
  `fix_python_floor_div` (`//`→`div`), `fix_python_augmented_assignment` (`x += 1`),
  `fix_scientific_notation`, `fix_truncated_binary_close`, `fix_stale_access_modifier`,
  `fix_div_rem`, `fix_do_block_fusion`, `fix_malformed_spec`.
- **Regex-hazard note.** Several do regex/line surgery on unparseable text (`fix_do_block_fusion`
  is the densest, `no_else_if` next). `no_markdown_code_fences` demonstrates the correct
  mitigation (parse-gate before commit); any Syntax rule *without* an equivalent
  "commit-only-if-it-now-parses" gate is a latent version of the exact bug the evolution
  branch rejected 7+ times. This is the highest-leverage place to standardize a guard.

### Semantic (`lib/semantic/`, 16 rules)
Compiler-diagnostic-driven fixes (unused vars, undefined fns). One-liners:
- `unused_variable`, `used_underscore_variable`, `no_underscore_in_expression`,
  `remove_unused_typespec_when_var` — unused/underscore variable hygiene.
- `undefined_function`, `undefined_string_alphanumeric` — **hallucinated-API repairs** (the
  latter targets a fabricated `String.alphanumeric?/1`). `undefined_function` is the largest
  semantic rule (569 LOC, regex-dense) — worth its own correctness review given size.
- `no_doc_on_private_function`, `no_bare_doc_attribute`, `no_bare_names_in_spec`,
  `no_non_negated_integer`, `outdented_heredoc`, `require_defmodule_wrapper`,
  `missing_use_exunit_case`, `prefer_explicit_range_step` — doc/spec/structural.
- `no_capture_as_bitwise_and` — repairs `&` misread as bitwise-AND (an AST-shape hazard).
- `prefer_kernel_max_over_local` — conceptually adjacent to pattern `no_manual_max`, but
  operates on local `max/min` shadowing; no direct collision (different phase, different
  shape).

Semantic rules lean on `Regex`/`String.replace` more than pattern rules
(`undefined_function` regex count 21, `undefined_string_alphanumeric` 7), but they run on
*parseable* code guided by real compiler diagnostics, so the text surgery is comparatively
anchored. No obvious defect surfaced in this brief pass; `undefined_function`'s size is the
main flag.

---

## 7. Top recurring quality problems (ranked by severity)

1. **Undeclared value-kind (int/float) semantic divergence in "equivalent" rewrites, hidden
   by an input-generator gap.** The three sort rules (§5.1–5.3) change behaviour on
   `[1, 1.0]`; the equivalence harness that exists to catch exactly this uses
   `stability_lists()` (identical dups) instead of the `term_lists()` value-kind trap the
   project already maintains. *Severity: high — real behaviour change on real (if rare)
   input, in the oldest code, with a fix already sitting unused in the test support.*

2. **DSL-reinterpretation blindness shipped for weeks.** 14 rules fired inside Ash/Ecto/Nx
   blocks with wrong runtime meaning until `unsafe_in_dsl/0` was retrofitted (PR #20 /
   `ce7b766`), ~2 months after some rules were born (§4b). The generator had no notion of
   AST-reinterpreting macros. *Severity: high — silent wrong output that still compiles;
   only 14 rules are classified, so uncovered rules in the same families remain a risk.*

3. **Over-fitting to a single training example.** `prefer_map_intersect_over_mapset_intersection`,
   `prefer_lookup_for_digit_conversion`, `prefer_string_slice_for_trim_last_char` (§5.11–5.12)
   each match one exact multi-clause snippet and are correct but nearly un-fireable on real
   code. *Severity: medium — not wrong, but dead weight that inflates the rule count,
   maintenance surface, and pipeline cost with ~zero coverage.*

4. **Ordering-by-accident under uniform priority.** 139/146 rules sit at priority 500, so
   inter-rule order is alphabetical (§1, §2A). The grapheme/count cluster produces the right
   endpoint only because `Avoid…` sorts before `No…`. *Severity: medium — currently benign,
   but any rename or new same-family rule can silently reorder a fixpoint.*

5. **Redundant/overlapping rules that the maintainer already flagged but did not fold.**
   grapheme/count 3-way convergence (`8b750fe`), `avoid_length_guard_less_than2` documented
   as a duplicate of `no_length_guard_to_pattern` (`8c4eb9a`) yet still shipped. *Severity:
   low–medium — wasted passes and duplicated logic; the copy-pasted `condition_bool?` across
   the two `if`-rules is the same smell at function granularity.*

6. **Text-surgery rules without a uniform safety gate.** The Syntax phase rejected 7+
   line-regex rules for corrupting heredoc content, then shipped two safely by adding a
   parse-gate — but that gate is per-rule, not a phase-level invariant (§6). *Severity:
   medium for the Syntax phase specifically — the next generated regex rule can reintroduce
   the class unless the gate is centralized.*

7. **Cosmetic inconsistency (metadata & messages).** Line-only Issue positions (no column);
   two message styles (terse vs heredoc) with no template. *Severity: low.*

### What the evidence says about improving auto-generated quality
The auto-generated rules are, on average, *more* careful about the value-kind trap
(`no_uniq_then_count`, §5.8) and DSL safety than the oldest hand-written ones — the harness
clearly learned those lessons (the 105 `followup —` rejections are that learning, written
down). The residual auto-gen defects are (a) **over-fitting** (rank 3) and (b) **coverage
gaps in the very oracle that gates them** — the equivalence harness passes a rule whose
input set can't discriminate the bug (ranks 1). The highest-leverage improvements are
therefore oracle-side, not rule-side: make the equivalence generators mandatory-adversarial
per operation class (feed `term_lists()`/value-kind and Unicode traps to every
sort/count/string rule), classify DSL-safety at generation time rather than in a later human
pass, and add a generality gate (reject a rule that matches only one literal AST shape).
