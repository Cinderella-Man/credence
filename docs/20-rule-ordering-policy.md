# 20 — Rule ordering policy

**Status:** v1, adopted 2026-07-28 · **Implements:** docs/12 C8
**Companion:** `docs/19-rule-standard.md` (the standard this is a clause of)

## The situation, measured

`Credence.RuleHelpers.discover_rules/1` orders every phase's rules with
`Enum.sort_by(&{&1.priority(), &1})` (`lib/rule_helpers.ex:23`). Priority first,
then the module itself — which for a module atom is **alphabetical**.

Of 290 live rules, **15 declare a priority**:

| phase | priority | rules |
|---|---|---|
| pattern | 50 | `no_piped_regex_replace` |
| pattern | 499 | `no_identity_function_in_enum` |
| pattern | 501 | `no_explicit_product_reduce`, `no_explicit_sum_reduce`, `prefer_heredoc_for_multi_line_doc` |
| pattern | 510 | `no_chunk_by_identity_for_dedup` |
| pattern | 520 | `no_identity_enum_map` |
| semantic | 100 | `missing_use_exunit_case`, `no_hallucinated_task_timeout_error_struct` |
| semantic | 400 | `no_hallucinated_defpstruct`, `no_non_negated_integer`, `no_stream_data_integer_two_args` |
| semantic | 450 | `fix_reraise_keyword_in_catch`, `fix_truncated_special_form` |
| semantic | 490 | `fix_negated_capture_with_arity` |
| syntax | — | none |

**The other 275 sit at the default 500, and are therefore ordered
alphabetically by module name.** Nobody chose that. It is what falls out of the
tiebreak.

That is the whole problem C8 names, and it is worse in the Semantic round than
in Pattern, because `lib/semantic.ex` dispatches with `Enum.find` over that
sorted list — **first match wins, no fall-through**. One rule per diagnostic.
If the alphabetically-first claimant's `fix/2` no-ops, every other rule matching
that diagnostic is silently dead. docs/18 found 12 contested diagnostic slots
this way; `undefined variable "<name>"` alone was claimed by 17 rejected rules.

So in Semantic, alphabetical order is not a cosmetic default — it decides which
rule gets to run at all.

---

## The policy

### 1. A non-default priority is an assertion, and must say what it asserts

Writing `def priority, do: 400` claims *this rule must run before the ones at
500*. That claim has a reason, and the reason belongs in the rule's moduledoc,
in one sentence, naming the other rule or the construct:

```elixir
# Runs before the 500s: its fix emits `Enum.map/2`, which
# `NoIdentityEnumMap` (520) then collapses when the mapper is identity.
def priority, do: 400
```

A priority with no stated reason is indistinguishable from a typo, and the next
person cannot safely change either one.

### 2. Alphabetical order may not be load-bearing

If rule A's fix produces a construct rule B's check looks for, that is a
**feeds-into pair** and both rules get explicit priorities. It is not acceptable
to rely on `NoAbc` sorting before `NoXyz`, because:

- renaming a rule silently reorders the pipeline;
- the dependency is invisible at both call sites;
- in Semantic it does not reorder anything, it *disables* something.

### 3. In the Semantic round, one diagnostic has one owner

Two rules whose `match?/1` accept the same diagnostic are not "ordered" — the
second one does not exist. Either narrow one of them so the sets are disjoint,
or merge them into a single rule that dispatches internally on AST shape.

docs/18's reconciliation is the evidence: five separate rebuild proposals landed
on the `undefined variable` slot, and four of them were dead by construction
before anyone wrote a line.

### 4. The bands

| band | meaning |
|---|---|
| < 100 | structural — must run before anything that reads the construct it produces |
| 100–499 | runs before the default population, for a stated reason |
| **500** | **default; no ordering claim made** |
| 501–999 | runs after the default population, for a stated reason |

`no_piped_regex_replace` at 50 and `no_identity_enum_map` at 520 are the two
existing endpoints and both are genuine: the first normalises a pipe shape other
rules then read, the second collapses an `Enum.map` that earlier rules may have
just produced.

---

## What this document does not do

**It does not retrofit the 275.** Assigning priorities from a heuristic would
replace an unexamined default with an unexamined guess, and 275 mass edits is
exactly the PR-#20-shaped move docs/19 §3 exists to prevent. The honest position
is that most of those rules probably have no ordering dependency at all, and the
handful that do should be found by looking for feeds-into pairs rather than by
sweeping.

**No test pins ordering today.** Nothing in `test/` asserts a priority value or
a rule sequence, so the alphabetical tiebreak can shift under a rename with the
suite staying green. That is a gap this document records rather than closes;
closing it needs the feeds-into pairs identified first, because a gate that pins
all 290 positions would fail on every rule addition and teach people to
regenerate it without reading.

## Round history

| round | change | landed |
|---|---|---|
| v1 | policy written; 15 explicit priorities audited; 275 defaults left alone deliberately | 2026-07-28 |
