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
and the relevant `docs/` file, not on the map. **Never restate a count here.** The
gates compute them (`default_rules/0`, `over_firing_test.exs:78`) and every number
hand-copied onto this map has drifted within hours.

## A. Merge + cut 0.8.1 (release-blocking, in order)

**PR [#22](https://github.com/Cinderella-Man/credence/pull/22),
`evolution_accepted` → `main`, confirmed by the maintainer 2026-08-16.** That
settles the identity question this section opened with — the head is the branch
carrying the 374 acceptance commits, not `evolution`. `gh` is not authenticated
on this machine and will not be, so anything needing the GitHub API is yours;
plain `git` works and the branch is pushed and level with its remote.

**The one constraint on the merge itself: fast-forward or merge commit, never
squash or rebase.** The docs cite commit ids throughout — docs/16, docs/22 Part III,
the escalation ledger, IMPROVEMENTS.md — and squashing orphans all of them and makes
the sister reset (B2) produce a tree unrelated to the documented history.
- [ ] **A3. Paste the refreshed body.** `docs/PR_BODY_phase4.md` is updated and
  pushed — correct commit count, current test numbers, the merge-method warning,
  and a section covering what landed after the original Phase-4 text. Copying it
  into the PR needs the API, so it is yours.
- [ ] **A5. The release acts on main**, in order: (1) re-run the A4 matrix **on
  `main` after the merge** — `mix test` on a quiet box (~19 min: it now includes the
  `:idempotency` sweep, which no longer needs its own invocation),
  `mix format --check-formatted`, `mix compile --force --warnings-as-errors`; (2) stamp the date on `CHANGELOG.md`'s
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
  `--force --warnings-as-errors`, `mix test --exclude corpus --exclude idempotency`
  — the two layers the other jobs own — plus a `git diff --exit-code` that catches a
  fixture the healer rewrites), `corpus`
  (`mix credence.corpus.fetch` then `mix test --only corpus`, cached on
  `lib/credence/corpus.ex` since every entry is an immutable version or SHA), and
  `idempotency` (the ~9-minute sweep, which a local `mix test` also runs — only CI
  splits it out, for parallelism). The YAML parses and
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

- [ ] **B1b. The Gate runs the clone's FULL suite per candidate — and `mix test` just
  got ~9 minutes longer.** `Gate.phase_args(:non_corpus)` is `["--exclude", "corpus"]`
  (`lib/cev/evolve/gate.ex:589`) and `attempt/2` runs `mix test` with no file list
  (`:560`), once per candidate, with retries. Now that `:idempotency` runs by default,
  every one of those gains the ~9-minute sweep, under a 1800 s cap
  (`Config.gate_test_timeout_s`) that used to have 5× headroom and now has ~1.6×.
  Decide before the 4th run:
  * add `--exclude idempotency` to `phase_args(:non_corpus)`, mirroring CI — fast, but
    a generated rule can then ship non-idempotent, which is the blind spot that let the
    sweep sit red across four rules; or
  * scope the sweep to the candidate's own fixtures, which is the check the Gate
    actually wants (~5,200 fixtures is a repo invariant, not a per-candidate question);
    needs the sweep to take a scope.

- [ ] **B9. `mix cev.preflight` green, then flip this file to `PRODUCING`.**
  The flip is deliberate and last; preflight now genuinely enforces it.

## C. Harness loop quality (valuable before Phase 9, not gating it)

- [ ] **C20. Two things left in `docs/24-improvement-research.md`; everything else
  there is done or refuted** (the refutations and the reasoning stay in docs/24 —
  B3's byte attribution was wrong by two orders of magnitude, B6 would have
  destroyed 14 accepted rules to catch 6 duplicates).

  Both are now decisions **for the 4th run**, not archive questions — the 2026-07-06
  archive is being dropped rather than preserved, so neither is settled by replay.
  * ~~**B4**~~ **resolved** (harness `27873ef`): the lens's zero yield measured its own
    "BIAS STRONGLY TO NO_ACTION" instruction, not the rows, so neither deleting it nor
    re-measuring the skip-gate was the right move. The prior is gone, the bar stayed.
    Next run's measurement: its non-NO_ACTION count against this run's zero.
  * **B5. Apply the fix, do not re-measure it.** `:rule_name_not_in_closed_set` was 83%
    of classifier errors and the names were real live rules; running the `fires?` probe
    when a resolvable rule sits outside the closed set recovers an estimated ~43 rows
    per run. The replay was only ever there to quantify that, and it needs the archive.
    Land it in `classify.ex:161-193` before the 4th run and let the run measure it.

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

- [ ] **D12. One undocumented report-without-fix, found by tallying the corpus run.**
  Across 20,076 corpus files the whole suite logs `check found N issue(s) but fix
  returned IDENTICAL source` for exactly three rules: `NoEnumTakeNegative` (7),
  `NoMapKeysEnumLookup` (1) and **`NoKeywordGetIntegerKey` (1)**. The first two decline
  for safety reasons docs/07 records (order-independence, bounds/negatives). The third
  documents no decline anywhere — so under D10's settled policy it either gets a widened
  fix or stops reporting that shape. Reproduce by grepping a full `mix test` for
  `IDENTICAL source`; `fix_or_drop_test` cannot see any of them, since it asks whether a
  rule fixes nothing *at all*.

- [ ] **D11a. Build list: one mechanism decision left, and it is yours.**
  `docs/23-build-list.md` is the list; every candidate was verified by running its
  target through the live pipeline, and each entry carries its own hazards. Of the
  25 rebuild/salvage candidates, 17 are repaired.

  What remains, after report-only was closed as an option (2026-08-17):

  * **Nothing left here.** `fix_undefined_struct_in_pattern` is done — the nested
    scope now hoists in `Semantic.FixCyclicStructReference`, which also closes the
    report-without-fix case it had on that shape.
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
