# STATUS

The mode file (docs/19 §4). One question: **can rules be generated right now?**

```
MODE: CATCHING UP
```

Shared with `credence-evolution-harness`. `mix cev.preflight` should refuse to
start a generation run while the mode is `CATCHING UP`, so a standard bump
cannot be outrun by new rules born under the old bar.

## Why CATCHING UP

Rule Standard v1 was written on 2026-07-28 (`docs/19-rule-standard.md`). Its
stratification audit in §2 measured how far the existing set sits from three of
its nine requirements — and **two of the three gates now exist**:

| audit row | measured | gate |
|---|---|---|
| C2.2 — equivalence dimensions | **129 of 155** Pattern equivalence tests named no operation-mapped dimension | **gated** 2026-07-28 (`equivalence_dimension_meta_test`) |
| C13 — corpus-findings debt | **6,366** accepted findings across 87 rules, 20% from one rule, 74% from fifteen | **gated** 2026-07-28 (`findings_budget_test` + `accepted_findings_budget.txt`) |
| C14 — DSL safety | **141 of 155** Pattern rules were never DSL-classified | **not gated — this is the one left** |

(The C13 row originally read *6,155 across 90 rules*. That figure came from
docs/12's 2026-07-11 audit rather than from the snapshot; the corrected count is
now published in a committed, gated file and cannot drift again.)

Generating more rules before the last gate exists adds to that third number. The
point of the mode file is that this is a stated position rather than something
each person re-decides.

## What flips it to PRODUCING

Not all nine requirements — that would be a standard nobody can ever meet. The
bar for PRODUCING is that a **newly generated rule cannot make the audit worse**,
i.e. requirements 4, 5 and 8 are wired into `mix credence.gen.rule`, the
meta-gates, and the harness seed. The retrofit sweep over existing rules can
then run behind the gate rather than racing it (docs/19 §3, and the ordering
there is the whole mechanism).

**4 and 8 are in. 5 (C14) is the remaining blocker**, and it is the next item on
the list — so this mode file is expected to flip once C14's static scan lands and
`mix credence.gen.rule` requires an `unsafe_in_dsl/0` declaration.

## History

| date | mode | why |
|---|---|---|
| 2026-07-28 | CATCHING UP | requirements 4 (C2.2) and 8 (C13) gated; 5 (C14) still open — that one gates the flip |
| 2026-07-28 | CATCHING UP | Rule Standard v1 adopted; items 4–9 ungated, audit in docs/19 §2 |
| 2026-07-27 | (implicit PRODUCING) | Phase 4 acceptance drain — 116 rules accepted, 143 rejected |
