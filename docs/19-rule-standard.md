# 19 — Rule Standard v1, and the stratification it has to catch up on

**Status:** v1, adopted 2026-07-28 · **Implements:** docs/12 C17
**Companions:** `STATUS.md` (which mode the repo is in right now) ·
`docs/22-remaining-work.md` (the single tracker — the §2 audit rows' "cost to
fix" items are tracked THERE, not here)

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
| 2a | **No rule reports a finding that nothing repairs** — *fix or drop it*, per finding rather than per rule | *gated* 2026-08-17 (`fix_or_drop_test`), ledger opened at 24 across 9 rules and **paid to zero the same day** |
| 3 | **No parser calls in rule tests** — everything routes through `Credence.RuleCase` | *gated* (`no_parser_calls_in_rule_tests_test`) |
| 4 | **Equivalence dimensions mapped to the rule's operation class** — a rule that rewrites `Keyword.get/2` must be tested against `keyword_lists`, not only `term_lists` | *gated* 2026-07-28 (`equivalence_dimension_meta_test`, C2.2) — §2 row A |
| 5 | **DSL-safety classified** — `unsafe_in_dsl/0` declared deliberately, even if the answer is `[]` | *gated* 2026-07-28 (`dsl_static_scan_test`, C14) — §2 row B. **Ledger EMPTY 2026-08-16**: all 40 swept, so this is satisfied by every rule rather than merely ratcheted |
| 6 | **Message and moduledoc follow the template** | *partly gated* 2026-08-16 (`rule_card_test`, C15) — the **intent line** is gated for all 289 rules (274 complied, 14 ledgered) and **`## Bad`/`## Good` for Syntax**, where those examples are what makes the self-corruption oracle adversarial. The Pattern (120/157) and Semantic (6/89) example backfill is **not** gated — an 83-entry ledger is a wall, not a ratchet |
| 7 | **Alpha-rename generality** — the rule fires on the construct, not on a variable name | *gated* 2026-08-16 (`alpha_rename_test`, C12(a)) — measured **0 offenders**; C12(c), over-fitting by *shape*, is separate and still open |
| 8 | **Within the accepted-corpus-findings budget** | *gated* 2026-07-28 (`findings_budget_test`, C13) — §2 row C |
| 9 | **Semantic-mutant kill rate above the floor** | **not measured** (C18) — report-only first |

Items 1–3 are why the suite is 8,261 tests.

**Requirement 2a is new, and it is the teeth on requirement 2.** Requirement 2 asks
whether a rule fixes *something*; 2a asks whether any individual finding is reported
and left unrepaired. All 289-odd rules satisfied 2 while 24 findings across 9 rules
violated 2a — `test/no_op_trace_test.exs` made those no-ops *visible* in the trace,
which is a different claim from forbidding them, and `corpus/scope_parity_test.exs`
gated only the converse direction (where check is silent, the fix must not act).

Every one of the nine was the same structural defect: the admission decision existed
in two copies, one per callback, and they had drifted. The remedy in each case was to
delete the second copy. Two of the nine were also silent miscompilations — output
that parses, compiles, warns about nothing, and returns a different answer — which no
other gate can catch, because the safety net reverts only on non-compiling output.

**Four of items 4–9 have since been gated** — 4 by C2.2, 5 by C14 and 8 by C13
on 2026-07-28, then 7 by C12(a) on 2026-08-16 — each with its positive controls
seen red on purpose. That is what §3 said had to happen first: the gates go in
before the retrofit sweep, so the sweep runs behind a ratchet instead of racing
one. **Item 9 remains open, and item 6 is half-open** — see its row.

Requirement 7 is the one that cost nothing to satisfy: the gate measured **zero**
offenders across all Pattern rules, so it was a ratchet from the day it landed
rather than a wall. Worth noting *because* the audit predicted otherwise —
docs/12 C12 named three rules as over-fit and all three pass it. They are
over-fit by **shape**, not by name, which is C12(c) and still open.

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

*Cost to fix:* **PAID, 2026-08-16 — the ledger is empty.** All 40 were swept:
**10** declare a family they diverge in, **9** declare a deliberate `[]` in the
rule, **21** earned a `@verified_dsl_safe` reason. The three-way split matters:
the source scan and the fixture-level oracle flag different populations, so a
rule the scan flags but the fixture oracle does not is answered in the rule with
`[]` rather than by an allowlist entry the other gate then calls stale.

One declaration did not survive contact with `dsl_macro_protection_test.exs`,
which requires every flagged rule to be *shown* gated by a fixture that fires
inside an embedded block: `no_repeated_div_rem` was proposed as `[:ash_expr]`
and is `[]`, because its matcher needs a multi-statement block with a rebinding
and an Ash `expr(...)` holds one expression. Six other flagged rules needed a
bare-expression fixture added before that gate could see them at all.

The historical text follows. The gate is landed (`test/dsl_static_scan_test.exs`), the 40
were frozen in its `@unclassified` ledger, and `mix credence.gen.rule` now emits a
deliberate `unsafe_in_dsl/0` so a newly generated rule is classified by
construction. **Requirement 5 of §1 is now gated.** The remaining work is the
sweep over those 40, which now runs behind a ratchet instead of racing one — the
ledger only shrinks. The sweep tool gets deleted afterwards (§3) — **done 2026-08-16**: the paydown-ordering machinery (`shortlist/1`, `rank/1`, `pin/1`) is gone, while `scan/2`/`tally/1`/`verified_dsl_safe_names/1` stay, because those are the gate itself rather than the sweep. An empty ledger is when a ratchet is most worth keeping.

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

### Row E — semantic-mutant kill rate: **measured, floor still unset**

C18 prescribes report-only first, published per-rule kill rates second, fix the
tail third, and only then a floor gate.

**Step one is done (T2.4, `b1297c7`).** `mix credence.mutants` exists and a
39-rule sample was measured on a quiet box: **corpus kill rate 0.740**, 629
killed / 221 survived, 0 timeouts, 189 s. `no_manual_max` reproduced the
salvage's 0.848 exactly, so the engine is deterministic across machines.

It stays **report-only on purpose** — no `--fail-under`, not wired into the
suite. The 221 survivors have not been triaged, and a floor set before that is a
number nobody can defend. Triage-then-floor is tracked in `STATUS.md` (D9);
until it happens this requirement is measured but ungated.

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
| v1.1 | requirement **2a** | 2026-08-17 | *fix or drop it* gated per FINDING. Ran in §3's order: gate first (`fix_or_drop_test`, default suite), then the sweep, then verify. Ledger 24 → 0 across 9 rules. **Step 4 does not apply** — `FixOrDrop` is the gate, not a sweep tool, the same call made for `DslStaticScan`'s `scan`/`tally` |

**What v1.1 cost, since §2's value is saying how much a checklist implies.** Nine
rules, all one defect — the admission decision kept in two copies that had drifted
— so the repair was always to delete the second copy rather than synchronise them.
Twelve findings gained a repair, six were removed as unrepairable, six were removed
where a repair exists but needs a rendering fix first (both `NonGroupedClauses`
shapes; specified in the source). Corpus 6367 → 6347, deletions only.

Two of the nine were **silent miscompilations** — parsing, compiling,
warning-free output that returns a different answer. Worth recording against §5's
warning about treating a green suite as compliance: these had been green under every
gate in the repo, because `apply_or_revert` reverts on non-compiling output and
these compile.

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

It is v1 and it was mostly aspiration when written: six of the nine
requirements were ungated then. **As of 2026-08-16 three are — 6 (C15,
template), 7 (C12, alpha-rename) and 9 (C18, mutant floor)** — which is what
§1's own table has said since C2.2, C13 and C14 landed on the day this section
was written. The sentence and the table disagreed for three weeks; the table
was right. §2 measures how far the existing set is from three of them. The
value here is not the checklist — anyone can write a checklist — it is the audit
table, because that is the part that says how much work the checklist implies
and where it actually is.

The one thing to resist: treating a green suite as evidence of compliance. The
suite gates items 1–3. A rule can satisfy all of them and still be untested
against the shape its fix breaks on, unclassified for DSL safety, over the
findings budget, and never mutation-tested.
