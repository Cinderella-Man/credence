# TODO — behaviour-equivalence suite: remaining work

Status of the behaviour-equivalence effort (see `docs/07-behaviour-equivalence-harness.md`
for the full plan and divergence log).

## What is already DONE (context, so this file stands alone)

- **Backfill 100%.** All **117** `Credence.Pattern.Rule` modules have a real
  behaviour-equivalence test under `test/pattern/<name>_equivalence_test.exs`.
  Zero `:equivalence_todo` skeletons remain.
- **Gate flipped (hard).** `test/equivalence_meta_test.exs` discovers every rule
  and asserts (a) each has a test module `Credence.Pattern.<Name>EquivalenceTest`,
  and (b) no test is still tagged `:equivalence_todo`. `test/test_helper.exs` now
  calls `ExUnit.start()` with **no excludes**. Checks verified manually (hiding a
  rule's test fails the gate naming that rule).
- **All discovered shipped-rule divergences resolved** (fixed / narrowed / dropped /
  reinstated), logged in `docs/07` §"Confirmed divergences". Totals: 17
  fixed/narrowed, 7 dropped, 1 merged, 1 reinstated-as-repair (125 → 117 rules).
- **Tiers + marks** live in `test/support/behaviour_equivalence.ex`:
  `assert_equivalent/2` (T1), `assert_equivalent_module/2` (T2),
  `assert_effect_trace_equivalent/2` (PROBE), `mark_equivalence_cosmetic/1` (T3a),
  `mark_equivalence_unconstructible/1` (T3b), `mark_equivalence_repair/1` (T3c).
- Full suite: `mix test` → green, **0 excluded** (≈4347 tests).

The items below are the parts of `docs/07` §"Verification" / §"Unresolved
questions" that are **NOT** yet done. They are confidence/rigor work, not coverage
gaps — every rule is already tested. Ordered by value.

---

## 1. Historical-regression check — ★ DONE (`test/equivalence_regression_test.exs`, 8 rules)

**Plan reference:** `docs/07` §Verification, bullet "Historical regression check".

**Why it matters.** Everything verified so far shows the suite is *green*
(known-good fixes pass) and that the meta-gate catches a *missing file*. It does
**not** yet show the suite is *sharp* — i.e. that the curated input sets actually
**catch a behaviour-changing fix**. Without this, we have no evidence the suite
would have stopped the historically-rejected fixes; an input set that never witnesses
a divergence is indistinguishable from a stub that happens to pass.

**Goal.** For **≥ 5** rules that were proven unsafe and rejected, reconstruct the
*original rejected fix* (before → broken-after) and assert that the harness
**fails** (produces a witness input). This proves the input set reproduces the
documented divergence — i.e. the suite would have caught each.

**Corpus (sister-repo bookkeeping, present in this tree under `maintainer_tools/`):**
- `maintainer_tools/unfixable_confirmed.md` — rules an agent tried to fix and
  proved have no safe, behaviour-preserving fix for any shape. Each entry:
  `## <rule> — <date>`, a `Files:` list, and a one-line `Reason:` describing the
  divergence (e.g. "value-type change on every input", "int-cmp predicate flips
  the answer", "multibyte crash → value"). **Start here** — these are the richest,
  freshly-proven findings.
- `maintainer_tools/followup.md` — rules flagged for follow-up.
- `maintainer_tools/stage3_unfixable.md`, `maintainer_tools/unfixable_unreviewed.md`
  — broader/auto-classified pools (lower-quality reasons; use only if needed).

**Procedure (per chosen rule):**
1. Read the `Reason:` line — it states the divergence class and usually an example
   shape. The rule's `.ex`/test files listed under `Files:` are typically **gone**
   from `lib/` (rejected), so you reconstruct, you don't run the rule.
2. Hand-construct a `before` snippet (the flagged shape) and the `after` snippet
   (the *rejected* fix the reason describes).
3. Write the comparison **without** going through the rule (the rule may not exist):
   evaluate `before` and `after` over an input set that includes the witness the
   reason names (e.g. an ASCII string for a grapheme↔codepoint value-type change;
   a multibyte string; an equal-key tuple for a sort; a `0`/`0.0` value-kind case).
   Use the same outcome tagging as the harness (`{:ok, v}` / `{:raise, mod}`) and
   assert they **differ** (`refute outcome_o === outcome_n`), capturing the witness.
4. Confirm the witness matches the documented reason.

**Where to put it.** A dedicated `test/equivalence_regression_test.exs` (NOT under
`test/pattern/`, so the meta-gate doesn't expect a matching rule). Each test is
self-contained: it shows the rejected fix diverges on a concrete input. Title each
after the source rule + the divergence class. Add a moduledoc pointing back to
`maintainer_tools/unfixable_confirmed.md`.

**Candidate starting set (verify reasons against the file before using):**
`avoid_charlist_for_iteration` (codepoint-int vs grapheme-string, ASCII witness),
`avoid_graphemes_for_byte_iteration` (value-type + multibyte crash→value),
`no_body_destructure_of_param`, plus two more with crisp single-input witnesses.

**Acceptance:** ≥ 5 regression tests, each producing a concrete witness on the
*rejected* fix, green (they assert divergence, so "green" = "divergence reproduced").
Note in `docs/07` §Verification that the historical check is satisfied, listing the
rules covered.

**Caveat:** if any chosen rule's rejected fix turns out **not** to diverge on a
constructible input (the reason was wrong / over-cautious), that itself is a finding
— record it; do not force a fake witness. Pick another rule to reach 5.

---

## 2. PROBE-rule methodology — ★ DONE (Decision A ratified in docs/07 §Decisions #6 + PROBE section)

**Plan reference:** `docs/07` Decision #6 + §"PROBE ⚑ rules (26)".

**The situation.** The plan classifies **26** rules as PROBE and says they use
`probe_effects` / `assert_effect_trace_equivalent` to verify *eval-order and
call-count* of the user fn the rule moves through a transform hole. In practice
only **1** rule — `use_map_join` — uses `assert_effect_trace_equivalent`. The other
**25** were covered with ordinary **value tests** (`assert_equivalent` /
`assert_equivalent_module`), on the argument that each preserves eval order *by
construction* (the predicate/mapper is applied once per element, in order; or the
rule short-circuits identically). That argument was checked case-by-case during
backfill but is not encoded as an effect-trace assertion.

The 26 PROBE-classified rules (from `docs/07`):
`no_anon_fn_application_in_pipe, no_case_destructure_in_pipe,
no_eager_with_index_in_reduce, no_explicit_max_reduce*, no_explicit_min_reduce*,
no_explicit_product_reduce, no_explicit_sum_reduce, no_filter_then_count,
no_filter_then_first, no_find_value_default_case, no_group_by_for_frequencies,
no_if_empty_for_enum_min_max, no_list_append_in_reduce,
no_manual_count_with_predicate, no_manual_find, no_manual_list_reduce,
no_map_keys_enum_lookup, no_map_keys_or_values_for_iteration, no_map_then_aggregate,
no_reduce_for_group_by, no_reduce_for_map_building, no_string_concat_in_loop,
no_take_while_length_check, no_zip_then_map, prefer_map_put_new, use_map_join`.
(*`no_explicit_max_reduce`/`min_reduce` were since **dropped**; exclude them.)

**Decision to make (pick one):**
- **(A) Ratify value-tests-where-order-is-provably-preserved.** Update `docs/07`
  Decision #6 and the PROBE section to state: the effect-trace mode is a *tool*
  used where a rule could plausibly reorder/duplicate/drop the user fn; rules that
  apply the fn exactly once per element in source order are covered by value
  equivalence, which subsumes the trace. Keep `use_map_join` as the worked
  effect-trace exemplar. Cheapest; arguably already correct.
- **(B) Wire `probe_effects` through the remaining ~24 rules.** For each, rewrite
  the firing expression with the transform hole expressed as `effect.(x)` and call
  `assert_effect_trace_equivalent` so order+count are asserted, not just the value.
  Stronger, mechanical, but ~24 test rewrites and several rules carry no externally
  visible fn to instrument (e.g. `no_string_concat_in_loop`, `no_reduce_for_map_building`)
  — those would stay value-only regardless, so (B) is partial.

**Recommendation:** (A), with a short rationale per rule class in `docs/07`. If (B),
do it as its own pass and keep the value test alongside.

**Acceptance:** `docs/07` Decision #6 and the PROBE section reflect the chosen
reality; no rule is silently mis-described as effect-trace-tested when it is
value-tested.

---

## 3. Anti-stub checks — ★ DONE (`test/behaviour_equivalence_self_test.exs`, 3 safety checks + control)

**Plan reference:** `docs/07` §Verification, bullet "Anti-stub".

**State.** The checks are **coded** in `assert_equivalent/2`
(`test/support/behaviour_equivalence.ex`): it asserts the rule *fires*
(line ~223), that a *rewrite happened* (line ~229), and that
`length(inputs) >= @min_inputs` (`@min_inputs 3`, line ~232; overridable
with `allow_few_inputs: true`). The **meta-gate** checks were verified this session
(hiding a file fails it). The **assert_equivalent** anti-stub checks were *not*
re-demonstrated with a deliberately-bad test.

**Do:** add a small self-test (e.g. `test/support/behaviour_equivalence_self_test.exs`)
that asserts, via `assert_raise ExUnit.AssertionError`, that:
- a 2-input input set (< `@min_inputs`) without `allow_few_inputs` raises;
- a rule + snippet where the rule does **not** fire raises;
- a snippet the rule leaves unchanged raises.

Keep it tiny; it documents the floor and protects it from regressing. (These are
self-tests of the harness, not rule coverage, so they live outside `test/pattern/`.)

**Acceptance:** the three negative cases pass (raise as expected); `docs/07`
§Verification "Anti-stub" bullet marked done.

---

## 4. Close the open "Unresolved questions" in docs/07 — LOW (bookkeeping)

`docs/07` §"Unresolved questions" — resolve in the doc:
- **Q1 (T2 callable synthesis):** RESOLVED in practice — T2 rules were hand-wrapped
  into minimal callable `defmodule`s in their equivalence tests (option (a)). Mark
  it so.
- **Q2 (input set↔tier defaults):** MOOT — input sets were authored by hand per rule;
  no scaffold auto-attach. Mark resolved/moot.
- **Q3 (`redundant_list_guard`):** already marked RESOLVED.
- **Q4 (divergence-worklist home):** decide + record. De-facto answer: divergences
  were tracked in **this repo's `docs/07`** §"Confirmed divergences" (not in
  `maintainer_tools/`). Ratify that.
- **Q5 (doc-observation rules):** RESOLVED — `no_trailing_newline_in_doc` /
  `prefer_heredoc_for_multi_line_doc` were classified **T3a cosmetic**
  (`mark_equivalence_cosmetic`), not T2-doc. Mark it so.

**Acceptance:** §"Unresolved questions" has no genuinely-open item (each is
RESOLVED / MOOT with a one-line outcome).

---

## 5. Optional future enhancement (explicitly out of current scope)

- **StreamData layer** — additive, fixed-seed, **non-gating** property-based inputs
  on top of the curated input sets (`docs/07` final bullet). Only worth doing after
  1–4; it widens witness-finding but must never gate `main`.

---

### Suggested order
1 (historical regression — the real confidence gap) → 3 (anti-stub self-test, quick)
→ 2 (PROBE decision + doc update) → 4 (close questions) → 5 (optional, later).
