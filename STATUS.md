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
  was ever published.

  Prepared (`51a4d96`): `CHANGELOG.md` now describes the release — it had not been touched
  since `4e9d16d`, so ten rules and a public API change were undocumented, and the date
  stamp in (2) means nothing until it does. Confirmed: zero tags, one `[0.8.1]` section,
  `mix.exs` version agreeing.

  **(5) is unblocked — `LICENSE` written**, MIT, `Copyright (c) 2026 Kamil Skowron`
  (sole author, first commit 2026-04-24). **Check the holder line is what you want** —
  it is the one part of that file I inferred rather than read. Hex's default `files`
  list covers `LICENSE*`, so no `mix.exs` change is needed. Unrelated and not a
  blocker: `package()` carries no `maintainers` and the project no `source_url`.

- [ ] **A6. CI has never executed on a runner — it needs this push.**
  `.github/workflows/ci.yml`, three jobs on a pinned Elixir 1.20.2 / OTP 29 (one pair by
  design, not a matrix: every behavioural claim in `docs/` was executed on it, and docs/17
  records 1.19.5 and 1.20.2 disagreeing about whether a rule's output parsed).

  Pre-flighted as far as is possible off a runner (`c898948`): pinned pair matches, all
  five mix tasks exist, no absolute local paths or env dependencies in `lib/` or `test/`.
  What remains unknowable without running it: runner behaviour, action versions, cache
  keys, and the cold ~1 GB corpus fetch. Treat the first run as a hypothesis.

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

- [ ] **B9. Only the flip is left — preflight is green up to it.** Run 2026-08-17: it
  passes the clone check (right path, right branch), the dataset check, and the secrets
  check, then halts on the mode interlock exactly as designed, reading the mode from the
  ACCEPTING repo's STATUS.md. Nothing else is owed.

  Note it halts inside `static_checks!()`, BEFORE `reconcile!()` — which does
  `git reset --hard`, `git clean -fd` and a **`git push`** on the clone. So preflight is
  safe to run for a status read while the mode blocks, and stops being safe the moment
  the mode is flipped. Flip it last, deliberately, as the item always said.

## C. Harness loop quality (valuable before Phase 9, not gating it)

- [ ] **C20. Nothing to build — `docs/24-improvement-research.md` is down to two
  measurements to take DURING the 4th run.** Everything else there is done or refuted
  (the reasoning stays in docs/24 — B3's byte attribution was wrong by two orders of
  magnitude, B6 would have destroyed 14 accepted rules to catch 6 duplicates).

  Neither is settled by replay: the 2026-07-06 archive is being dropped.
  * ~~**B4**~~ **resolved** (harness `27873ef`): the lens's zero yield measured its own
    "BIAS STRONGLY TO NO_ACTION" instruction, not the rows, so neither deleting it nor
    re-measuring the skip-gate was the right move. The prior is gone, the bar stayed.
    Next run's measurement: its non-NO_ACTION count against this run's zero.
  * **B5. Do NOT build it yet — measure in the 4th run.** I had this backwards earlier:
    the prize is not ~43 rows. Re-measured against the archive, 28 of the 44 name a rule
    that exists, and only **6** can be probed at all (the `fires?` gate needs a BEFORE,
    and 32 of the replies have none). More to the point, the cause is largely gone: a
    real rule missing from the closed set is what T4.3's `Logger` truncation produced,
    and that is fixed (`truncate: :infinity`). The experiment is the 4th run's own
    `:rule_name_not_in_closed_set` count against this run's 44.

## D. Credence rule work (independent of the merge)

- [ ] **D4. C13(b) — one corpus-composition decision, and one job that is yours to start.**

  (T5.2's "narrow or retire `prefer_heredoc_for_multi_line_doc`" is refuted and closed:
  all 1,298 of its findings sit in `lib/generated/`, and it fires zero times across
  ~19,400 hand-written files. The rules found exactly their documented target.)

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

  **Not a decision:** `corpus_whitelist_validator` is staged and has never run — 6,131
  findings in 62 batches (`95defc1`). Starting it is yours: one billed Claude session per
  batch, resumable in slices (`validate_loop.sh 3 2`).

- [ ] **D6. C12(b) is BUILT and has run — `mix cev.fire_rate` (harness `32946ef`).**
  C12(c) was already done (`b3ffd62`, `d857b5d`).

  **I had the blocker wrong, and it is worth saying why so it is not re-asserted.** This
  item said C12(b) needs H10 (per-rule provenance) and H11 (per-pass report). Neither half
  was actually missing. The birth link — the thing H10 was proposed to create — has been
  in **credence's own git history all along**: `cred-gen: new(semantic): no_foo [row 134]`,
  and **628 of 628** `cred-gen:` commits carry `[row N]`. That is a better carrier than
  H10's `var/cache/` JSON, because it survives both `cev.reset` and acceptance. The fire
  records ride the `APPLIED_RULES:` lines `Cev.AppliedRules.parse/1` already reads.

  (The one thing this item got right stands: credence's per-rule corpus counts are **not**
  a substitute. The corpus premise is "well-reviewed code, credence should find nothing",
  so zero findings there is the desired state, not a retirement signal.)

  **Measured on the 3rd run:** 117 rules observed firing, 52 on exactly one row, **8
  flagged as fired-only-on-their-birth-row** — three of which acceptance had already
  retired. Every count is a **lower bound** and the flagged 8 an **upper** bound: row logs
  do not survive their rows (`RowLog.close/1` deletes on ordinary completion; every other
  outcome moves the log to a path with **no pass component**, so a later pass overwrites
  an earlier one), which took 1,280 attempts down to 489 logs. The task computes that loss
  and prints it above the numbers.

  **Yours, and the only two things left here:**
  * Look at the 8. `mix cev.fire_rate --repo ../credence` lists them; each is a question,
    not a verdict, because its other fires may be in a deleted log.
  * **Decide whether to make the 4th run's logs pass-scoped** before B9's flip. As it
    stands the run discards ~62% of its own fire evidence as it goes, and this measurement
    stays a lower bound forever. It is a small change to `Cev.RowLog`, but the blast radius
    is real — `cev.reset`, `AppliedRules.for_row/1`, the classifier's log reads and the
    Gate's `tail/1` all know the current layout — so it is a deliberate call, not a
    drive-by, and it is the last moment it can be made for this run.

- [ ] **D7. Only C10 is left, and it is a scope call rather than a gap.**
  C9 is closed three ways and C16 is built (`0007208` — `rule_status/1` now reports
  `:priority` and `:unsafe_in_dsl`). The C9 detail is in docs/24 §A5: row 1 DONE, row 7
  refuted (8 discoveries = 1 ms against a 410 ms fix), row 9 refuted on measurement (zero
  rules fire on four of five real files, so the prize there is exactly 0%). **Do not
  re-derive those** — they are recorded specifically so nobody does.

  **C10, and it is a decision about scope, not a defect.** `Issue` needs no change to
  carry a column — `meta` is a free map — so the work is populating ~290 rules against 9
  tests that assert `meta` as an exact map. If you take it, keep the corpus key on line
  only: `credence.corpus.ex:522` and `accepted_findings.txt` are `path:line  rule`, and
  adding a column rewrites the snapshot and churns the budget gate. Telemetry is a
  separate question and means a new runtime dep for a library whose one consumer parses
  stdout.

- [ ] **D9. (a) is DONE — the triage is `docs/25`. One decision left: pick the floor.**
  All 225 survivors of a fresh sweep are triaged and ledgered
  (`docs/25-mutation-survivor-triage.md` + `docs/25-survivor-triage.json`).

  **Raw 0.737. Triaged 0.826** — 92 of 225 survivors cannot be killed by any input. The
  ≈0.77 ceiling this item carried was right in direction and low. `--fail-under 0.740`
  would sit 0.09 *below* what the tests already earn and could not fail anything.

  The triage was run **twice, independently**: 223/225 verdicts agree, both disagreements
  went toward MORE gaps, and `docs/25` records the conservative run. So the rate is stable
  to ±0.002 but **an individual verdict is ~99% reliable, not certain** — which is exactly
  the input to the decision below.

  **The decision, and it is only this:** floor **per rule** (the triaged distribution runs
  0.400–1.000; one global number is met by the strong rules and ratchets nothing) —
  at the triaged rate (maximum ratchet, but the 1-in-100 verdict instability says expect
  about one false failure) or a notch under it. `docs/25` has the per-rule table.

  **Two things worth doing first, both in `docs/25`:** 34 of the 92 equivalents are
  **provably dead code** in 15 rules — deleting it pulls the raw rate up to meet the
  triaged one, so the number the tool prints by default becomes trustworthy on its own.
  And nine rules sit at the 40-mutant cap, so their rates must be **re-measured** after
  any such cleanup, not projected.

- [ ] **NEW — `SourceMask.byte_offset/3` overshoots by one on a grapheme cluster that
  spans a token boundary.** Confirmed, **not fixed**. On
  `x = %{a: "́b", c: marker(1)}` (the string's first codepoint is U+0301 COMBINING
  ACUTE) the parser reports column 19 for `marker` and `byte_offset/3` answers **20**;
  the true byte offset is 19.

  The docstring's model — "the parser counts columns in graphemes" — is right *within* a
  token and wrong at the seam: the tokenizer segments graphemes per token, so a literal's
  opening `"` and a following combining mark are two columns to it and one cluster to
  `String.slice/3`. Fixing it properly needs token boundaries, which is why it is not a
  one-liner and is not bundled with the mask repairs (`docs/25` §"a real bug").
  Consequence is a repair landing one byte off, or a spurious `:error`.

  (The five `mask/1` defects found alongside it are fixed — evidence in the commit and in
  `test/source_mask_test.exs`, which fails 7 ways against the old scanner.)

  Method note, whichever floor you pick: a survivor is not an "add a test" item, it is a
  request to construct an input that *separates two programs*, and for many no such input
  exists. `prefer_no_question_mark_for_non_boolean` (0.400, **zero** equivalents) is the
  one rule in the sample whose tests are simply thin.

- [ ] **D11a. Build list worked out; one item left and it is not buildable as it stands.**
  `docs/23-build-list.md` is the list and carries every disposition — what was built, what
  is banked for want of a field sample, and the three that are dead as specified because
  report-only is not something this project ships.

  * **`no_process_send_after_infinity` — blocked on the REPAIR, not on the
    `assumptions/0` switch the item used to name** (`c3ba0d6`). The literal
    `Process.send_after(pid, msg, :infinity)` always raises `ArgumentError`, so no promise
    about running data applies to it; and no sound fix is known — the proposed
    `if arg == :infinity` guard is dead code on a literal, and deleting the call trades a
    loud crash for a timer that silently never fires. The dataflow shape
    (`Keyword.get(opts, _, :infinity)`) is where a switch would live, and it is the half
    with the corruption history.

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
