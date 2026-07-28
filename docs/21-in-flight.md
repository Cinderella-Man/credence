# 21 — In-flight ledger

**Purpose:** the answer to "what was being worked on when the session died?"
Per docs/16 Appendix B (*ledgers over memory*), work that is started but not
committed is recorded **here**, in the repo, not in a session's head. Update it
when a batch is launched and when it lands. Delete rows once they are committed.

---

## Incident 2026-07-28 10:36 — OOM, VSCode killed, 8 agents lost

**What happened.** A batch of **eight** concurrent implementation agents was
launched at 10:25 local (`phases-6-8-batch-2`, run `wf_b3251a89-a7a`). Each was
compiling and running Elixir probes in or beside the same tree; one of them
(C18) additionally made a **full clone of the repo and ran a suite in it**. At
10:36 the box ran out of memory: `erl_crash.dump` in the repo root and a second
one in that clone, the editor was killed, and the workflow died `status: killed`
with `result: null` after **17 minutes and 1.2 M tokens**. No agent ever
returned a value, so nothing was integrated.

**Why it was avoidable.** Nothing about eight was necessary. This box has 24
schedulers and ~12 physical cores; the corpus suite alone takes 983 % CPU
(docs/16 Phase 3). Concurrency limit going forward: **3–4 agents, and never two
that compile Elixir in the same tree at once.**

**Recovered.** All eight scratchpads and all eight agent transcripts were copied
out of `/tmp` before it was cleaned:

```
/home/kamil/projects/credence-salvage-2026-07-28/
    b2-<item>/            per-agent working files (the deliverables)
    _agent_transcripts/   agent-*.jsonl — full reasoning, 8 files, ~4 MB
```

This is the second time this program has nearly lost work to a scratchpad
(docs/15 gotcha 7). **A scratchpad is not storage** — the salvage directory is
not either. Anything worth keeping gets committed.

### Safe as of the crash — committed and pushed

`credence` on `evolution_accepted` is clean and pushed through `c338c67`:

| commit | item |
|---|---|
| `7fc6cc0` | C5 (6.1) — surface the silent patch-drop path |
| `5dc7cca` | C2.1 (6.2) — four missing equivalence-battery dimensions |
| `f4d08a8` | Phase 5 — escalation ledger + phantom `redefining module` fix |
| `9d70bab` | C6 (6.2) — per-rule crash isolation |
| `b6c3134` | C17 (6.7) — Rule Standard v1, stratification audit, `STATUS.md` |
| `f98c88d` | C4 (6.3) — semantic per-pass compile-revert with culprit attribution |
| `636468d` | C3 (6.3) — the Syntax round's two guards |
| `3ef1b87` | C2.2 (6.2) — dimension-mapping gate + the live bug it found |
| `6bd2b05` | P3 + P4 (7) — rule-scoped corpus scans + the analysis cache |
| `c338c67` | C8 (6.4) — rule ordering policy (docs/20) |

`credence-evolution-harness` on `main` has `P5+H13` (`96865e7`), `H12`
(`60ce2c4`) pushed, and **three commits unpushed**: `6f776fe` (H14 push-failure
breaker), `9cffbba` (H15 dead Python-translation sweep), `fb3bc2a` (H9 + LD2).
**Push those before anything else touches the harness.**

### Lost as return values, recoverable from the salvage

Six of the eight were close to done — several were writing their *positive
controls*, i.e. the last step — when they were killed. None of their work is in
either repo.

| item | repo | how far it got | salvage artifacts |
|---|---|---|---|
| ~~**C13** whitelist budget gate~~ | credence | **✅ LANDED 2026-07-28** — salvage verified and integrated; see below | — |
| **H8** verdict memory + positive exemplars | harness | 42 tests passing, writing the mutation positive controls | `b2-h8/verdicts.ex`, `classify.ex`, `prompt.ex` (35 K), `verdict_memory_test.exs`, `ctl1–ctl6/` |
| **Gate staged-path dispatch** (Addendum 2 / 8.7) | harness | Gate integration test against a stub `mix` | `b2-gatedispatch/corpus_dispatch.ex`, `corpus_dispatch_test.exs`, `gate_corpus_dispatch_test.exs`, `gate.ex.REFERENCE_ONLY` |
| **LD3 + LD4** test-only-diff policy + known-good list | harness | five modules written, no summary | `b2-ld34/test_only_diff.ex`, `verified_good.ex`, `row_log.ex`, `trace_evidence.ex`, `classify.ex`, `prompt.ex` |
| ~~**C14** DSL-safety static scan~~ | credence | **✅ LANDED 2026-07-28** — salvaged scanner verified, corrected and gated; see below | — |
| **P5 bugs** (3 credence defects from the ledger) | credence | mid-fix on `no_bare_names_in_spec`; found `heredoc_value/1` returns raw source bytes, which changes the fix | `b2-p5bugs/no_bare_names_in_spec.ex`, `probe90*.exs`, `probe134*.exs` |
| **C18** semantic-mutant sweep | credence | early — had just cloned the repo (this is the agent that OOMed) | `b2-c18/mutation.ex`, `sweep.ex`, `credence.mutants.ex` |
| **C7** idempotency gate | credence | earliest — reading docs, one fixture sweep | `b2-c7/fixtures.bin`, `sweep.exs` |

**Treat every salvaged artifact as unverified.** It was written by an agent that
never got to state its own verdict, and in at least one case (P5 bugs) the agent
had just discovered its approach was wrong. Re-derive the claim before trusting
the code.

---

### Salvage recovery log

**C13 — landed.** The salvaged implementation was verified rather than trusted,
and it held up:

- `mix credence.corpus --update-budget` regenerated `accepted_findings_budget.txt`
  **byte-identical** to the agent's copy, so its numbers were reproducible, not
  asserted.
- Its central empirical claim was re-measured independently and is real: the
  distribution has a genuine gap at the cap — the 15th-largest rule holds **122**
  accepted findings and the 16th holds **99**, so a cap of 100 grandfathers
  exactly the 15 rules carrying 74% of the debt and leaves the other 72 firing
  rules compliant with no slack.
- Its load-bearing design decision was checked against the harness rather than
  taken on faith: `--update-snapshot` deliberately does **not** write the budget
  file, because `Cev.Evolve.Corpus.delta/1` uses `--update-snapshot` as a
  read-only probe that saves and restores *only* the snapshot path
  (`lib/cev/evolve/corpus.ex:56-71`). A second file written behind its back
  would be left dirty in the clone and would redden the Gate on the next row.
  Confirmed correct.
- Positive controls: five perturbations plus an unperturbed **GREEN-0** control
  (a runner that reddens everything proves nothing). Each of the five trips
  exactly the invariant it attacks, GREEN-0 passes.

Two documentation defects fell out of doing it, both of the same shape — an audit
row *quoted* rather than measured:

1. **docs/19 row C was wrong.** It read *6,155 accepted findings across 90 rules*
   and was labelled measured 2026-07-28; those are docs/12's figures from
   2026-07-11. The snapshot holds **6,366 across 87 rules** — the row was wrong in
   both directions at once. Corrected, and now backed by a gated file.
2. **docs/19 requirement 4 was listed ungated** although C2.2's
   `equivalence_dimension_meta_test` had landed 80 minutes before docs/19 was
   written. Corrected.

**C14 — landed.** The salvage here was a working scanner and a raw 155-rule
classification, but **no gate test**, and the by-hand cross-check C14's spec
explicitly requires had not happened. Doing that cross-check is what earned its
keep:

- The scanner reproduced its own classification exactly (155 rules; 45
  `:possibly_unsafe`), so it was deterministic.
- But **five of the 45 were false positives of one class**: a matcher for
  `&fun/arity` whose capture `/` was read as division. The scan exempted only a
  *literal integer* arity, so `&fun/arity` with the arity bound to a pattern
  variable — the ordinary way to write it — was flagged, as was Sourceror's
  `{:__block__, _, [1]}` arity wrapper and its meta-elided `{:&, [spec]}` pair.
  Fixed by handling the capture node itself rather than the `/` in isolation:
  once the enclosing `&` is out of view, `{name, meta, ctx}` is indistinguishable
  from a divisor. **45 → 40.**
- The 40 are frozen in the gate's `@unclassified` ledger, split by evidence
  strength: 17 touch a construct `DslGuard` attributes to a real family, 23 are
  flagged only on unattributed constructs. Recording that split matters — a flat
  40 implies 40 equal risks.
- The gate also closes the loop the audit row missed: **101 of the 141
  "unclassified" rules cannot be affected by this class at all.** The work is 40
  rules, not 141.
- Positive controls: GREEN-0 plus four perturbations. The first attempt reddened
  on the *wrong* invariant — a fabricated extra rule file made the rule count
  mismatch, so the vacuity check fired and the gate itself was never exercised.
  Rewritten to the realistic scenario (an existing rule's fix starts building a
  construct), it now trips the intended invariant.
- `mix credence.gen.rule` now emits a deliberate `unsafe_in_dsl/0`, **verified by
  scanning the generator's own output** — a freshly scaffolded rule classifies as
  `:declared`.

### The PRODUCING bar is now met

`STATUS.md` set it as requirements 4, 5 and 8 wired into the meta-gates, the
generator and the harness seed. All three legs are in place (the harness seed
already taught self-classification, `lib/cev/implement/seed.ex:244`).

**The mode file is deliberately still `CATCHING UP`.** `mix cev.preflight` refuses
to start a generation run while it says so, and that interlock should come out on
purpose rather than as a side effect of the last gate landing. It is the
maintainer's call.

---

## Currently in flight

*(nothing — update this section when a batch is launched)*

**Next, in order** (one at a time, per the concurrency limit above):

1. **P5 bugs** — the three credence defects from the escalation ledger. Salvage is
   the least trustworthy of the batch: the agent had just found that
   `heredoc_value/1` returns raw source bytes, which changed its fix.
2. **The harness trio** (H8, LD3+LD4, Gate staged-path dispatch) — all three
   rewrite the same classifier `prompt.ex`/`classify.ex`, so they need a merge
   decision, not three parallel integrations. Push the harness's three unpushed
   commits first.
3. **C7** and **C18** — the two that barely started. Their salvage is scaffolding,
   not an implementation; treat it as a head start on reading, not as code.

Also open, and now unblocked by C14's gate: the **sweep over the 40 ledgered
rules** (docs/19 §2 row B). It runs behind a ratchet now, so it can be done in
batches without the set refilling behind it.
