# 24 — Improvement research: Credence and the harness

Written 2026-08-17, against credence `evolution_accepted` and harness `1f62e16`.

This is a **research** document, and the distinction matters here more than
usual. This project has been burned repeatedly by written claims that evaporated
when someone ran them — four in one session, every one in the direction that made
the codebase look worse than it was. So every item below carries one of three
markers:

* **[MEASURED]** — I ran it. The number is reproducible from the command given.
* **[READ]** — derived from code or logs by reading, not by executing. Treat as a
  hypothesis with a named experiment, not as a finding.
* **[DONE]** — already landed on this branch; recorded so the next reader knows
  the ground moved.

Items marked [READ] must not be acted on without first running the experiment
attached to them. That is not ceremony — **B6** is the example. It is a change
IMPROVEMENTS.md proposes and that I would have made on the strength of the
argument; joining it against the run's own labels shows it would have destroyed
14 accepted rules to catch 6 duplicates.

---

## Part A — Credence

### A1. The Pattern round skipped every file that did not compile — [DONE]

`Credence.Pattern.fix_with_trace/2` opened with `if compiles?(code_string)` and
skipped all 156 rules otherwise. **625 of 1,724 Pattern test fixtures parse but
do not compile; 275 of them now receive a repair that gate refused, and none
gained a compile error.** A single undefined helper was enough to disable the
whole round, and that is what LLM output looks like mid-generation.

Replaced by a relative oracle: a fix is accepted when its compile errors are a
subset of those already present. On compiling input the baseline is empty and the
check is byte-for-byte the old one. See `RuleHelpers.compiles_no_worse?/2`.

### A2. Reporting and fixing were each gated; nothing checked they met — [DONE]

Six Pattern rules reported their own documented anti-pattern and repaired none of
it. All six were defects in the *examples* (bare snippets rather than modules),
not the rules. `test/rule_self_repair_test.exs` now gates both rounds:
153 of 156 Pattern rules repair their own example directly (3 ledgered cascades),
and 89 of 89 Semantic rules repair one of their own fixtures.

### A3. Two rules documented an example they do not fire on — [DONE]

And the extractor that found them had two bugs of its own, each of which
manufactured a fake finding. `test/rule_card_test.exs` now gates both directions:
every `## Bad` example must make its rule fire, and no `## Good` example may.

### A4. Over-fitting in shape — partially [DONE], the third is open

docs/12 C12(c) named three rules as over-fit in shape. Probing them agreed, but
not where the doc said:

* `prefer_lookup_for_digit_conversion` — **[DONE]** keyed on the UPPERCASE hex
  alphabet alone, so of the two spellings an author writes it fired on one.
  Lowercase is what git SHAs, MD5 digests and CSS colours look like. Now matches
  both, and the repair reads the alphabet back off the input rather than
  hardcoding it, so a wider match cannot produce the wrong case.
* `prefer_string_slice_for_trim_last_char` — **[DONE]** was positional: exactly
  three clauses, in one order, under `String.graphemes`. Now accepts any clause
  set where one clause slices, it comes last, and the rest return `""` — which
  covers the two-clause wildcard form and `String.codepoints`. Equivalence to
  `String.slice(str, 0..-2//1)` was executed over combining characters, ZWJ emoji
  and CJK for each variant before widening. A *leading* slice clause is
  deliberately excluded: it is equivalent, but it makes the trailing clauses
  unreachable, which belongs to `RemoveUnreachableClausesAfterCatchall`.
* `prefer_map_intersect_over_mapset_intersection` — **probed, boundary pinned,
  deliberately NOT widened.** It fires on **2 of 8** plausible spellings. Of its
  five requirements, three are load-bearing for equivalence and must not be
  widened — the trailing `Enum.sort()` (without it the repair silently reorders,
  since `Map.intersect/3` returns a map), `Map.fetch!` rather than `Map.get`
  (raises vs `nil`), and the `min`/`max` combiner, which is already general.
  Only two are incidental syntax: an inlined pipeline with no `common_keys`
  binding, and `MapSet.new(Map.keys(x))` as a call rather than a pipe. That is
  the entire available gain from widening a five-stage structural matcher, so
  the measurement and the boundary are pinned in tests and the decision is left
  to whoever has a corpus fire-rate to weigh it against (C12(b)).

### A5. Performance in the fix hot path

The Pattern round did ~176 parses and ~8–17 compiles per file where ~12 parses
and ~7 compiles suffice. The first two are [DONE]; the rest are ranked by
gain/risk.

| | change | cost removed | risk | status |
|---|---|---|---|---|
| 1 | Thread the parse through `run_fixable_rules/4`'s accumulator | ~150 Sourceror parses per file | very low | **[DONE]** |
| 2 | Compute `compile_errors(fixed)` once in the accept/revert decision | 1 compile per accepted fix on the 36% of files that do not compile | very low | **[DONE]** |
| 3 | Hoist `rules/1` into the branch that uses it in `Syntax.fix_with_trace/2` | 1 discovery per file, on the path that discards it | none | **[DONE]** |
| 4 | `analyze_after: false` opt-out on `Credence.fix/2` | 1 compile + 2 parses + 156 checks per call | low-medium (public return field) | **[DONE]** |
| 5 | Thread `DslGuard.block_ranges/2` through `dsl_partition` | ~12 AST walks when 4 DSL-unsafe rules fire | low | [READ] |
| 6 | `DslGuard.count_subtrees/2` is O(N·depth) — `strip_meta/1` prewalks the subtree at every node | quadratic outlier on large patches | low | [READ] |
| 7 | Memoize `discover_rules/1` in `:persistent_term` | 2–15 ms per file | medium — code-reload staleness; needs a reset hook for `mix credence.mutants` | [READ] |
| 8 | Lockstep meta-insensitive equality in `diff_patches/2` | O(N·depth) → O(N) per firing rule | medium — equality semantics need a property test first | [READ] |

**On #1's safety, since it is the largest:** there are seven ways out of the
reduce and exactly **one** returns a different source, so the threaded parse is
only ever stale if that one branch forgets to re-derive it. That is a single
place to get right rather than a cache with an invalidation window. The
re-derivation must go through `Sourceror.parse_string/1` and keep the `{:error, _}`
branch — `apply_rule_fix_with_status/3` only proved the output satisfies
`Code.string_to_quoted/1`, and Sourceror parses under a different option set, so
"it was accepted" is not "Sourceror can read it".

**Before doing #7, run the experiment.** It is the one most likely to be
premature:

```
mix run -e 'Credence.Pattern.default_rules()
  {us,_} = :timer.tc(fn -> Enum.each(1..8, fn _ -> Credence.RuleHelpers.discover_rules(Credence.Pattern.Rule) end) end)
  IO.puts("8 discoveries = #{div(us,1000)}ms — this is the entire prize")'
```

If that prints under ~10 ms, the two hoists are the whole win and
`:persistent_term` buys a staleness hazard for nothing.

### A6. Examples shared module names, and it bit three times — [DONE]

Measured: `defmodule Bad` in 21 rules, `defmodule M` in 14, `defmodule Example`
in 13, `Solution` in 5 — 9 names shared across 126 examples. Harmless as
documentation; a hazard the moment gates COMPILE those examples, because the
Erlang code server is global and two async tests defining `Bad` race, one
deleting the module the other is mid-check on.

It surfaced three separate times, and each time it looked like a rule defect:
`NoDuplicateFunctionClauses -> reverted`, then `FixFnGuardPosition` and
`FixNegationInGuard` "not reporting" on their own examples. All three passed
when run alone, which is the worst shape a flake can have — it reads as a real
finding.

The first two were worked around with `async: false`. That was the wrong fix:
every example module name is now unique, derived from its own rule, so the
hazard is gone at the source and both gates are concurrent again. A gate in
`rule_card_test.exs` asserts the uniqueness across all 242 example modules in
both rounds, so it cannot quietly come back — and perturbing two rules to share
a name turns it red naming both.

### A7. The Semantic backfill is done, and it REFUTED its own motivation — [DONE]

The argument for backfilling Semantic was that it would give that round a
duplicate signal, which it had none of. All 86 examples are now in and verified
true — and pointing the D8a intersection at them reports **zero** pairs, for a
reason that makes the whole idea wrong rather than merely unproductive.

Semantic dispatch is first-match-wins, so a snippet is claimed by exactly one
rule. Measured: **84 of 89 rules fire on exactly one snippet**, their own.
Containment between two singletons is false unless they are the same singleton,
so the containment half can almost never fire and a gate on it would pass by
construction — the T3.10a vacuity failure exactly. The signature half alone is
no better: 76 pairs at Jaccard >= 0.6.

The Semantic duplicate question is already answered by a different and stronger
mechanism: a Semantic duplicate is a rule that never wins its dispatch slot,
which `dispatch_contention_test.exs` detects directly and `pipeline_witness`
catches end-to-end.

So the backfill's value turned out to be the shared adversarial corpus and the
truth gate over it — which found two pre-existing false examples — not the
duplicate signal it was proposed for. Worth recording as the fifth claim this
project has had refuted by running it.

---

## Part B — The harness

All of Part B is **[READ]** unless marked otherwise: it comes from reading harness
code and aggregating its run logs, not from executing the harness. The two
aggregations *were* computed rather than quoted — 1,280 rows in
`var/run/rows.jsonl` and 489 archived row logs from `run-2026-07-06`.

### B1. `Implement.wrote_nothing?/1` reads a key that does not exist — [DONE]

`lib/cev/implement.ex:97` reads `bf.rule_source`. The only producer,
`lib/cev/evolve/router.ex:454`, writes `rule_src` — as does the other consumer at
`lib/cev/implement/seed.ex:206`. `rule_source` appears nowhere else in `lib/` or
`test/`.

The live driver is `:cc`, so this runs on every `{:ok, _}` agent return on a
bugfix row. The raise escapes into `Orchestrator.safe_rule_gen/3`'s rescue, so a
completed ~25-minute implementer session is discarded and the row is booked
`:raised`. Introduced in `98bcddf` (2026-07-28), *after* the 3rd evolution, so it
has never run in anger.

**Fix:** `bf.rule_source` → `bf.rule_src`. **Experiment / the missing control:** a
unit test calling `Implement.run/2` on a ctx from `Router.bugfix_ctx/5` with a
stub returning `{:ok, %{}}`, asserting `{:gave_up, {:cc, "no_writes"}}` rather
than a raise. Highest value-per-line in this document.

### B2. Both crash handlers DELETE the row log — [DONE]

`Orchestrator`'s two rescues call `safe_close_log/1` → `RowLog.close/1` →
`File.rm(...)`. Every other outcome *moves* the log instead.

**89 rows of the 3rd evolution (7.6%) therefore have no evidence at all** — 68
`rulegen: raised` plus 21 `outcome: exception` — and grepping all 489 archived
logs for the crash markers returns zero hits. `raised` rows also carry
`decision: null`. This is why nobody knows what those rows were.

**Fix:** add a `"crashed"` outcome dir and `move/2` instead of removing.

### B3. The classifier reads the whole log, and `Cev.Distill` removes 0.08% of it

Median archived log 171,663 bytes; median after distillation 171,532. The
sentinel it splits on is emitted immediately before solve, so "everything below"
is the whole file. Classify then averages 54,511 input tokens per call over 1,296
calls — **$33.60 of the run's $66.73**, with zero cache reads on that stage.

What the bytes are, over a 124-log sample: 16.3% is
`[credence_fix] done. Applied: []` — a message whose content is that nothing
happened — and ~20% is `Code.compile_string raised:` dumps.

**Fix:** make `distill/1` structure-aware. **Experiment:** replay the 489 archived
logs through the candidate distiller offline (no LLM) for the byte reduction,
then re-classify 30 rows with known verdicts and measure decision agreement.

### B4. The `:solved` classifier lens has a measured yield of exactly zero

Cross-tabulating solve outcome against rule-gen outcome over 1,177 rows: of the
238 rows where solve succeeded, **zero** produced a commit, a bugfix, a
divergence or a switch proposal. Cost: $6.02 and 5.5 wall-hours. This is not a
bug — the prompt explicitly says "BIAS STRONGLY TO NO_ACTION" for that lens. The
design and the data agree; the design just has no output.

**Fix — gate, do not delete:** skip the classifier when solve succeeded *and* the
applied-rules sidecar holds no non-integer outcome *and* the log has no
`source CHANGED` trace. That keeps the one plausible source of value (an
over-fire visible in a clean solve). **Experiment:** replay the 238 rows through
the predicate offline; if more than ~20 survive, it is too loose.

### B5. `:rule_name_not_in_closed_set` is 83% of classifier errors and is recoverable

43 of the 52 logs in `classifier_errors/` are this, plus 51 re-asks that cost a
second full classify call and then failed anyway. The names are **real live
rules**, not hallucinations — `NoRedundantAssignment` ×8, `FixLocalFunctionInGuard`
×6, `UndefinedFunction` ×5.

The problem is ordering in `classify.ex:161-193`: closed-set membership is
checked *before* `RulePaths.resolve` and before the `fires?` probe. The probe
that can actually answer "is this report about this rule?" is never consulted for
an out-of-set name.

**Fix:** when the named rule resolves in the clone but is outside the closed set,
run `fires?` — `:fires` accepts and widens the set, `:inert` rejects, `:unknown`
passes. **Experiment:** replay the 43 archived specs through the reordered gate
and count how many become valid BUGFIX rows.

### B6. Do NOT make the novelty gate blocking — the run's own data refutes it

This is the item most worth recording, because IMPROVEMENTS.md H7 proposes
exactly the change the data rejects. Joining the 48 overlap-noted rows against
`docs/18-per-rule-verdicts.json`:

* 34 overlap-noted rows committed a rule; 20 were later rejected — a **59%**
  reject rate against a **55%** base rate. Essentially no discrimination.
* For duplicates specifically it is enriched ~1.8×, but precision is 6/34 =
  **18%**. Blocking would have destroyed 14 accepted rules to catch 6 duplicates,
  and still missed 19 of the 25 duplicate-rejects.

H7's *residual* check — compare `Credence.fix(before)` against the proposal's
`after`, re-run on the residual — is the part that could raise precision, and is
the only part worth building. Ship it only if an offline replay against the same
labels clears ~70% precision.

### B7. The harness consumes 1 of Credence's 4 fix statuses, and drops it before the classifier — step 1 [DONE]

`AppliedRules.parse/1` deliberately accepts any outcome atom. `reverted/1` routes
on `:reverted` only. And `modules/1` — the only thing that reaches the classifier
— is `Enum.map(&elem(&1, 0))`, which **discards the outcome three lines later**.
The classifier sees outcomes only incidentally, as raw text inside a 43K-token log
dump.

Also: across all 489 archived logs there are 2,472 `APPLIED_RULES` entries and
**every one is an integer**. Even `:reverted` has never fired in a real run.
`:patch_rejected`, `:crashed` and `:no_op` all landed after the run, so Phase 9
will be the first time the harness ever sees them.

**Order:** (1) **[DONE]** `AppliedRules.outcomes/1` carries the outcomes and the
prompt renders them with a legend defining each atom; validation still runs
against the plain module list, so no routing changed; (2) route `:crashed` into the
deterministic bugfix lane alongside `:reverted`, since a crash needs no
classifier judgment; (3) then consider `:patch_rejected` and `:no_op`.
**Experiment first:** run `mix credence.fix` over the 489 rows' final sources at
current HEAD and count each atom. If `:no_op` dominates and `:crashed` is
near-zero, invert that priority.

### B8. Gates with no positive control, and the mutation check's measured yield

Census of reject markers across the archive against the harness test suite:
`:scope`, `:pure_deletion`, `:no_test_change`, `:unstable_tests` and
`:environmental` have unit controls but no production red — fine. Three have
**neither**: `{:mutation_no_effect, _}`, `:no_changed_test_to_mutate`, and the
`:reverted` bugfix lane in the router.

The mutation numbers matter: `mutation OK` appears in 179 logs and
`mutation_no_effect` in exactly **1**, so the mutation check rejected 1 of 180
candidates — a 0.6% rejection rate. `gate.ex`'s own NOTE concedes why: for a new
rule, reverting `lib/` deletes the module, the test file cannot compile, and RED
is automatic. That is STATUS C6 / H4, now with a number attached.

**Experiment that decides whether H4 is worth building:** take 20 committed rules,
apply a blind mutant (`check/2 -> []`) to each, run its focused tests, and count
how many stay green. That number is the size of the assertion-free class.

### B9. Resumability — three real gaps

Most of it is sound: progress, rows, transient attempts, decisions and the whole
log tree are on disk; the per-pass permutation is derived deterministically from
the pass number, so a mid-pass resume re-derives the same order; and
`Preflight.reconcile!` hard-resets the clone, so a dirty tree recovers.

* **(a) The runaway budget ceiling resets to zero on every restart — [DONE].**
  `Budget` seeded `spent_usd: 0.0` and never read `usage.jsonl`, so the $500
  ceiling was per-VM-lifetime, not per-run — and a crash-restart loop, the exact
  failure it exists to stop, could never trip it. `init/1` now sums `cost_usd`
  from the run's usage log, skipping malformed lines (which can only
  under-count, failing toward "keep running" rather than a false shutdown).
* **(b) A row that kills the VM is retried forever with no counter.** Pending is
  recomputed from progress and the permutation is deterministic, so the same
  index is retried first on every boot. `TransientAttempts` only counts
  `:transient_abort`. Fix: an `in_flight` marker written on `RowLog.open` and
  cleared on completion, with a per-index crash count.
* **(c)** Row indices are positional against an unpinned glob — this is STATUS
  B4a, and the mitigation is confirmed: every `rows.jsonl` line carries `task`
  beside `index`, so the mapping is recoverable.

### B10. The harness test suite writes into live run state — [DONE]

`config/config.exs` sets `run_dir: "var/run"` for **all** envs and there is no
`config/test.exs`. Two measured consequences: **25 `sidecar_test_*.log` fixtures
sit at the top level of the run archive** — the durable evidence STATUS B1a is
about — and they are the only source of `ENVIRONMENTAL` strings there, so anyone
grepping it gets false positives. And `var/run/usage.jsonl` carries 118 synthetic
records totalling ~$35,636 of fake spend, which `mix cev.usage` reads directly.

There is also a latent hazard: `RowLog.open/1` swaps the *global* `:row_file`
logger handler, so running `mix test` during a live run would hijack the live
row's log capture.

**Fix:** a test-env config block setting `run_dir: "tmp/test_run"`. Cheap, and it
is what makes every later measurement of the archive trustworthy.

### B11. Do not measure the 3rd evolution's rejects from `rows.jsonl`

It contains **zero** `rejected` outcomes while `escalated/` holds 45 logs and
docs/22 counts 143 acceptance-review rejects. The cause is documented and
**already fixed** (`Jason` could not encode the `{:rejected, reason}` tuple; the
raise was swallowed and booked as `exception`). Flagged only because the 288
`committed` / 0 `rejected` in that file will mislead the next person.

---

## Doc claims this research refutes

Recorded because docs/22's four refuted claims taught this project to check:

* `harness/docs/IMPROVEMENTS.md` H5 says `evolve/gate.ex` "has **no unit tests**"
  and its `mix test` invocations have "**no wall-clock timeout**". Both are false
  today — `test/cev/gate_test.exs` is ~660 lines with named CONTROL cases, and
  `Cev.MixTest` wraps every invocation in `timeout --kill-after`. Treat that
  file's problem statements as dated, and its line cites as stale (H7 and H4 have
  both moved).
* `Cev.Distill`'s moduledoc claims it produces "a smaller single-call input". Its
  own run's logs say it removes 0.08%.
* `Cev.AppliedRules`'s moduledoc says the generic-atom parse means "this side
  must never again lose an outcome it has not heard of". True of `parse/1`; false
  of the pipeline, which discards the outcome in `modules/1`.

## Suggested order

**Credence:** A4's third rule (probe it before deciding), then A5 #4, then A5 #7
*only if* its experiment justifies it, then A7 as the real argument for the D5
Semantic backfill.

**Harness:** B1, B2, B10 and B9(a) are **done**. Next: B5 and B4 (pure token
savings, both with offline replay experiments), then B3, the largest single cost
lever, which needs the replay harness B4 and B5 build. Then B8 and B7. Leave B6
as a "do not build H7 as specified" note.

**One correction to B10 worth keeping:** the existing `var/run/usage.jsonl`
pollution is NOT cleaned up. Those are the maintainer's files, and deleting run
evidence is the exact mistake B2 is about. Measured for the recovery: 5,197
records totalling **$35,731.58**, of which 59 are individually over $100 — the
real run cost about $67, so a `cost_usd < 100` filter plus a timestamp cut
recovers it.
