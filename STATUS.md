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
level with their remotes.** This file holds **only what is still open**. When an
item lands, strike it in `docs/22-remaining-work.md` (the item-level tracker) and
**delete it here** — the reasoning lives in the commit message, the rule source
and the relevant `docs/` file, not on the map.

**Verified green, so not on the map** (2026-08-17): full suite **10,259 tests +
6 properties, 0 failures** with the corpus layer included; the `:idempotency`
sweep green; `mix format --check-formatted` and `mix compile --force
--warnings-as-errors` clean. Two rules for reading that line:

* Say which half of a two-part gate was verified. The `:idempotency` **sweep** is
  excluded from `mix test`; it went red for three fixtures and sat undetected
  across four rules because "idempotency green" here meant only the fast
  stale-entry half. See A5.
* No hand-copied counts. Per-phase rule totals used to be quoted here and drifted
  the moment a rule landed. The gates compute them from `default_rules/0` at run
  time and are green; that is the claim with something behind it.

**Read before trusting an older note:** the Pattern round no longer skips files
that fail to compile (`lib/pattern.ex:85-99`), so any earlier statement about fix
coverage predates it; concurrent `analyze/1` on two files defining the same module
returned NO issues, fixed with a module-keyed compile lock (`docs/24` §A8); and
`docs/24-improvement-research.md` records ranked improvements for both repos with
one change deliberately NOT to make.

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

**A1 and A4 are done and deleted from this map** (A1 by the maintainer's
confirmation above; A4's matrix was re-run 2026-08-17 — green, including the
`:idempotency` sweep, whose three offenders were diagnosed as a consequence of the
Pattern compile gate coming off and ledgered in `test/idempotency_test.exs`).

A4 is worth one standing caution: it is **a measurement with an expiry date, not a
fact**. Its evidence sat stale across four rules while reading as "done", which is
why A5 re-runs the matrix on `main` and why A6 exists.

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

- [ ] **C20. Two things left in `docs/24-improvement-research.md`; everything else
  there is done or refuted** (the refutations and the reasoning stay in docs/24 —
  B3's byte attribution was wrong by two orders of magnitude, B6 would have
  destroyed 14 accepted rules to catch 6 duplicates).

  * **B4 is a maintainer decision.** The `:solved` classifier lens has zero yield
    over 238 rows at $6.02 and 5.5 h per run, but the proposed replacement gate
    lets **154 of 238** through against its own bar of 20, and the variant that
    skips all 238 is untestable from the archive. Delete the lens, or keep it one
    more run and re-measure now that the outcome atoms reach the classifier.
  * **B5 is open with an intact case.** `:rule_name_not_in_closed_set` is 83% of
    classifier errors and the names are real live rules; reordering the `fires?`
    probe ahead of the closed-set check would recover ~43 rows per run. Its replay
    experiment needs a built clone, so it has not been run.

## D. Credence rule work (independent of the merge)

- [ ] **D4. C13(b) — one corpus-composition decision, and two small jobs.**

  T5.2's stated action (narrow, demote or retire
  `prefer_heredoc_for_multi_line_doc`) is **refuted and should not be done**:
  1,298 of 1,298 of its findings, and 167 of 167 of
  `no_trailing_newline_in_doc`'s, sit inside `lib/generated/` — 2% of the corpus
  carrying ~24% of the debt — and both fire **zero** times across ~19,400
  hand-written files. The rules found exactly their documented target.

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

  **Not decisions, still open:**
  * **`corpus_whitelist_validator` has never run — no batches staged, no reports**
    (re-measured 2026-08-17; not merely "its snapshot is stale"). Re-stage with
    `prepare_batches.sh` first: its copy is 2026-07-03 and ~1,000 rows over the live
    whitelist. **Yours to start** — one billed Claude session per 100-row batch, ~60
    of them, hours of wall-clock.

- [ ] **D6. C12(b) — fire-rate telemetry. Blocked on the harness's H10/H11.**
  C12(c) is done (`b3ffd62`, `d857b5d`); nothing here is waiting on a probe.

- [ ] **D7. T5.7** — C9 hot-path (the Pattern fix loop re-parses the source
  once **per rule**; discovery re-scans `Application.spec` every call), C10
  observability (no `Issue.column`, no telemetry — and nothing downstream yet
  consumes the `:reverted|:patch_rejected|:crashed|:no_op` vocabulary), C16
  (`rule_status/1` exposes neither `priority` nor `unsafe_in_dsl`; no `max_passes`
  for the **Pattern** round — the Semantic round already has one,
  `lib/semantic.ex:115`, so do not go looking for a missing mechanism).
- [ ] **D9. Mutant-survivor triage — a decision, plus the expensive half.** Rule
  Standard requirement 9 is the last ungated one, and C18 stages it: sweep →
  publish → fix the tail → only then a floor. Sweep done and deterministic
  (**0.740**, 629 killed / 221 survived, 39 rules, seed 0 — reproduced exactly
  three weeks and ~20 commits apart). The survivors classify structurally
  (121 need individual review; the rest are catch-all constants, comparison
  boundaries, position arithmetic and unreached defaults), and 10 rules hold 56%.

  Triage by reading **`tmp/mutants/mutants.tsv`** (852 rows, rule/operator/context) —
  gitignored, so the only copy is local; regenerable only because seed 0 is
  deterministic. Its rows predate this item's own `no_python_multi_return` fix, so a
  fresh sweep reads ~0.742 / 219: that is the fix, not a regression.

  **The decision is the floor, and it is yours.** Do not set `--fail-under` at
  0.740 — that fails rules for carrying defensive clauses rather than weak tests,
  which is C18's own reason for staging. Either (a) triage the 121, ledger the
  equivalent ones, and set the floor against the *triaged* rate — correct and a
  week's work; or (b) set a floor well below the rate (0.60 kills nothing today)
  purely as a regression ratchet — a day's work, much less bought. Per-rule either
  way: the distribution runs 0.475–0.875 and one number hides both ends.

  Method note worth keeping, from working the worst rule end to end
  (`no_python_multi_return`, 0.475 → 0.525, three failed attempts first): a
  survivor is not an "add a test" item, it is a request to construct an input that
  *separates two programs*. Exercising a path is not distinguishing it, disjoint
  clauses need one fixture each, and the assertion has to be the decline. For many
  survivors no such input exists that anyone would write.

- [ ] **D11a. Work the build list — no new-rule items left; one extension remains.**
  `docs/23-build-list.md` is the list; every candidate was verified by running its
  target through the live pipeline, and each entry carries its own hazards. Of the
  25 rebuild/salvage candidates, 17 are repaired.

  What remains, after report-only was closed as an option (2026-08-17):

  * **Remaining work (1), and it is not a new rule:** `fix_undefined_struct_in_pattern`
    — extend the live `Semantic.FixCyclicStructReference` to hoist struct-defining
    nested modules above their first reference, keeping that rule's compile-verifying
    `confirm_reorder/2` gate.
  * **Banked, not buildable (1):** `fix_when_guard_in_with_clause` — no field sample;
    it exists only in a disposition sentence that this session refuted. The unsafe
    widen it guards against is already blocked by a tested `:none` in
    `Credence.Syntax.WhenGuardPosition`.
  * **Closed by building only its sound half (1):** `no_remote_function_in_guard` —
    dead as named (report-only, plus three corruption paths in docs/17 §787). The one
    repair docs/17 certifies ships as `Semantic.FixStructTestInGuard`, gated on the
    target parameter being a bare variable; the other shapes stay banked.
  * **Dead as specified (2):** the GenServer reply-protocol pair and
    `no_stream_data_constant_with_range`. Their dispositions require report-only,
    which this project deletes; the failure modes stay banked in docs/17.
  * **Needs a mechanism decision (1):** `no_process_send_after_infinity` — a fix
    gated behind an `assumptions/0` safety switch is neither report-only nor
    unconditional, but `lib/assumptions.ex` carries two switches today and adding a
    third needs its own justification plus the property test
    `assumptions_meta_test` demands.

## F. Tracker & doc hygiene

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
