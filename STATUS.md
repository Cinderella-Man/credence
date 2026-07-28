# STATUS

The mode file (docs/19 §4). One question: **can rules be generated right now?**

```
MODE: CATCHING UP
```

Shared with `credence-evolution-harness`. `mix cev.preflight` refuses to start a
generation run while the mode is `CATCHING UP`, so a standard bump cannot be
outrun by new rules born under the old bar.

> ✅ **The interlock is implemented** (docs/22 **T4.1**, harness `24f2dee`).
> `Cev.Preflight` reads this file through `Cev.Status` and halts the run while
> the mode is anything other than `PRODUCING`. It reads the **accepting** repo's
> copy — `CEV_ACCEPTING_REPO` / `:accepting_repo`, falling back to the Gate's
> clone — because the clone sits on `evolution` and its copy can trail this one
> by a whole standard revision.
>
> Note the polarity: `PRODUCING` permits, and *everything else* blocks. A typo
> here does not accidentally open the gate.

## Why CATCHING UP

Rule Standard v1 was written on 2026-07-28 (`docs/19-rule-standard.md`). Its
stratification audit in §2 measured how far the existing set sits from three of
its nine requirements — and **two of the three gates now exist**:

| audit row | measured | gate |
|---|---|---|
| C2.2 — equivalence dimensions | **129 of 155** Pattern equivalence tests named no operation-mapped dimension | **gated** 2026-07-28 (`equivalence_dimension_meta_test`) |
| C13 — corpus-findings debt | **6,366** accepted findings across 87 rules, 20% from one rule, 74% from fifteen | **gated** 2026-07-28 (`findings_budget_test` + `accepted_findings_budget.txt`) |
| C14 — DSL safety | 141 of 155 Pattern rules were never DSL-classified — but the scan shows only **40** touch a reinterpreted construct at all | **gated** 2026-07-28 (`dsl_static_scan_test`) |

(The C13 row originally read *6,155 across 90 rules*. That figure came from
docs/12's 2026-07-11 audit rather than from the snapshot; the corrected count is
now published in a committed, gated file and cannot drift again.)

**All three gates now exist**, so the condition below is satisfied — see "What
flips it to PRODUCING". The mode is still `CATCHING UP` because flipping it is a
deliberate act by the maintainer, not a side effect of the last gate landing:
`mix cev.preflight` refuses to start a generation run while this file says
`CATCHING UP`, and that interlock should be removed on purpose or not at all.

## What flips it to PRODUCING

Not all nine requirements — that would be a standard nobody can ever meet. The
bar for PRODUCING is that a **newly generated rule cannot make the audit worse**,
i.e. requirements 4, 5 and 8 are wired into `mix credence.gen.rule`, the
meta-gates, and the harness seed. The retrofit sweep over existing rules can
then run behind the gate rather than racing it (docs/19 §3, and the ordering
there is the whole mechanism).

**All three legs are in place as of 2026-07-28:**

| leg | 4 (C2.2) | 5 (C14) | 8 (C13) |
|---|---|---|---|
| meta-gate | `equivalence_dimension_meta_test` | `dsl_static_scan_test` | `findings_budget_test` |
| `mix credence.gen.rule` | n/a — a fresh scaffold has no order-sensitive call to map | emits a deliberate `unsafe_in_dsl/0` (verified: a generated rule scans as `:declared`) | n/a — a new rule has zero corpus findings |
| harness seed | — | already taught self-classification (`lib/cev/implement/seed.ex:244`) | — |

Each gate has had its positive controls seen red on purpose, per the docs/12
amendment. **The bar is met; the flip is the maintainer's call.** Note that Phase
9 is separately blocked on the PR to `main`, Mimo secrets, a local solve endpoint
and a spend decision (docs/16 §START HERE), so flipping this file does not by
itself start anything.

Remaining work of every kind is tracked in **`docs/22-remaining-work.md`** —
the single tracker.

## History

| date | mode | why |
|---|---|---|
| 2026-07-28 | CATCHING UP | requirements 4, 5 and 8 all gated — the PRODUCING bar is met, awaiting a deliberate flip |
| 2026-07-28 | CATCHING UP | requirements 4 (C2.2) and 8 (C13) gated; 5 (C14) still open — that one gates the flip |
| 2026-07-28 | CATCHING UP | Rule Standard v1 adopted; items 4–9 ungated, audit in docs/19 §2 |
| 2026-07-27 | (implicit PRODUCING) | Phase 4 acceptance drain — 116 rules accepted, 143 rejected |
