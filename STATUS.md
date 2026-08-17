# STATUS

The mode file (docs/19 §4). One question: **can rules be generated right now?**

```
MODE: CATCHING UP
```

Shared with `credence-evolution-harness`. `Cev.Preflight` reads this file through
`Cev.Status` (harness `24f2dee`) and halts a generation run while the mode is
anything other than `PRODUCING` — permission is enumerated, everything else
blocks, fail-closed on a missing mode line. The PRODUCING bar (docs/19
requirements 4, 5, 8 gated) **is met**; the flip is the maintainer's deliberate
act and is the *last* step of Part B below, not the first.

---

# The release map — everything left to close out the 3rd evolution

**As of 2026-08-17, credence `evolution_accepted`, harness `main`, both clean and
level with their remotes.** Originally produced by a 6-agent audit; since then a
long working session has closed a number of items and, more usefully, found
things that were not on any list. Nothing left on this map is done; when an item
lands, strike it in `docs/22-remaining-work.md` (still the item-level tracker)
and delete it here.

**Verified green, so not on the map** (re-measured 2026-08-17): full suite
**10,245 tests + 6 properties, 0 failures** (corpus layer included);
`mix format --check-formatted` clean; `mix compile --force --warnings-as-errors`
clean; every rule witnesses its failure mode through the real pipeline AND repairs
its own documented example; every `## Bad`/`## Good` example verified TRUE by
execution; self-corruption, dispatch-contention, duplicate, DSL and budget gates
all green; maintainer_tools queues drained.

Two cautions about that sentence, both learned today:

* **"idempotency-ratchet green" used to appear in this list and has been removed
  from it.** There are two halves and only the fast one runs by default. The
  ratchet (stale-entry) half is green; the full `:idempotency` **sweep** was red,
  for three fixtures, undetected since the Pattern compile gate came off — see
  A4. A gate excluded from `mix test` does not belong in a list headed "verified
  green" without saying which half was verified and when.
* **The per-phase rule counts that used to be quoted here are deliberately
  gone.** This line carried "Pattern 153 direct + 3 ledgered cascades, Semantic
  89/89" and "all 289 rules"; those moved when the D11a rules landed and nobody
  re-measured. The gates that own these numbers compute them from
  `default_rules/0` at run time and are green, which is the claim worth making.
  A hand-copied count is a claim with no gate behind it — exactly what F1-F5
  corrected once already.

**What this session changed that alters earlier assumptions** — read these before
trusting an older note:

* **The Pattern round used to skip every file that does not compile.** 625 of
  1,724 Pattern fixtures parse but do not compile; 275 now get a repair they
  never got. Any earlier statement about fix coverage predates this.
* **Credence returned NO issues for a file analysed concurrently with another
  defining the same module** — a silent false negative, 30 of 30 runs. Fixed
  with a module-keyed compile lock (`docs/24` §A8).
* **Four harness defects**, two of which change what its logs mean: a `KeyError`
  on every bugfix row, and crash handlers that DELETED the row log, which is why
  89 rows (7.6%) of the 3rd evolution have no evidence at all.
* **`docs/24-improvement-research.md` is new** — ranked improvements for both
  repos, every claim marked MEASURED, READ or DONE, with the experiment that
  must precede acting on the READ ones. It also records one change NOT to make.

## A. Merge + cut 0.8.1 (release-blocking, in order)

**PR [#22](https://github.com/Cinderella-Man/credence/pull/22),
`evolution_accepted` → `main`, confirmed by the maintainer 2026-08-16.** That
settles the identity question this section opened with — the head is the branch
carrying the 374 acceptance commits, not `evolution`. `gh` is not authenticated
on this machine and will not be, so anything needing the GitHub API is yours;
plain `git` works and the branch is pushed and level with its remote.

- [ ] **A2. Merge with an SHA-preserving method — fast-forward or merge commit,
  never squash or rebase.** 374 commit ids are cited across docs/16, docs/22
  Part III, the escalation ledger, IMPROVEMENTS.md and the session memory;
  squash orphans every one and makes the sister reset (B2) produce a tree
  unrelated to the documented history. Re-verify at merge time:
  `git fetch && git merge-base --is-ancestor origin/main evolution_accepted`
  (true as of 2026-08-16 — 0 commits behind, so a fast-forward is available).
- [ ] **A3. Paste the refreshed body.** `docs/PR_BODY_phase4.md` is updated and
  pushed — correct commit count, current test numbers, the merge-method warning,
  and a section covering what landed after the original Phase-4 text. Copying it
  into the PR needs the API, so it is yours.
- [ ] **A5. The release acts on main**, in order: (1) re-run the A4 matrix **on
  `main` after the merge** — `mix test`, `mix test --only idempotency` on a quiet
  box, `mix format --check-formatted`, `mix compile --force
  --warnings-as-errors`; (2) stamp the date on `CHANGELOG.md`'s
  `## [0.8.1] - Unreleased` (docs/22 T0.4: "stamping a date is the release
  act"); (3) `git tag v0.8.1` — the repo has **zero tags**, and do not cut a
  v0.7.0, it was folded into 0.8.1 by `24ce7df`; (4) push the tag; (5) decide
  hex.publish — `mix.exs` carries hex-shaped `package()` metadata but nothing
  was ever published. **Trade-off for you:** publishing makes the rule set
  installable and also makes every future rename a breaking change for
  downstreams; not publishing keeps the project git-only, which is what every
  doc currently assumes.
- [ ] **A6. CI is written but has never run — treat it as a hypothesis until it
  goes green once.** `.github/workflows/ci.yml` now exists (there was no
  `.github/` at all), with three jobs matching A5's list: `check` (format,
  `--force --warnings-as-errors`, `mix test --exclude corpus`, plus a
  `git diff --exit-code` that catches a fixture the healer rewrites), `corpus`
  (`mix credence.corpus.fetch` then `mix test --only corpus`, cached on
  `lib/credence/corpus.ex` since every entry is an immutable version or SHA), and
  `idempotency` (the ~11-minute sweep nothing else runs). The YAML parses and
  every command in it is one this session ran locally and green — but **no job
  has executed on a runner**, because that needs a push, which is yours. Expect
  the first run to need adjustment; the corpus job in particular fetches ~1 GB
  on a cold cache.

  Deliberately **one** Elixir/OTP pair (1.20.2 / OTP 29), not a version matrix,
  even though `mix.exs` allows `~> 1.17`: every behavioural claim in `docs/` was
  executed on that pair, and docs/17 entry 11 records 1.19.5 and 1.20.2
  disagreeing about whether a rule's output parsed. Widening it is worth doing
  and owns whatever it turns red.

**A1 is done; A4 was re-run 2026-08-17 and one of its four legs had gone red.**
A1 by the maintainer's confirmation above.

A4's original run was at `00c1c1c` — full suite **10,023 tests + 6 properties, 0
failures** (corpus included), the `:idempotency` sweep green in ~650 s, formatter
clean, zero-warning compile, harness **332 passed**. Re-run today at
**10,245 tests + 6 properties, 0 failures**, formatter clean, zero-warning
compile — **but the `:idempotency` sweep failed with three new offenders.**

Diagnosed, and it is not a rule defect. All three fixtures have
`compiles?/1 == false`, and the Pattern round **stopped skipping non-compiling
files** after `00c1c1c` (`lib/pattern.ex:85-99`). Before that they were fixpoints
by *exclusion*; now pass 1 repairs them and pass 2 finds a follow-on. Two are the
documented docs/14 E7 class (a Pattern fix leaves a variable the Semantic round
then renames `_x`), the third is a two-rule Pattern cascade
(`PreferMapNewWithTransform` → `NoGroupByForFrequencies`). Each was traced pass
by pass and converges after exactly two changes with no oscillation. Ledger
29 → 32, with the engine-change reasoning written into
`test/idempotency_test.exs` — because "the ratchet may only shrink" is the right
rule for a rule regression and the wrong one when the engine moved under the
measurement.

**The gap worth keeping:** `:idempotency` is excluded from the default suite, so
nothing catches a regression in it between deliberate runs. These three sat
undetected from whenever the compile gate came off until today, and A4 read as
"done" throughout. A4 is a *measurement with an expiry date*, not a standing
fact — which is A5's own reason for re-running the matrix on `main` after the
merge, and A6's reason for existing.

The harness `:integration` tests remain the one layer never run; they shell into
the live clone and need B3's two env vars, so they belong to the Phase-9 setup
rather than to this section.

## B. Phase-9 prerequisites (the next evolution; runbook order)

- [ ] **B1a. The archive is local-only — put the evidence somewhere durable.**
  `var/archive/run-2026-07-06/` now holds all 83 MB (verified byte-identical,
  35 entries), so `cev.reset` can no longer destroy it. But `var/` is
  gitignored, so this survives a reset and not a disk. Part E lifted the
  reasoning that mattered into committed files; decide whether the raw logs
  also warrant an off-machine copy before the next run.
- [ ] **B2. After the merge: reset sister `evolution` onto the new `main`.**
  The sister (`/home/kamil/projects/credence_evolution`, `b83d623`) contains
  **none of the five new meta-gate files** (pipeline_witness,
  dispatch_contention, self_corruption, idempotency, rule_helpers_ast_diff —
  docs/22 says "three"; it is five), has no STATUS.md, still ships the retired
  `no_else_if` live, and its CONTEXT.md understates the rule inventory. Until
  the reset, **no new gate binds the harness Gate**. After it, run the five
  gate files inside the sister once, as proof they bind.
- [ ] **B3. Repoint the clone — two env vars, not one.** The docs/22 runbook
  line (`CEV_CREDENCE_CLONE=…/credence_evolution`) is **incomplete since T4.1
  landed**: `Config.accepting_repo/0` falls back to the clone, which has no
  STATUS.md, so preflight halts `{:error, :missing}` instead of reading the
  mode. Set both: `CEV_CREDENCE_CLONE=/home/kamil/projects/credence_evolution
  CEV_ACCEPTING_REPO=/home/kamil/projects/credence`. (`config.exs:168`'s
  commented example is still another machine's path.)
- [ ] **B4a. Decide how row indices survive the NEXT run.** The immediate
  problem is solved: the `0*01` glob matched **230** dirs at run time and **282**
  now, so index 225 named
  `095_004_multi_currency_money_with_fx_conversion_01` then and
  `077_001_interval_tree_…` today — but `var/run/rows.jsonl` records `task`
  beside `index` for every row, so the mapping was never lost, only
  unmaterialised. `harness/docs/REQUEUE_ROWS.md` now carries all **28**
  re-queue rows resolved to names, and **all 28 task directories still exist**.
  No dataset pin needed, and pinning would have discarded 52 tasks the next run
  wants.

  What remains is a choice for the next run, not this one: either make the
  orchestrator resume by **task name** rather than bare index (`var/run/progress`
  stores an index today), or pin `:task_glob`/the dataset SHA per run so indices
  mean something for the run's lifetime. **Trade-off:** names are stable and
  verbose; a pinned SHA keeps indices meaningful but freezes the corpus of tasks
  a run can see.

- [ ] **B5. Minimum in-loop gate residue: T4.2 (c)** [H]. **(d) is DONE**
  (harness `3f7e64a` + credence `6b64aba`): a BUGFIX report whose repro does not
  make the accused rule fire now fails classification, via the new
  `mix credence.fires <rule>` probe. Note it is inert until B2 — the sister
  clone has no such task yet, and a clone without it answers `:unknown`, which
  passes by design. **(c) remains**: require the classifier to quote the
  verbatim offending line from the `credence_fix` trace. The `Spec` struct
  (`spec.ex:18-28`) has no field that could carry it, so this is a parser +
  prompt + validator change, not just a check.
- [ ] **B6. Secrets, endpoint, spend.** `config/secrets.exs` now exists with
  all three key groups, but the Mimo console cookie expires by design —
  validate with `mix cev.budget`. The solve stage points at
  `http://localhost:8000/v1/chat/completions` (`:local_qwen_thinking`) —
  `curl -m 5 http://localhost:8000/v1/models` before launch. The **spend
  decision has no recorded artifact** — still a human call.
- [ ] **B7. Work the re-queue list** (escalation_ledger.md:940-972; every cited
  row log verified present in `var/run/logs`). 26 rows: diverged 1+18, 7, 106,
  107, 162, 164, 205 (+31/185/33 only after C2/T3.4 lands; 105 stays out — it
  is the probe's positive control); escalated 2, 6, 100, 119, 144, 169, 225,
  95; classifier-error rows 1/23/125/138/139/141/203/227 (unblocked by T3.2);
  **row 199** — the run's one ACCEPT — apply `199.patch` by hand after
  narrowing `bare_neg_one_range?/1`. Plus the 105 remaining pass-5 rows
  (230 − 125 distinct completed) — all subject to B4's re-pinning first.
- [ ] **B8. Quota headroom** for the 26-row transient tail (11 classifier
  timeouts, 7 `:closed`, 5 HTTP 429, 3 implementer kills): raise the Mimo
  quota or add backoff.
- [ ] **B9. `mix cev.preflight` green, then flip this file to `PRODUCING`.**
  The flip is deliberate and last; preflight now genuinely enforces it.

## C. Harness loop quality (valuable before Phase 9, not gating it)

- [ ] **C20. `docs/24-improvement-research.md` is worked down to one item, and
  two of its proposals were refuted by replaying them.** Done: B1, B2, B7 (step
  1 — the classifier now SEES `:crashed`/`:no_op`/`:patch_rejected` per rule),
  B8 (positive controls for both mutation-check rejects), B9(a), B9(b) (a row
  that kills the VM is no longer retried forever), B10.

  **Refuted, do not build as specified:**
  * **B4** — the `:solved` classifier lens has zero yield over 238 rows ($6.02
    and 5.5h per run), but the proposed gate lets **154 of 238** through against
    its own bar of 20. The variant that skips all 238 is worse: it works only
    because no outcome atom occurred in the whole run, so it is untestable from
    the archive. **This is now a maintainer decision** — delete the lens, or keep
    it one more run and re-measure now that the atoms reach the classifier.
  * **B3** — `Cev.Distill` really does remove only 0.08%, but the replacement
    would remove **0.3%, not 36%**: the byte attribution behind it was wrong by
    two orders of magnitude. 91.6% of the log is the solve attempts themselves.
  * **B6** — making the novelty gate blocking would have destroyed 14 accepted
    rules to catch 6 duplicates. Was never started.

  **Left open with an intact case: B5** — `:rule_name_not_in_closed_set` is 83%
  of classifier errors and the names are real live rules; reordering the
  `fires?` probe ahead of the closed-set check would recover ~43 rows per run.
  Its replay experiment needs a built clone, so it was not run here.

## D. Credence rule work (independent of the merge)

- [ ] **D4. C13(b) — one decision for you, and two small jobs that are not.**

  **Measured, and it kills the item's stated action.** T5.2 said to narrow,
  demote or retire `prefer_heredoc_for_multi_line_doc` because it holds 1,298 of
  6,366 accepted findings (20%). Reading the *paths* rather than the count:
  **1,298 of 1,298** of its findings, and **167 of 167** of
  `no_trailing_newline_in_doc`'s, are inside `lib/generated/` — 2% of the corpus
  (426 files, two projects) carrying **24% of the entire debt**. Outside
  generated code both rules fire **zero** times across ~19,400 hand-written
  files. The rule is not a style rule firing on idiomatic code; it is a rule
  that found exactly its documented target (machine-emitted Python-style
  docstrings) and nothing else. Do not narrow, demote or retire it.

  **THE DECISION — corpus composition, and it is genuinely yours.** Add
  `"/generated/"` to `@excluded_segments` (`lib/credence/corpus.ex:697`, beside
  `/deps/`, `/test/`, `/node_modules/`) and re-pin, or leave it.
  * *For:* the corpus's own premise is "well-reviewed code, Credence should find
    nothing", and generated output is reviewed at its generator, never at its
    output. One deletions-only diff removes 1,466 findings, and the budget
    gate's invariant 4 then **permanently retires two of the fifteen
    grandfathered rows** — they can never exceed the cap again without a
    deliberate re-grandfathering.
  * *Against, and this is the strong half:* generated-ness is not what causes
    the noise — **one template decision replicated across 202 files** is.
    `lexical`'s 221 generated files produce zero findings. So the path predicate
    is 100% precise on *this* corpus and is still a proxy. It is also incomplete
    the other way: `date_time_parser/lib/combinators.ex` is machine-generated,
    carries ~161 findings, and no `/generated/` segment can see it. And after
    the exclusion all three affected rules have **zero corpus evidence in either
    direction** — `--only-rule` would answer "clean" from having scanned
    nothing, which is the vacuous answer the corpus gates exist to prevent.
  * *If you take it:* the corpus is local (1 GB, 500 entries) so
    `mix credence.corpus --update-snapshot --update-budget` needs no fetch, and
    the two grandfathered rows must come off `findings_budget_test.exs` in the
    same commit or the gate fails on invariant 4.

  **Not decisions, still open:** the `prefer_erlang_float` taste review (37 gold
  findings), and running `corpus_whitelist_validator` on its cadence — its local
  snapshot is the stale 2026-07-03 copy (7,113 rows) against a live 6,155-row
  whitelist, so the current whitelist has never been validated.

- [ ] **D6. C12(c) — two of the three shape-over-fit matchers are generalised;
  one is untouched.** The name half was already done (zero Pattern rules keyed to
  a variable name). On shape, `prefer_lookup_for_digit_conversion` now matches
  both hex alphabets and `prefer_string_slice_for_trim_last_char` accepts the
  two-clause and `String.codepoints` spellings, each after executing the
  equivalence rather than arguing it. **`prefer_map_intersect_over_mapset_intersection`
  (356 lines, a hard-coded four-stage pipeline) is not probed yet** — do that
  before deciding, since both of the others turned out narrower than docs/12
  described and in a different way than it described. C12(b), fire-rate
  telemetry, stays blocked on the harness's H10/H11.

- [ ] **D7. T5.7** — C9 hot-path (the Pattern fix loop re-parses the source
  once **per rule**; discovery re-scans `Application.spec` every call), C10
  observability (no `Issue.column`, no telemetry — and nothing downstream yet
  consumes the `:reverted|:patch_rejected|:crashed|:no_op` vocabulary), C16
  (`rule_status/1` exposes neither `priority` nor `unsafe_in_dsl`; no
  `max_passes` config).
- [ ] ~~**D8a. Build the duplicate gate.**~~ **DONE** — see
  `test/rule_duplication_test.exs` and `test/support/rule_duplication.ex`.
  Recorded here only because the *result* changed what D6 and D9 should assume:
  the gate reports **three** pairs, all triaged benign by execution, and a
  fourth crossing both signals is now a test failure.

- [ ] **D9. Mutant-survivor triage — the method is established and measured;
  the tail is not worked.** Rule Standard requirement 9 is the last fully
  ungated one, and C18 stages it deliberately: sweep → publish → **fix the
  tail** → only then a floor. The sweep re-ran clean at `0ef1685` and reproduced
  T2.4's numbers exactly (**0.740**, 629 killed / 221 survived, 39 rules,
  seed 0) — three weeks and ~20 commits apart, so the engine is deterministic.

  **The 221 survivors classify structurally**, which is what makes the tail
  tractable rather than 221 separate judgments:

  | class | n | share |
  |---|---|---|
  | needs individual review | 121 | 55% |
  | catch-all clause constant (`defp f(_), do: false`) | 44 | 20% |
  | comparison boundary | 25 | 11% |
  | catch-all branch constant (`_ -> :error`) | 14 | 6% |
  | position arithmetic (line/col ±1) | 9 | 4% |
  | unreached default argument | 6 | 3% |

  Concentrated, too: 32 of 39 rules have at least one, and the worst 10 hold
  56% of them.

  **The worst rule was worked end to end as the method, and it cost more than
  expected.** `no_python_multi_return` (0.475) went to **0.525** — two mutants
  killed, each verified by hand-mutating the source and watching the new test
  redden. Getting there took three failed attempts, and the reason generalises
  to the whole tail:

  * **exercising a path is not distinguishing it.** Three tests that ran the
    `when` code killed nothing, because the lookahead scans *forward* and the
    `when` lines sat above the candidate.
  * **disjoint clauses need one fixture each.** `starts_with_when?/1` matches
    exactly `when`, `when ` + rest, and `when\t` + rest; a `when true` line
    exercises only the second.
  * **the assertion has to be the decline**, and only where the line after the
    `when` is the `->`; anywhere else the scan halts either way and the mutant
    is equivalent *on that input*.

  So a survivor is not an "add a test" item — it is a request to construct an
  input that separates two programs, and for a good many of them no such input
  exists that anyone would ever write.

  **The recommendation, and the trade-off it turns on.** Do not set
  `--fail-under` at 0.740: it would fail rules for carrying defensive clauses
  rather than weak tests, which is C18's own stated reason for staging. Two
  defensible options: (a) triage the 121 "individual review" survivors, mark the
  equivalent ones in the ledger, and set the floor against the *triaged* rate —
  correct, and the expensive path; (b) set a floor well below the current rate
  (0.60 kills nothing today) purely as a regression ratchet, which buys much
  less but costs a day rather than a week. Either way the floor should be
  per-rule rather than corpus-wide, since the distribution runs from 0.475 to
  0.875 and a single number hides both ends.

- [x] **D10. DONE. Decided by the maintainer, gated, and paid to zero the same
  day.** The instruction: *"if rules can't fix the code they need to be removed.
  Try to check can you improve them; if yes go ahead, if not, remove them. WE DO
  NOT HAVE 'warn only' rules — Credence is FIXING code, not just complaining
  about it."*

  **The population was 24 findings across 9 rules, not the one this item named.**
  D10 asked whether a rule fixes *something*; the question that matters is whether
  any individual finding is reported and left unrepaired. Fix coverage was
  1486/1515 = 98.1%, and the missing 1.9% was real.

  ⚠️ **The first measurement said 46 across 13 and was wrong.** It drew fixtures
  from `PipelineWitness.candidates/1`, whose index over-collects by design — a
  witness only has to be found once, so a false candidate is free there. 22 of the
  46 were *prose*: test names and doc sentences that happen to parse. One made
  `UseMapJoin` fire and crash its fix, and would have been filed as a rule defect.
  A gate whose failure message accuses a rule of a bug needs the precise index
  (`MetaTestSupport.fixtures/1`).

  **Gated:** `test/fix_or_drop_test.exs` + `test/support/fix_or_drop.ex`. Nothing
  enforced this before — `no_op_trace_test` proves a no-op is *reported*, which is
  a different claim, and `corpus/scope_parity_test` gates only the converse. Runs
  in the **default** suite at 2.7 s, deliberately untagged, because A4 above is
  what happens to an excluded gate. Ledger **24 → 0**; its vacuity checks are in
  the machinery, not the result, so it still means something at zero.

  **Every one of the nine was the same defect: one decision kept in two copies.**
  `find_valid_groups` vs `find_fixable_groups`; `boolean_clause_pair?` vs a `cond`
  over `unwrap_pattern` (with `normalize_pattern/1` a byte-identical duplicate);
  `reassemble_call?` vs `reassemble_fixable?` (twice, in two sibling rules);
  `check_body/1` as a copy of `group_clauses/1`'s phase 1 with the safety test
  removed; `safe_callback?/1` re-listing what `wrap_arg/2` accepts;
  `check_clause/6` per-clause against a per-function-group fix. In each case the
  remedy was to delete the second copy, not to synchronise the two.

  **Two silent miscompilations came out of it, both in shipped rules, both found
  by asking why a rule DECLINED rather than by hunting bugs:**
  * `NoGuardEqualityForPatternMatch` rewrote `def f(x, {x, y}) when x == :a` to
    `def f(:a, {x, y})`, dropping the repeated-variable match constraint —
    executed, `f(:a, {:b, 2})` went from `:nomatch` to `2`.
  * `NoMapKeysOrValuesForIteration` passed an unrecognised callback through while
    rewriting `Map.values(m)` to `m` — executed with `cb = fn v -> v > 0 end` and
    `m = %{a: -1, b: 2}`, `false` became `true`, because the callback then receives
    `{:a, -1}` and a tuple outranks any integer in Erlang term order.

  Both compile, warn about nothing, and return a different answer, so no existing
  gate could see them: the net reverts on non-compiling output and these compile.
  `:no_patches` has two meanings that look identical from outside — "the fix knows
  something the check doesn't" and "the fix is quietly wrong".

  **One compromise, and it is the thing to revisit first.** Six of the 24 (both
  `NonGroupedClauses` shapes) were closed by removing reporting where a repair
  *does* exist. Moving an annotation run with its clause was implemented and
  reverted: the moves were right, the rendering was not — a moved slice keeps its
  old `do:`/`end:` positions and `patches_from_ast_transform/3` honours them, so
  two clauses printed onto one line, the failure docs/17 entry 11 records from this
  code path three times. The layout-metadata strip is specified in the source.
  Every other removal was verified to have no possible repair (no stdlib
  `count_and_sum`; an unreachable clause after a leading `_`; `"c-b-a"` is not
  `"cba"`; a base clause consuming its accumulator via `to_string/1`).

  Corpus effect across the sweep: **6367 → 6347** accepted findings, deletions
  only, 0 new over four re-pins.

- [ ] **D11a. Work the build list — it is written and measured.**
  `docs/23-build-list.md` replaces docs/17's ranked list (which docs/18 §5.3
  records as having taken heavy damage on review). Every candidate was checked
  by **running its target through the live pipeline**, not by reading.

  Of the 25 rebuild/salvage candidates, **16 are repaired** — and the
  reason that number is so high is that the honest repair for most was never a
  new rule but a row in `UndefinedFunction`'s tables. One of the eight,
  `no_agent_update_tuple_wrapper`, is repaired by *not existing*.

  **8 remain, each RE-verified uncovered on 2026-08-17** (worth redoing, since
  the Pattern round no longer skips non-compiling files: one item,
  `fix_undefined_type_t_in_spec`, turned out to be covered already by
  `NoBareNamesInSpec`). Five are built:
  `no_deprecated_not_in`, `no_pipe_into_unary_arithmetic`,
  `fix_ets_new_string_name`, `fix_ets_options_bare_keypos` and
  `no_enum_sort_then_map_values`. That last one **refuted the premise docs/17
  ranked it #1 on**: "every `Enum.*`/`Stream.*` returns a list" is false —
  `%Stream{}` is a struct, so `Map.values/1` on a `Stream.map` result does not
  raise; `Enum.group_by`/`frequencies`/`into`/`reduce` return maps;
  `Enum.at`/`find`/`max_by` return an element that is usually one; and
  `Map.new/1` *wants* a list. Measured: 350 candidate sites of the ungated class
  across the corpus, **zero** true positives, 65% of them `Map.new`. The rule
  shipped as the one producer-pair/one-consumer whitelist docs/18's disposition
  had already sanctioned; docs/17 §5.1 now carries the correction. No table rows —
  the three the list identified as cheapest (`Map.reduce/3`,
  `StreamData.string/0`, `:crypto.compare/2`) were added the same day, so
  everything remaining needs a rule and its own equivalence argument. Two of the Syntax ones
  (`fix_stray_comma_before_when_guard`, `fix_when_guard_in_for_comprehension`)
  must be built **together** — they emit the byte-identical parse error and need
  opposite repairs, so a shared backward scanner is the only safe way to build
  either. And `no_remote_function_in_guard` has three recorded corruption paths
  in docs/17 entry 11, one of which emits output that does not parse.

  **⚠️ "8 remain" overstates what is buildable — it is 5 workable + 3 blocked,
  and one of the five is not a rule.** Re-reading docs/18's `action` field for
  every remaining item (2026-08-17) found that four rule names across three items
  are specified **report-only**, which this project deletes rather than ships:
  both GenServer rules ("emit no fix"; "do not port this module's fix"),
  `no_process_send_after_infinity` ("ONE new REPORT-ONLY pattern-phase rule") and
  `no_stream_data_constant_with_range` (recorded as "REAL-but-not-catchable in
  the current architecture"). **That is the same decision as D10 above**, which
  reads as being about one rule and is not: if `NoRedundantListTraversal` may
  keep reporting what it will not repair, these three items become ordinary work
  under a named exception; if `check/2` is narrowed instead, they are dead as
  specified and their failure modes stay banked in docs/17.
  `no_process_send_after_infinity` alone has a third route — a fix gated behind
  an `assumptions/0` safety switch is neither report-only nor unconditional —
  and that is a mechanism change needing its own justification. The fifth
  workable item, `fix_undefined_struct_in_pattern`, is a redirect rather than a
  build: extend the live `Semantic.FixCyclicStructReference`. Table in docs/23.

## F. Tracker & doc hygiene

**F1-F5 are DONE** (`42d3a59`, plus the per-item passes since). Every claim
listed there was corrected: docs/22's stale checkboxes, counts and line cites;
docs/21's denial of the STATUS.md interlock; the missing banners on docs/12/13/14
and docs/19's self-contradiction; CONTEXT.md's rule count; and the harness's
`IMPROVEMENTS.md` landed-list.

- [ ] **F6. Two one-liners, both verified safe.**
  * Record the merge method in docs/22 once A2 happens. The PR is now recorded:
    **#22**, `evolution_accepted` → `main`.
  * **Retire `credence-evolution-harness-backup` — checked, it holds nothing
    unique.** Its HEAD (`f145884`) exists in the live harness; its only untracked
    items are `docs/IMPROVEMENTS.md` (the live copy is newer) and
    `docs/research/harness-internals.md` (**byte-identical** to the live one);
    no secret key is present there and absent live; the only file it alone has
    is an `.elixir_ls` editor cache. `rm -rf` is yours to run — the check is the
    part that needed doing, and deleting a directory I did not create is not
    something to do on inference.
