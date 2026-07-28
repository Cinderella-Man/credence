# STATUS

The mode file (docs/19 §4). One question: **can rules be generated right now?**

```
MODE: CATCHING UP
```

Shared with `credence-evolution-harness`. `mix cev.preflight` should refuse to
start a generation run while the mode is `CATCHING UP`, so a standard bump
cannot be outrun by new rules born under the old bar.

## Why CATCHING UP

Rule Standard v1 was written on 2026-07-28 (`docs/19-rule-standard.md`). Six of
its nine requirements are not gated yet, and the stratification audit in §2
measures how far the existing set is from three of them:

- **129 of 155** Pattern equivalence tests name no operation-mapped dimension (C2.2)
- **141 of 155** Pattern rules were never DSL-classified (C14)
- **6,155** accepted corpus findings across 90 rules, 21% of them from one rule (C13)

Generating more rules before those gates exist adds to every one of those
numbers. The point of the mode file is that this is a stated position rather
than something each person re-decides.

## What flips it to PRODUCING

Not all nine requirements — that would be a standard nobody can ever meet. The
bar for PRODUCING is that a **newly generated rule cannot make the audit worse**,
i.e. requirements 4, 5 and 8 are wired into `mix credence.gen.rule`, the
meta-gates, and the harness seed. The retrofit sweep over existing rules can
then run behind the gate rather than racing it (docs/19 §3, and the ordering
there is the whole mechanism).

## History

| date | mode | why |
|---|---|---|
| 2026-07-28 | CATCHING UP | Rule Standard v1 adopted; items 4–9 ungated, audit in docs/19 §2 |
| 2026-07-27 | (implicit PRODUCING) | Phase 4 acceptance drain — 116 rules accepted, 143 rejected |
