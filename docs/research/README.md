# Research reports (2026-07-11) — inputs to docs/12–15

These are the raw research artifacts behind the improvement proposals
(`docs/12`), the performance investigation (`docs/13`), the adversarial
scrutiny (`docs/14`), and the harness proposals
(`credence-evolution-harness/docs/IMPROVEMENTS.md`). They were produced in one
coordinated session on 2026-07-11: four autonomous research agents (Claude
Opus) worked in parallel while a coordinating session (Claude Fable) read the
quality-critical code paths first-hand, then cross-verified the agents' most
load-bearing claims by direct reading and by executing experiments
(`docs/14`).

| Report | What it covers | Verification status |
|---|---|---|
| [`credence-internals.md`](credence-internals.md) | Pipeline mechanics (all three rounds, patch application, DSL guard), rule framework contracts, QA machinery (meta-gates, equivalence harness, corpus layers, fixture healer), maintainer tools, docs/01–11 summaries + roadmap gap table, 13 pipeline weaknesses | Spot-verified; two refinements noted in header |
| [`rule-quality-audit.md`](rule-quality-audit.md) | Inventory of 146 pattern rules (priorities/assumptions/DSL flags), overlap clusters, consistency audit, git archaeology (provenance eras, 105 `followup —` rejects, 40 deletions, DSL retrofit timeline), 12-rule deep critique, syntax/semantic pass, ranked problem list | **Header contains material corrections** — two of its three headline defects were empirically refuted; one confirmed and extended. Read the header first. |
| [`prior-art.md`](prior-art.md) | Transferable techniques from Getafix/Refazer/Revisar/Piranha/Sorald (learned transformation rules), Alive2/SafeRefactor/StreamData/mutation testing (fix validation), Semgrep-Assistant/Self-Refine-limits/LLM-judge reliability (LLM rule-gen), ESLint/RuboCop/Clippy/Tricorder (rule-set hygiene at scale), ranked top-10 | Citation leads; key items consistent with known systems |
| [`../../credence-evolution-harness/docs/research/harness-internals.md`](../../../credence-evolution-harness/docs/research/harness-internals.md) | The full rule-gen spine (verbatim Classify + Implement-seed prompts, router/novelty/equiv/gate mechanics), solve/validate/workspace, orchestrator/ops, test-coverage map, ADR summaries, 18-point weakness/signal-loss map | Three most load-bearing claims re-verified directly, all confirmed |

Reading order for a newcomer: this README → the two internals reports → the
audit (with its header corrections) → `docs/12` + `docs/13` (the proposals)
→ `docs/14` (what survived scrutiny) → `docs/15` (hand-off index).

**Caution:** these reports are snapshots of 2026-07-11 code. `file:line` cites
will drift. Where a report and `docs/14` disagree, `docs/14` wins — its claims
are backed by executed experiments.
