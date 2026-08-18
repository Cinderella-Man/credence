# 25 — Mutation survivor triage (D9(a))

**Every survivor of the 2026-08-18 sweep, sorted into *a test could catch this* versus
*no test could*.** D9(a) asked for exactly this: triage the survivors, ledger the
equivalent ones, and floor against the triaged rate rather than the raw one.

Reproduce the sweep exactly — the sample is a pure function of `{rule module, seed}`:

```
MIX_ENV=test mix credence.mutants --sample 39 --seed 0 --cap 40 --out DIR
```
Elixir 1.20.2 / OTP 29. The machine-readable ledger with every argument in full is
`docs/25-survivor-triage.json`; this file is the summary and the reasoning.

## The number

| | mutants | rate |
| --- | ---: | ---: |
| killed | 631 | |
| survived | 225 | |
| — of those, **equivalent** (no input separates them) | 94 | |
| — of those, **real gaps** (an input exists) | 131 | |
| **raw** — what the sweep reports | | **0.7371** |
| **triaged** — equivalents out of the denominator | | **0.8281** |

**94 of 225 survivors (42%) cannot be killed by any test.** D9's earlier 14-row
sample put that at 14–21% and called ≈0.77 a ceiling "and probably higher". It was
right in direction and low: the ceiling is **0.8281**.

So `--fail-under 0.740` would sit **0.09 below** what the tests already earn — it could
not fail anything, which is the outcome C18 staged this work to avoid.

## Why a global floor is still the wrong shape

The triaged distribution runs **0.400 to 1.000**. Six rules are already perfect and one
sits at 0.400. A single global number is satisfied by the strong rules while the weak
ones sit under it untouched — it would ratchet nothing. Floor **per rule**.

## Per-rule, worst first

`triaged = killed / (killed + gaps)`. A rule at 1.000 has no reachable untested
behaviour left in the four operator families; it does not mean its tests are complete.

| rule | layer | killed | gaps | equiv | raw | **triaged** |
| --- | --- | ---: | ---: | ---: | ---: | ---: |
| `prefer_no_question_mark_for_non_boolean` | pattern | 4 | 6 | 0 | 0.400 | **0.400** |
| `no_duplicate_defstruct` | semantic | 5 | 3 | 0 | 0.625 | **0.625** |
| `no_sort_then_reverse` | pattern | 10 | 6 | 8 | 0.417 | **0.625** |
| `no_manual_frequencies` | pattern | 13 | 7 | 0 | 0.650 | **0.650** |
| `no_python_multi_return` | syntax | 21 | 11 | 8 | 0.525 | **0.656** |
| `no_enum_count_for_length` | pattern | 16 | 8 | 3 | 0.593 | **0.667** |
| `prefer_desc_sort_over_negative_take` | pattern | 15 | 7 | 3 | 0.600 | **0.682** |
| `fix_negated_capture_with_arity` | semantic | 13 | 6 | 1 | 0.650 | **0.684** |
| `fix_mixed_required_optional_map_keys` | syntax | 25 | 9 | 5 | 0.641 | **0.735** |
| `fix_with_else_bare_value` | semantic | 3 | 1 | 0 | 0.750 | **0.750** |
| `no_naive_datetime_new_with_tuple` | semantic | 6 | 2 | 0 | 0.750 | **0.750** |
| `no_redundant_case_nil_clause` | pattern | 6 | 2 | 4 | 0.500 | **0.750** |
| `fix_reraise_keyword_in_catch` | semantic | 17 | 5 | 2 | 0.708 | **0.773** |
| `no_reduce_for_group_by` | pattern | 28 | 8 | 4 | 0.700 | **0.778** |
| `no_sort_for_top_k` | pattern | 28 | 8 | 4 | 0.700 | **0.778** |
| `fix_python_floor_div` | syntax | 4 | 1 | 1 | 0.667 | **0.800** |
| `no_redundant_to_list` | pattern | 9 | 2 | 0 | 0.818 | **0.818** |
| `no_undefined_module_in_rescue` | semantic | 9 | 2 | 0 | 0.818 | **0.818** |
| `prefer_string_split_trim` | pattern | 18 | 4 | 0 | 0.818 | **0.818** |
| `fix_plug_dependency_module_order` | semantic | 29 | 6 | 5 | 0.725 | **0.829** |
| `fix_hallucinated_stream_data_flat_map` | semantic | 15 | 3 | 2 | 0.750 | **0.833** |
| `fix_case_branch_assignment_scope` | semantic | 27 | 4 | 9 | 0.675 | **0.871** |
| `no_rescue_in_exception` | semantic | 7 | 1 | 0 | 0.875 | **0.875** |
| `no_manual_list_reduce` | pattern | 31 | 4 | 5 | 0.775 | **0.886** |
| `no_stream_data_tuple_with_list` | semantic | 29 | 3 | 6 | 0.763 | **0.906** |
| `no_length_comparison_for_empty` | pattern | 32 | 3 | 5 | 0.800 | **0.914** |
| `prefer_string_slice_for_trim_last_char` | pattern | 34 | 3 | 2 | 0.872 | **0.919** |
| `no_grapheme_palindrome` | pattern | 25 | 2 | 2 | 0.862 | **0.926** |
| `prefer_map_new_with_transform` | pattern | 28 | 2 | 2 | 0.875 | **0.933** |
| `no_postfix_if_expression` | syntax | 30 | 2 | 3 | 0.857 | **0.938** |
| `fix_hallucinated_naive_datetime_accessor` | semantic | 16 | 0 | 0 | 1.000 | **1.000** |
| `fix_stale_access_modifier` | syntax | 2 | 0 | 0 | 1.000 | **1.000** |
| `hallucinated_guard` | pattern | 18 | 0 | 0 | 1.000 | **1.000** |
| `no_case_destructure_in_pipe` | pattern | 5 | 0 | 0 | 1.000 | **1.000** |
| `no_doc_with_do_block` | syntax | 2 | 0 | 0 | 1.000 | **1.000** |
| `no_empty_map_new` | pattern | 10 | 0 | 0 | 1.000 | **1.000** |
| `no_hallucinated_ets_keytype_option` | pattern | 17 | 0 | 2 | 0.895 | **1.000** |
| `no_literal_list_typespec` | pattern | 8 | 0 | 0 | 1.000 | **1.000** |
| `no_string_concat_in_loop` | pattern | 16 | 0 | 8 | 0.667 | **1.000** |

## The second finding: 35 of the 94 equivalents are DEAD CODE

An equivalent mutant is not always "a value nothing can reach". Most of these are a
mutation of a branch **no input can enter at all** — which makes the survivor list a
map of this codebase's dead code, found for free.

The largest single instance, verified by hand: `no_sort_then_reverse` lines 197–203
match a capture arity as a **bare** `2`, but `Sourceror.parse_string/1` wraps every
literal as `{:__block__, _, [2]}`. Those two clauses can never match. The live copies
are the two immediately below them (lines 205–211) — and the tests **do** kill the
mutants on the live copies, which is exactly why only the dead twins survived. This is
the `{:__block__, _, [literal]}` trap and the two-copies-of-one-predicate smell in one
place.

Rules carrying provably-dead code, by where the sweep pointed:

| rule | lines |
| --- | --- |
| `no_sort_then_reverse` | 197, 198, 201, 202 |
| `no_python_multi_return` | 91, 200, 224, 684 |
| `no_manual_list_reduce` | 103, 257, 414 |
| `fix_plug_dependency_module_order` | 126, 205 |
| `no_postfix_if_expression` | 161, 163 |
| `no_redundant_case_nil_clause` | 160, 162 |
| `fix_mixed_required_optional_map_keys` | 162, 188 |
| `no_stream_data_tuple_with_list` | 202, 214 |
| `fix_case_branch_assignment_scope` | 173, 230 |
| `fix_python_floor_div` | 135 |
| `no_length_comparison_for_empty` | 166 |
| `no_grapheme_palindrome` | 61 |
| `no_hallucinated_ets_keytype_option` | 141 |
| `prefer_desc_sort_over_negative_take` | 157 |
| `prefer_map_new_with_transform` | 152 |

Deleting dead code leaves the **triaged** rate untouched — equivalents are already out of
its denominator — and pulls the **raw** rate up toward it, because the survivors it
counted disappear. Delete every dead branch found here and the raw rate rises 0.737 →
0.828, converging on the triaged number. That is the case for cleaning up first: it makes
the cheap number the sweep prints by default trustworthy on its own, without a triage
pass standing behind it.

One caveat before treating that as a clean arithmetic prediction. **Nine of the 39 rules
are at or one below the 40-mutant cap** (`fix_case_branch_assignment_scope`,
`fix_plug_dependency_module_order`, `no_length_comparison_for_empty`,
`no_manual_list_reduce`, `no_python_multi_return`, `no_reduce_for_group_by`,
`no_sort_for_top_k` at 40; `fix_mixed_required_optional_map_keys` and
`prefer_string_slice_for_trim_last_char` at 39). For those, removing dead lines does not
just delete mutants — it frees cap slots, and mutants that were never sampled take their
place. Their rates have to be re-measured after any cleanup, not projected.

## Method — what a survivor actually is

A survivor is not an "add a test" ticket. It is a request to construct an input that
**separates two programs**, and for many no such input exists. An equivalence claim has
to name the *mechanism* that makes the separating input impossible; "I could not think
of a test" is a gap someone failed to describe, not an equivalence.

Two calibration cases carried over from the earlier sample, both still valid:
`arity in 1..255` widened to `1..256`, where `&f/256` is a CompileError; and
`fix_extra_brace_in_ets_match`'s negative-index guard, which needs the parser to report
column 1 when it reports an opening delimiter's column (≥ 5 across ten shapes).

## How much to trust the 94

Every equivalence claim was re-examined by a second, independent pass whose only
instruction was to **refute** it by constructing a separating input. It overturned
**none**. A 0-of-94 refutation rate is itself suspicious, so two were checked by hand
against the running system rather than by reading:

* `no_sort_then_reverse` lines 197–203 — parsed `&>=/2` with the project's own Sourceror
  and confirmed the arity arrives wrapped, so the bare-`2` clauses are unreachable.
* `no_python_multi_return` line 224 — replaced the `Map.get/3` default with a `raise`,
  then ran the rule over **1,575 real files** (400 random corpus files, all of `lib/`,
  all of `test/`). The default was taken **zero** times.

The bias was set deliberately: when impossibility could not be proven, the instruction
was to answer GAP. A wrong EQUIVALENT inflates the rate and would set a floor above what
the tests earn — that failure is silent, and it arrives as false failures later.

## What is left, and it is a decision

The measurement is done. What remains is picking the floor, per rule, and that is a
maintainer call because it trades ratchet strength against false failures:

* **At the triaged rate** — maximum ratchet, zero slack. Any equivalent mutant this
  triage got wrong becomes a false failure the first time someone touches that rule.
* **A notch below it** (say triaged − 0.05) — absorbs one bad call per rule, still
  ratchets everywhere the raw floor could not.

Whichever: the six rules already at 1.000 pin at 1.000 for free, and
`prefer_no_question_mark_for_non_boolean` at 0.400 with **zero** equivalents is the one
rule whose tests are simply thin — six reachable behaviours, none covered.
