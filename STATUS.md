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

**As of 2026-08-16, credence `evolution_accepted` @ `6962b7c`, harness `main` @
`1f62e16`, both clean and level with their remotes.** Produced by a 6-agent
audit (4 read-only auditors + code-level verifier + adversarial critic) with
every load-bearing claim either executed today or marked as a hypothesis.
Nothing on this map is done; when an item lands, strike it in
`docs/22-remaining-work.md` (still the item-level tracker) and delete it here.

**Verified green today at `6962b7c`, so not on the map:** full suite
**9,975 tests + 6 properties, 0 failures** (corpus layer runs in the default
suite); `mix format --check-formatted` clean; every rule witnesses its failure
mode through the real pipeline (T1 gate — so "rules that never trigger" is a
closed class); the self-corruption, dispatch-contention, idempotency-ratchet,
DSL and budget gates all green; maintainer_tools queues all drained
(candidates, unfixable_unreviewed, assumption proposals — empty); escalation
ledger 95 decisions, all dispositioned except row 183 (D2 below).

---

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
- [ ] **A6. There is no CI in either repo** (no `.github/` at all), so the merge
  triggers zero checks and the local matrix is the only verification this
  release will ever get. Cheap insurance before the next evolution: a workflow
  running the A4 matrix.

**A1 and A4 are done.** A1 by the maintainer's confirmation above; A4 was run at
`00c1c1c` — full suite **10,023 tests + 6 properties, 0 failures** (corpus
included), the `:idempotency` sweep green in ~650 s, formatter clean,
zero-warning compile, harness **332 passed**. The harness `:integration` tests
remain the one layer never run; they shell into the live clone and need B3's two
env vars, so they belong to the Phase-9 setup rather than to this section.

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

- [x] **C19. Four harness defects found and fixed** (harness repo, 366 tests
  green). Listed here because two of them change what earlier measurements mean:
  `Implement.wrote_nothing?/1` raised `KeyError` on **every** bugfix row (a
  one-word key mismatch, landed after the 3rd evolution so never seen); both
  crash handlers **deleted** the row log, which is why **89 rows (7.6%) of the
  3rd evolution have no evidence at all**; `mix test` wrote into the live run
  dir, putting 25 ExUnit fixtures inside the durable archive and ~$35,700 of
  synthetic spend into `usage.jsonl`; and the runaway budget ceiling reset to
  zero on every restart, so a crash-restart loop could never trip it.
  Full research: `docs/24-improvement-research.md` §B.

- [ ] **C20. Work the rest of `docs/24-improvement-research.md`.** Ranked, with
  the experiment that must precede each. Next by value: B5 (`:rule_name_not_in_closed_set`
  is 83% of classifier errors and is recoverable), B4 (the `:solved` classifier
  lens has a measured yield of exactly **zero** — $6.02 and 5.5 hours for
  nothing), B3 (`Cev.Distill` removes 0.08% of the log; classify is half the
  run's cost). **B6 is a do-NOT-build note:** making the novelty gate blocking
  would have destroyed 14 accepted rules to catch 6 duplicates.


- [ ] **C1. T2.3 — land the LD3+LD4 merge.** ~60% done in salvage
  `b2-ld34/` (six modules, **zero tests**, agent killed at "Now the tests").
  Gate/Router integration was never designed; note the tracker's cite drifted:
  the bare `:no_lib_change` reject is now `gate.ex:128` + `check_touches` at
  `gate.ex:198-202`, tree discarded at `:148-151`. Take T2.2's H8 as merge
  base. Its own `probe.exs` is the first executable check.
- [ ] **C5. T4.9** H1 gold over-fire ratchet (diff against an
  accepted-gold-findings snapshot — 76/304 golds carry findings, never
  zero-assert) + H2 executable fix-safety oracle (needs H10's solve archive).
- [ ] **C6. T4.10** — all eight sub-items open: H4 (mutation check's vacuous
  RED for new rules — `gate.ex:231-262`'s own comment concedes it), H7
  (novelty is advisory; `router.ex:132-143` logs and builds anyway), H3
  (equiv single-var only; `:error` silently `:skipped`), H10, H11
  (`mix cev.report`), H16 (`solve.ex:38` deps one-liner), H17, H18.
## D. Credence rule work (independent of the merge)

- [x] **D14. Hot-path performance, three of eight.** See
  `docs/24-improvement-research.md` §A5 for the ranked table and the five that
  remain. Landed: the Pattern round threads its parse through the reduce instead
  of re-parsing per rule (~150 Sourceror parses per file), the accept/revert
  decision computes the output's compile errors once instead of twice, and the
  Syntax round builds its rule list only on the branch that uses it.


- [x] **D13. Every Pattern rule's own anti-pattern is now repaired end-to-end**
  (`test/rule_self_repair_test.exs`, 153 direct + 3 ledgered cascades). Not on
  the original list. Recorded because the *method* generalises: reporting and
  fixing were each gated, and nothing checked that the two met. Six rules passed
  both and repaired nothing through the pipeline.


- [x] **D12. The Pattern round no longer skips files that do not compile.** Not
  on the original list — found while backfilling D5, when six rules' own test
  fixtures turned out to get zero repair from `Credence.fix/1` despite their
  `fix/2` working perfectly in isolation. The cause was a single gate in
  `Credence.Pattern.fix_with_trace/2`: `if compiles?(code_string)`, else skip all
  156 rules. Measured cost: **625 of 1,724 Pattern test fixtures parse but do not
  compile, and 275 of them now receive a repair the old gate refused** — none of
  which gained a compile error. Replaced by a relative oracle
  (`RuleHelpers.compiles_no_worse?/2`): a fix is accepted when its compile errors
  are a subset of the ones already present. On compiling input the baseline is
  empty, so the check is byte-for-byte the old one. Full suite 10,109/0.


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

- [x] **D5. C15 — DONE. `## Bad`/`## Good` on all three rounds, every example
  verified true by execution.** Pattern 156/156, Semantic 86/89 (three declined:
  two whose fixture contains a heredoc delimiter, one already covered). Gated in
  `rule_card_test.exs` and `semantic_rule_card_test.exs`, both directions —
  every Bad example must make its rule report, no Good example may.

  **The Semantic backfill did NOT produce a duplicate signal, and that is the
  finding.** Pointed at Semantic, the D8a intersection reports zero pairs, and
  the zero is structural rather than earned: dispatch is first-match-wins, so
  **84 of 89 rules fire on exactly one snippet** — their own — and containment
  between two singletons is false unless they are the same singleton. A gate on
  it would pass by construction, which is the T3.10a vacuity failure. The
  Semantic duplicate question is already answered by `dispatch_contention_test.exs`
  (a duplicate is a rule that never wins its slot). The backfill's real value is
  the shared adversarial corpus and the truth gate over it.

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

- [ ] **D10. Fix coverage is 97.2%, and the deferred decision was about a
  population that does not exist.** FIX_LOG deferred "make ~20 Tier-3 rules
  check-only or comment-preserving" for a design decision. Two things are wrong
  with that framing, and measuring settles both.

  **Check-only is not available.** CONTEXT.md's standing policy is *fix or drop
  it* — a rule that can only find a problem is deleted, not kept as a warning.
  So the decision as posed had one legal option out of two.

  **And the population is one rule, not twenty.** Measured over every Pattern
  rule's own fixtures: **1,798 of 1,849 flagged fixtures produce a change —
  97.2%**. **Zero** rules flag without ever fixing. Exactly one sits below 50%:
  `NoRedundantListTraversal`, at 6/19.

  **That one rule is a deliberate decision, not drift — and it is the decision
  FIX_LOG meant to defer.** `NoRedundantListTraversal` fixes only
  `min`+`max` (into `Enum.min_max/1`). `@fixable_pairs` **excludes**
  `count`+`sum` on a written rationale: merging `length/1` and `Enum.sum/1` into
  a manual `Enum.reduce` with a tuple accumulator is a readability downgrade,
  and `sum`/`length` is the idiomatic way to compute a mean. So the rule reports
  "consider merging" and does not fix, on purpose.

  I narrowed `check/2` to the fixable set to enforce *fix or drop*, and reverted
  it: it turned 12 check tests red, all of them pinning that intentional
  reporting. **The decision is genuinely yours**, and now has numbers attached:
  * **keep it** — one rule reports 13 findings it will not repair, and the
    project's "every rule fixes" claim carries a documented exception;
  * **narrow `check/2`** — the claim becomes true without exception, 12 tests
    go, and a real redundancy stops being reported;
  * **widen the fix** — needs an equivalence argument for the count+sum merge
    *and* a defence of the readability cost the note already rejects.

  Worth keeping the metric: nothing measured fix coverage before, so "does
  coverage go up or down across an evolution" had no answer. It does now.

- [ ] **D11a. Work the build list — it is written and measured.**
  `docs/23-build-list.md` replaces docs/17's ranked list (which docs/18 §5.3
  records as having taken heavy damage on review). Every candidate was checked
  by **running its target through the live pipeline**, not by reading.

  Of the 25 rebuild/salvage candidates, **12 are repaired** — and the
  reason that number is so high is that the honest repair for most was never a
  new rule but a row in `UndefinedFunction`'s tables. One of the eight,
  `no_agent_update_tuple_wrapper`, is repaired by *not existing*.

  **13 remain, each verified still uncovered today.** `no_deprecated_not_in`
  is built (`lib/semantic/no_deprecated_not_in.ex`). No table rows are left —
  the three the list identified as cheapest (`Map.reduce/3`,
  `StreamData.string/0`, `:crypto.compare/2`) were added the same day, so
  everything remaining needs a rule and its own equivalence argument. Two of the Syntax ones
  (`fix_stray_comma_before_when_guard`, `fix_when_guard_in_for_comprehension`)
  must be built **together** — they emit the byte-identical parse error and need
  opposite repairs, so a shared backward scanner is the only safe way to build
  either. And `no_remote_function_in_guard` has three recorded corruption paths
  in docs/17 entry 11, one of which emits output that does not parse.

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
