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
`evolution_accepted` → `main`.** ⚠️ **Fast-forward or merge commit, never squash or
rebase** — the docs cite commit ids throughout and squashing orphans all of them
(rationale and the record to complete afterwards: docs/22 **T0.5**). Not merged as of
2026-08-18: `main` is at `fb6473c`.

`gh` is not authenticated on this machine and will not be, so anything needing the
GitHub API is yours; plain `git` works and the branch is pushed and level with its
remote.
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

  **Reproduce any of this with `.github/run-ci-locally.sh` (`all` for every job).**

  **All three jobs' steps now executed in a clean container** (2026-08-18, HEAD `d89aeae`)
  — `hexpm/elixir:1.20.2-erlang-29.0.5-ubuntu-noble`, which is the Elixir/OTP pair
  `setup-beam` resolves to for this pin, on a **fresh `git clone` with no local `_build`,
  `deps` or config**:

  | job | result |
  |---|---|
  | `check` | `deps.get` · `format --check-formatted` · `compile --force --warnings-as-errors` · `test` (9,022 tests, 0 failures, 240 s) · `git diff --exit-code` — **all pass** |
  | `idempotency` | `mix test --only idempotency` — **passes**, 594 s (the item's ~11 min estimate holds) |
  | `corpus` | `mix test --only corpus` — **passes**, 1,501 tests, 0 failures, 212 s |

  That covers the failure modes a local run cannot: stale `_build` hiding a warning,
  dependence on local state, and the fixture-healer leaving the tree dirty (`git
  diff --exit-code`, the step most likely to pass locally and fail on a runner).

  **Still genuinely unknowable off GitHub**, and the only reason this item stays open:
  the action versions (`checkout@v4`, `setup-beam@v1`, `cache@v4`), the cache keys, and
  the cold ~1 GB corpus fetch — the container run mounted the local corpus and skipped
  `mix credence.corpus.fetch`. Treat those four as the hypothesis; everything else has
  been executed.

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

- [ ] **C20. Nothing to build — two measurements to TAKE during the 4th run.** Neither is
  settled by replay (the 2026-07-06 archive is being dropped); everything else in
  `docs/24` is done or refuted and stays there.
  * **B4** (docs/24 §B4, resolved in harness `27873ef`): count the `:solved` lens's
    non-NO_ACTION replies against this run's zero.
  * **B5** (docs/24 §B5): count `:rule_name_not_in_closed_set` against this run's 44.
    **Do not build the recovery lane first** — the cause was largely T4.3's `Logger`
    truncation and that is fixed, so the 4th run's own count is the experiment.

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

- [ ] **D6. C12(b) is BUILT — `mix cev.fire_rate` (harness `32946ef`, why the old "blocked
  on H10/H11" was wrong is in credence `1ed12f1`).** Two things left, both yours:
  * ~~Look at the 8~~ **— done, and none of them should be retired on this evidence.**
    Three (`no_ets_info_bare_size`, `no_hallucinated_struct_field_in_pattern`,
    `no_plug_before_dependency_definition`) were already retired at acceptance. The five
    that survive each key on a **general** failure mode, not on the shape of one row —
    any bare Erlang bitwise BIF, any local function in a guard, any tuple to
    `NaiveDateTime.new!/2`, any built-in type redefinition, the `:=<` atom — and each
    carries 13–34 tests. So the single fire measures **feedstock scarcity, not
    over-narrowness**: a model has to make that particular mistake for the rule to fire,
    and 230 rows is a small sample to expect it in. Re-run `mix cev.fire_rate` after the
    4th run; if one of the five is still at one fire with the log loss fixed, *then* it is
    a question.
  * **Decide whether to make the 4th run's logs pass-scoped, before B9's flip.** The run
    discards ~62% of its own fire evidence as it goes, so this measurement stays a lower
    bound until it changes, and this is the last moment to change it for this run. Small
    edit to `Cev.RowLog`, real blast radius — `cev.reset`, `AppliedRules.for_row/1`, the
    classifier's log reads and the Gate's `tail/1` all know the current layout.

- [ ] **D7. Only C10 is left, and it is a scope call rather than a gap.** (C9 is closed
  and C16 built in `0007208`; the refutations are in docs/24 §A5 — **do not re-derive
  them**, they are recorded specifically so nobody does.)

  `Issue` needs no change to carry a column — `meta` is a free map — so the work is
  populating **314 construction sites** against 9 tests that assert `meta` as an exact
  map, with no shared constructor to route them through (re-checked 2026-08-18). If you
  take it, keep the corpus key on line only: `credence.corpus.ex:522` and
  `accepted_findings.txt` are `path:line  rule`, so adding a column rewrites the snapshot
  and churns the budget gate. Telemetry is separate and means a new runtime dep for a
  library whose one consumer parses stdout.

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

  **The dead-code cleanup this item used to list first is DONE.** All 28 flagged sites
  were checked one at a time (`docs/25-dead-code-verdicts.json`): **7 deleted, 16 kept**
  as deliberate defensive defaults, **5 were not dead at all** — my earlier "34 sites"
  came from a keyword match and was wrong. Raw rates moved toward triaged as intended
  (`no_sort_then_reverse` 0.417 → 0.625).

  **That cleanup then paid for itself.** `no_manual_list_reduce` sits at the 40-mutant cap,
  so deleting a dead line freed a slot and a never-sampled mutant took it — and survived.
  Triaging that one found a real over-firing gap **and a test passing for the wrong
  reason**: a test named "does not flag when the base pattern is not an empty list" used a
  body that also failed a *different* check, so it stayed green with the pattern check
  disabled entirely. Four isolating cases added; the rule is now **0.800** (was 0.775).
  The other eight at-cap rules are untouched and their rows stand.

- [ ] **NEW — `SourceMask.byte_offset/3` overshoots by one on a grapheme cluster that
  spans a token boundary.** Confirmed, **not fixed**. On
  `x = %{a: "́b", c: marker(1)}` (the string's first codepoint is U+0301 COMBINING
  ACUTE) the parser reports column 19 for `marker` and `byte_offset/3` answers **20**;
  the true byte offset is 19.

  The docstring's model — "the parser counts columns in graphemes" — is right *within* a
  token and wrong at the seam: the tokenizer segments graphemes per token, so a literal's
  opening `"` and a following combining mark are two columns to it and one cluster to
  `String.slice/3`. Consequence is a repair landing one byte off, or a spurious `:error`.

  **⚠️ Do not "fix" this by counting codepoints instead.** Measured on 1.20.2, neither
  counting is right, so the obvious one-line change trades a rare bug for a commoner one:

  | line content | graphemes | codepoints |
  |---|---|---|
  | plain ASCII | ✅ | ✅ |
  | string starting with a combining mark | ❌ off by one | ✅ |
  | string holding a ZWJ family emoji | ✅ | ❌ off by four |
  | string holding a flag | ✅ | ❌ off by one |

  Graphemes are correct *inside* a token and codepoints are correct *across* the
  delimiter, so a correct conversion needs token boundaries — which is why this is not a
  one-liner and was not bundled with the mask repairs (`docs/25`).

  (The five `mask/1` defects found alongside it are fixed — evidence in the commit and in
  `test/source_mask_test.exs`, which fails 7 ways against the old scanner.)

  Method note, whichever floor you pick: a survivor is not an "add a test" item, it is a
  request to construct an input that *separates two programs*, and for many no such input
  exists. `prefer_no_question_mark_for_non_boolean` (0.400, **zero** equivalents) is the
  one rule in the sample whose tests are simply thin.

- [ ] **D11a. One item left, and it is not buildable as specified.** `docs/23-build-list.md`
  carries every disposition. The residue: **`no_process_send_after_infinity` is blocked on
  the REPAIR**, not on the `assumptions/0` switch the item used to name (`c3ba0d6`). No
  sound fix is known — the proposed guard is dead code on a literal, and deleting the call
  trades a loud crash for a timer that silently never fires. Unblocking it means finding a
  repair, not making a decision.
