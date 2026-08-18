# 25 — Mutation survivor triage (D9(a))

**Every survivor of the 2026-08-18 sweep, sorted into *a test could catch this* versus
*no test could*.** D9(a) asked for exactly this: triage the survivors, ledger the
equivalent ones, and floor against the triaged rate rather than the raw one.

Reproduce the sweep exactly — the sample is a pure function of `{rule module, seed}`:

```
MIX_ENV=test mix credence.mutants --sample 39 --seed 0 --cap 40 --out DIR
```

Elixir 1.20.2 / OTP 29. `docs/25-survivor-triage.json` is the machine-readable ledger
with every argument in full; this file is the summary and the reasoning. Both are
generated from the run, not transcribed.

## The number

| | mutants | rate |
| --- | ---: | ---: |
| killed | 631 | |
| survived | 225 | |
| — of those, **equivalent** (no input separates them) | 92 | |
| — of those, **real gaps** (an input exists) | 133 | |
| **raw** — what the sweep reports | | **0.7371** |
| **triaged** — equivalents out of the denominator | | **0.8259** |

**92 of 225 survivors (41%) cannot be killed by any test.** D9's earlier 14-row sample
put that at 14–21% and called ≈0.77 a ceiling "and probably higher". It was right in
direction and low: the ceiling is **0.8259**.

So `--fail-under 0.740` would sit **0.09 below** what the tests already earn — it could
not fail anything, which is the outcome C18 staged this work to avoid.

## How reproducible is this?

The triage was run **twice, independently**. The two runs agree on **223 of 225 verdicts
(99.1%)**. Both disagreements went the same way — run 2 found separating inputs run 1
could not — so run 2's GAP set strictly contains run 1's, and **this file records run 2,
the conservative read**. Run 1 would have reported 0.8281; the difference is 0.002.

The aggregate is therefore stable to about ±0.002, but **an individual verdict is not a
certainty** — roughly 1 in 100 moved between runs. That matters for how the floor is set:
pinning exactly at the triaged rate assumes every one of these 92 equivalence calls is
right, and about one in a hundred is not.

## Why a global floor is the wrong shape

The triaged distribution runs **0.400 to 1.000**. 9 rules are already perfect; one sits at
0.400. A single global number is satisfied by the strong rules while the weak ones sit
under it untouched — it would ratchet nothing. Floor **per rule**.

## Per-rule, worst first

`triaged = killed / (killed + gaps)`. A rule at 1.000 has no reachable untested behaviour
left *in the four operator families the sweep uses*; it does not mean its tests are
complete.

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
| `fix_mixed_required_optional_map_keys` | syntax | 25 | 11 | 3 | 0.641 | **0.694** |
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

**Four of these rows are now stale, deliberately.** The dead-code deletions below moved
the RAW rate of `no_sort_then_reverse` (0.417 → 0.625), `no_redundant_case_nil_clause`
(0.500 → 0.545) and `prefer_desc_sort_over_negative_take` (0.600 → 0.625) toward their
triaged rate — which is the whole point of the cleanup, and leaves those triaged rates
unchanged, because every mutant removed was an equivalent one. The table is kept as the
record of the sweep it triages.

The exception to watch: `no_manual_list_reduce` is at the 40-mutant cap, so deleting one
dead line freed a slot and a **newly sampled, untriaged** mutant took it — and survived.
Its triaged rate is therefore 0.886 or 0.861 depending on that one verdict. Settle it
before pinning that rule's floor.

## Second finding: dead code — 28 sites, checked one at a time

An equivalent mutant is not always "a value nothing can reach". Some mutate a branch **no
input can enter at all**, which makes the survivor list double as a map of dead code,
found for free.

**A correction to this file's first draft.** It claimed "34 of the 92 equivalents are dead
code", from a keyword match over the triage arguments. That over-counted. Every site was
then examined individually (`docs/25-dead-code-verdicts.json`, one agent per rule, each
tracing the real compiled module rather than reading):

| verdict | sites | what it means |
| --- | ---: | --- |
| **DELETE** | 7 | genuinely unreachable, and removing it changes nothing observable |
| **KEEP** | 16 | unreachable today, but a deliberate defensive default — removing it trades a safe fallback for a crash or a silent mis-splice |
| **ALIVE** | 5 | not dead at all; the keyword match was wrong |

The five ALIVE ones do **not** overturn their EQUIVALENT verdicts. The mutant is still
unkillable — but because the mutated value is *masked* downstream, not because the line
cannot run. `no_python_multi_return` line 200 is the clearest: it is one of the hottest
lines in the module (41,567 executions over 532 files), and its `:error → :ok` mutant
survives only because the value flows into a `match?({:ok, _}, …)` that rejects both.

### The 7 that were deleted

`no_sort_then_reverse` 197–203 was the largest and is the archetype: two clauses matching
a capture arity as a **bare** `2`, where `Sourceror.parse_string/1` wraps every literal as
`{:__block__, _, [2]}`. They could never match, and their live twins sat immediately
below. The tests **do** kill the mutants on the live copies — which is exactly why only
the dead ones survived.

The others: `no_manual_list_reduce` 414 and `no_redundant_case_nil_clause` 162 (the same
bare-vs-wrapped literal shape), and `prefer_desc_sort_over_negative_take` 157 (a catch-all
on a `chunk_every(…, :discard)` result, which is always a 2-list).

Measured after deleting them, and it is not what a naive count predicts:

| rule | kill rate before | after |
| --- | ---: | ---: |
| `no_sort_then_reverse` | 0.417 | **0.625** |
| `no_redundant_case_nil_clause` | 0.500 | **0.545** |
| `prefer_desc_sort_over_negative_take` | 0.600 | **0.625** |
| `no_manual_list_reduce` | 0.775 | **0.775** |

`no_manual_list_reduce` did not move **because it sits at the 40-mutant cap**: deleting a
dead line freed a slot, a mutant that had never been sampled took it, and that one also
survived. This is the cap caveat below, observed rather than predicted — which is why the
nine at-cap rules must be re-measured after any cleanup, never projected.

### The 16 that were kept, and why that is not laziness

The recurring shape is a fallback whose default is unreachable *today* because of an
invariant owned by **another module** — `Sourceror` always attaching `:line`,
`SourceMask.enclosing_opener/2` halting at depth 0. Removing them means `fetch!` and a
raise where there is currently a safe value, and in one case
(`fix_mixed_required_optional_map_keys` 162) a negative depth that would silently return
the wrong byte offset into a `binary_part` splice — a wrong-place edit rather than a
crash. Unreachable is not the same as unnecessary.

## Method — what a survivor actually is

A survivor is not an "add a test" ticket. It is a request to construct an input that
**separates two programs**, and for many no such input exists. An equivalence claim must
name the *mechanism* making the separating input impossible; "I could not think of a
test" is a gap someone failed to describe, not an equivalence.

Two calibration cases carried over from the earlier sample, both still valid:
`arity in 1..255` widened to `1..256`, where `&f/256` is a CompileError; and
`fix_extra_brace_in_ets_match`'s negative-index guard, which needs the parser to report
column 1 when it reports an opening delimiter's column (≥ 5 across ten shapes).

The bias was set deliberately: where impossibility could not be *proven*, the instruction
was to answer GAP. A wrong EQUIVALENT inflates the rate and sets a floor above what the
tests earn — and that failure is silent until it arrives as false failures later.

Two equivalence claims were also checked by hand against the running system rather than
by reading:

* `no_sort_then_reverse` 197–203 — parsed `&>=/2` with the project's own Sourceror and
  confirmed the arity arrives wrapped, so the bare-`2` clauses are unreachable.
* `no_python_multi_return` line 224 — replaced the `Map.get/3` default with a `raise`,
  then ran the rule over **1,575 real files** (400 random corpus files, all of `lib/`,
  all of `test/`). The default was taken **zero** times.

## What is left, and it is a decision

The measurement is done. Picking the floor is a maintainer call, because it trades
ratchet strength against false failures:

* **At the triaged rate** — maximum ratchet, zero slack. Given the ~1-in-100 verdict
  instability measured above, expect roughly one false failure across the sample.
* **A notch below** (say triaged − 0.05) — absorbs a bad call per rule and still
  ratchets everywhere `--fail-under 0.740` could not.

The 9 rules already at 1.000 pin there for free.
`prefer_no_question_mark_for_non_boolean` (0.400, **zero**
equivalents) is the one rule in the sample whose tests are simply thin — 6 reachable
behaviours, none covered.
