# 19 — Rule Standard v1, and the stratification it has to catch up on

**Status:** v1, adopted 2026-07-28 · **Implements:** docs/12 C17
**Companions:** `STATUS.md` (which mode the repo is in right now)

Credence's rule set is **era-stratified**. Every past quality upgrade was
applied unevenly, and until this document nothing recorded which bar a given
rule was accepted under. Measured today, by the month each Pattern rule file
first appeared:

| era | rules | what shipped with them |
|---|---|---|
| 2026-05 | 60 | the original set — before DSL-safety, before the equivalence backfill |
| 2026-06 | 87 | the two evolution bursts |
| 2026-07 | 9 | the acceptance drain (Phase 4) |

The DSL-safety guard was retrofitted **two months** after the rules it protects
shipped (PR #20). The equivalence backfill was a one-off campaign (docs/07). The
corpus whitelist has been accumulating debt since the beginning (C13). Each of
those was a *sweep*, and a sweep is what you do when the standard arrived after
the rules did.

The point of a versioned standard is to stop doing that.

---

## 1. Rule Standard v1

A rule is **v1-compliant** when all of the following hold. Items marked *gated*
are enforced by a meta-test today; the rest are the catch-up work in §2.

| # | Requirement | Status |
|---|---|---|
| 1 | **Test triplet present** — `_check_test`, `_fix_test` (or a combined file), and for Pattern rules an `_equivalence_test` | *gated* (`check_meta_test`, `fix_meta_test`, `equivalence_meta_test`, `rule_test_completeness_test`) |
| 2 | **The rule actually does something** — `check` asserted in both directions; a real `fix` whose output differs from its input; the output parses | *gated* (`semantic_meta_test`, `syntax_meta_test`, `fix_meta_test`) |
| 3 | **No parser calls in rule tests** — everything routes through `Credence.RuleCase` | *gated* (`no_parser_calls_in_rule_tests_test`) |
| 4 | **Equivalence dimensions mapped to the rule's operation class** — a rule that rewrites `Keyword.get/2` must be tested against `keyword_lists`, not only `term_lists` | *gated* 2026-07-28 (`equivalence_dimension_meta_test`, C2.2) — §2 row A |
| 5 | **DSL-safety classified** — `unsafe_in_dsl/0` declared deliberately, even if the answer is `[]` | *gated* 2026-07-28 (`dsl_static_scan_test`, C14) — §2 row B |
| 6 | **Message and moduledoc follow the template** | **not gated** (C15) |
| 7 | **Alpha-rename generality** — the rule fires on the construct, not on a variable name | **not gated** (C12) |
| 8 | **Within the accepted-corpus-findings budget** | *gated* 2026-07-28 (`findings_budget_test`, C13) — §2 row C |
| 9 | **Semantic-mutant kill rate above the floor** | **not measured** (C18) — report-only first |

Items 1–3 are why the suite is 8,261 tests.

**Three of items 4–9 have since been gated** — 4 by C2.2, 5 by C14, 8 by C13 —
each with its positive controls seen red on purpose. That is what §3 said had to
happen first: the gates go in before the retrofit sweep, so the sweep runs behind
a ratchet instead of racing one. Items 6, 7 and 9 remain open.

**Those three are exactly the bar `STATUS.md` sets for `PRODUCING`**, and all
three legs of it are now in place: the meta-gates (above), `mix credence.gen.rule`
(which emits a deliberate `unsafe_in_dsl/0`), and the harness seed (which already
taught new rules to self-classify — `lib/cev/implement/seed.ex:244`). Flipping the
mode is therefore a decision about *when*, not about whether the bar is met.

---

## 2. The stratification audit

One row per out-of-line population. **This table is the catch-up plan** — most
of C11–C15 are rows in it. All figures measured 2026-07-28 against 155 Pattern,
90 Semantic, 45 Syntax rules.

### Row A — equivalence tests that name no dimension: **129 of 155 (83%)**

```
term_lists 17 · unicode_strings 7 · maps 4 · tuples 3 · single_codepoint_strings 2
signed_integers 1 · multi_codepoint_strings 1 · stability_lists 1
keyword_lists 0 · mixed_numeric 0
```

The `keyword_lists` and `mixed_numeric` zeros are expected — both landed on
2026-07-27 (C2.1). The 129 are not. A rule whose equivalence test names no
dimension is testing against whatever its author hand-wrote, which may or may
not contain the shape its fix is risky on. docs/14 E1 is the cautionary case:
`term_lists`' only mixed-kind entry tied at the *minimum*, so first-vs-last
divergences were invisible and **two live bugs shipped through a green
equivalence suite**.

*Cost to fix:* C2.2's mapping gate has to land first, and it must be
conservative — 129 newly-red rules is not a gate, it is a wall. Expect the first
version to flag a handful.

### Row B — Pattern rules never DSL-classified: 141 of 155, of which **40 matter**

13 rules declare `unsafe_in_dsl/0` (a 14th hit is `lib/pattern/rule.ex`, the
behaviour itself). The other 141 inherit the `[]` default, which means "safe
inside every macro DSL" — a claim nobody made deliberately. The distinction that
matters: a rule that has *considered* Ash/Ecto/Nx and concluded `[]` is
compliant; a rule that never considered them is unclassified and looks identical.

**Measured 2026-07-28 by C14's static scan**, which is what turns 141 into an
actionable number. Of the 155 Pattern rules:

| bucket | n | meaning |
|---|---|---|
| `:declared` | 13 | source contains an explicit `def unsafe_in_dsl` |
| `:verified_safe` | 35 | on `@verified_dsl_safe` with a written reason |
| `:anchored` | 3 | every matcher clause keyed on a form no DSL expression admits |
| `:no_construct` | 64 | the fix touches no reinterpreted construct at all |
| **`:possibly_unsafe`** | **40** | **the real debt** |

So 101 of the 141 "unclassified" rules cannot be affected by this class at all —
they either touch no reinterpreted construct or are anchored where a DSL
expression cannot reach. The work is 40 rules, not 141, and it stratifies again:
**17 touch a construct `DslGuard` attributes to a named family** (Ash.Expr,
Ecto.Query or Nx.Defn) and are the paydown order; the other 23 are flagged only
on constructs in the union oracle that no family reinterprets, which is weaker
evidence and is recorded as such rather than counted as equal risk.

Five rules came off the first shortlist as false positives, all one class: a
matcher for `&fun/arity` where the capture's `/` was read as division. The scan
exempted only a literal integer arity, so `&fun/arity` with the arity bound to a
pattern variable — the ordinary way to write it — was flagged. Worth recording
because it is the shape a static scan gets wrong: `{name, meta, ctx}` is
indistinguishable from a divisor once the enclosing `&` is out of view.

*Cost to fix:* **the gate is landed** (`test/dsl_static_scan_test.exs`), the 40
are frozen in its `@unclassified` ledger, and `mix credence.gen.rule` now emits a
deliberate `unsafe_in_dsl/0` so a newly generated rule is classified by
construction. **Requirement 5 of §1 is now gated.** The remaining work is the
sweep over those 40, which now runs behind a ratchet instead of racing one — the
ledger only shrinks. The sweep tool gets deleted afterwards (§3).

### Row C — corpus-findings debt: **6,366 accepted findings across 87 rules**

> **Corrected 2026-07-28.** This row first read *6,155 across 90 rules* with a
> per-rule top five to match. Those were docs/12's figures from 2026-07-11,
> carried over rather than re-measured, so the row was wrong in both directions
> at once — fewer findings and more rules than the snapshot actually holds. The
> numbers below come from `Credence.Corpus.Budget.counts/1` over the committed
> snapshot, and unlike the first set they are now **gated**, so they cannot
> quietly drift again.

Concentrated, not diffuse — and counted **with `(xN)` multiplicity**, because a
rule firing three times on one source line is three suppressed fix sites:

```
prefer_heredoc_for_multi_line_doc  1,298   (20% of the whole whitelist)
no_case_true_false                   521
prefer_map_new                       504
prefer_function_capture              337
prefer_guard_over_if                 249
```

15 rules exceed the cap of 100 and hold **4,734 findings — 74% of the debt**.
The other 72 firing rules are already compliant, as are the 68 Pattern rules
that fire zero times. The distribution has its own knee at the cap: the 15th
rule holds 122, the 16th holds 99.

docs/16 already names `prefer_heredoc_for_multi_line_doc` as the first paydown
target and flags `prefer_erlang_float` (37 gold findings on hand-written code)
as a taste-rule candidate for the C13 budget review.

*Cost to fix:* C13 says budget gate first, evidence-ranked paydown second. Do
not invert that — paying down without a gate just refills.

**Gate landed 2026-07-28** (C13(a) + (c)): `test/corpus/accepted_findings_budget.txt`
publishes the per-rule counts, `test/corpus/findings_budget_test.exs` freezes the
cap and the grandfather ledger, and `mix credence.corpus --budget` prints the
ranking — which is also the paydown order. Neither the file nor the gate needs
the corpus, so both run under `mix test --exclude corpus`. **Requirement 8 of §1
is now gated**; the paydown (C13(b)) is the part still open.

### Row D — the three trace states nothing consumes yet

Landed 2026-07-27/28: `{rule, :reverted}` (pre-existing), `{rule,
:patch_rejected}` (C5), `{rule, :crashed}` (C6). All three name a rule that
reported findings it did not fix. Nothing downstream reads them yet — the
harness's bugfix lane is the intended consumer (H1's sibling).

*Cost to fix:* harness-side, Phase 8.

### Row E — semantic-mutant kill rate: **unmeasured**

C18 prescribes report-only first, published per-rule kill rates second, fix the
tail third, and only then a floor gate. Nothing has been measured, so there is
no tail to fix yet and no floor to set.

---

## 3. Raising the bar is a named round, in this order

The ordering is the whole mechanism, and it is what prevents the next
PR-#20-style retrofit:

1. **Wire the new check in first** — `mix credence.gen.rule`, the meta-gates,
   and the harness rule-generation seed. From that moment every *new* rule meets
   the bar without anyone remembering to check.
2. **Then** sweep the existing rules, with its own ledger.
3. Verify the whole set.
4. **Delete the sweep tool.** A sweep tool that survives becomes a way to keep
   shipping non-compliant rules and fixing them later, which is the habit being
   broken.
5. Record the round below.

### Round history

| round | standard | landed | scope |
|---|---|---|---|
| — | (pre-standard) | 2026-05 → 2026-07 | 60 + 87 + 9 rules, three eras, no recorded bar |
| v1 | this document | 2026-07-28 | standard written; items 1–3 already gated, 4–9 audited in §2 |

---

## 4. Mode file

`STATUS.md` at the repo root records whether the credence/harness pair is
**PRODUCING** rules or **CATCHING UP** on a standard bump. The dataset project's
experience — the source of this whole mechanism — is that this one file is what
stops half-applied upgrades from accumulating silently, because it makes the
answer to "can I generate rules right now?" a fact rather than a judgement call.

It is shared with the harness: `mix cev.preflight` should refuse to start a
generation run while the mode is CATCHING UP, so a standard bump cannot be
outrun by new rules born under the old bar.

---

## 5. What this document does not claim

It is v1 and it is mostly aspiration: **six of the nine requirements are
ungated**, and §2 measures how far the existing set is from three of them. The
value here is not the checklist — anyone can write a checklist — it is the audit
table, because that is the part that says how much work the checklist implies
and where it actually is.

The one thing to resist: treating a green suite as evidence of compliance. The
suite gates items 1–3. A rule can satisfy all of them and still be untested
against the shape its fix breaks on, unclassified for DSL safety, over the
findings budget, and never mutation-tested.
