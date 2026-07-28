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
| **C13** whitelist budget gate + evidence-ranked paydown | credence | writing the positive control (the gate test run red on purpose) | `b2-c13/probe_gate.exs`, `run_red.exs`, `run_tests.exs` |
| **H8** verdict memory + positive exemplars | harness | 42 tests passing, writing the mutation positive controls | `b2-h8/verdicts.ex`, `classify.ex`, `prompt.ex` (35 K), `verdict_memory_test.exs`, `ctl1–ctl6/` |
| **Gate staged-path dispatch** (Addendum 2 / 8.7) | harness | Gate integration test against a stub `mix` | `b2-gatedispatch/corpus_dispatch.ex`, `corpus_dispatch_test.exs`, `gate_corpus_dispatch_test.exs`, `gate.ex.REFERENCE_ONLY` |
| **LD3 + LD4** test-only-diff policy + known-good list | harness | five modules written, no summary | `b2-ld34/test_only_diff.ex`, `verified_good.ex`, `row_log.ex`, `trace_evidence.ex`, `classify.ex`, `prompt.ex` |
| **C14** DSL-safety static scan (132 unclassified rules) | credence | scanner written (30 K), calibrating against a pinned expectation | `b2-c14/dsl_static_scan.ex`, `pin.txt`, `entries.txt`, `calibrate.exs` |
| **P5 bugs** (3 credence defects from the ledger) | credence | mid-fix on `no_bare_names_in_spec`; found `heredoc_value/1` returns raw source bytes, which changes the fix | `b2-p5bugs/no_bare_names_in_spec.ex`, `probe90*.exs`, `probe134*.exs` |
| **C18** semantic-mutant sweep | credence | early — had just cloned the repo (this is the agent that OOMed) | `b2-c18/mutation.ex`, `sweep.ex`, `credence.mutants.ex` |
| **C7** idempotency gate | credence | earliest — reading docs, one fixture sweep | `b2-c7/fixtures.bin`, `sweep.exs` |

**Treat every salvaged artifact as unverified.** It was written by an agent that
never got to state its own verdict, and in at least one case (P5 bugs) the agent
had just discovered its approach was wrong. Re-derive the claim before trusting
the code.

---

## Currently in flight

*(nothing — update this section when a batch is launched)*
