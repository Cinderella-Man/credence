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
- [ ] **B4. Pin the task dataset — row indices have silently drifted.** The
  `0*01` glob now matches **282** task dirs vs the 230 the run saw; indices
  are positional (`Path.wildcard |> Enum.sort`), so run-index 225 now names a
  *different task* than the one in `rows.jsonl`. Every re-queue row number and
  any resume is invalid until the dataset repo is pinned back to its
  run-contemporaneous commit (`git rev-list -1 --before="2026-07-06" HEAD` in
  `elixir-sft-dataset`) or indices become content-addressed.
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

- [ ] **D5. C15 — backfill `## Bad`/`## Good` on Pattern and Semantic.** The
  gate landed (`test/rule_card_test.exs`, Rule Standard requirement 6) and
  covers the two parts that were cheap or load-bearing:
  * **Intent line, all 289 rules.** The moduledoc must open with one sentence
    naming the mechanism — that sentence is the dedup signal the classifier
    reads, and a list of rule *names* teaches a generating model nothing, since
    the next proposal arrives under a different name. Measured **274/289
    compliant** before gating, so it is a ratchet; 14 are ledgered.
  * **`## Bad`/`## Good` on Syntax, 40/43.** Gated there and nowhere else
    because for a Syntax rule those examples are **test infrastructure, not
    documentation**: `self_corruption_test.exs` runs the rule's own `fix/1` over
    its own source, and the Bad block is the adversarial input. Delete it and
    the oracle still passes — by having nothing to find.
  * All three scaffolds now emit an intent line plus both blocks, verified by
    generating one of each, so new rules are compliant by construction.

  What remains is the backfill where the block is documentation rather than
  machinery: **Pattern 120/157** and **Semantic 6/89**. Semantic is the reason
  this is not gated yet — an 83-entry ledger is a wall, and the C13/C14 lesson
  is that a wall teaches people to disable the gate. **Trade-off for whoever
  picks this up:** backfilling Semantic mechanically would produce 83 accurate
  but low-value blocks, whereas the intent line already carries the dedup
  signal; the case for doing it is the *second* signal it gives H8, not the
  documentation.

- [ ] **D6. C12(c) — the SHAPE half of over-fitting.** The **name** half is
  done: requirement 7 is now gated by `test/alpha_rename_test.exs`, and the
  answer is **zero** — no Pattern rule is keyed to a variable name. Two findings
  came out of measuring it rather than assuming it. First, docs/12 named three
  rules as over-fit (`prefer_map_intersect_over_mapset_intersection`,
  `prefer_lookup_for_digit_conversion`,
  `prefer_string_slice_for_trim_last_char`) and **all three pass the name bar**;
  they are over-fit in *shape* — a hard-coded four-stage pipeline, a byte-exact
  16-clause hex table, one 3-clause `case` — which is real and is what remains
  here. Second, the first three "offenders" the probe reported were all **its
  own bugs**: an attribute reference (`@re`) and a zero-arity definition name
  both parse as `{name, meta, nil}`, exactly like a variable, and the third was
  `Sourceror.to_string/1` normalising `'abc'` to `~c"abc"` on round-trip, which
  is why the gate now compares against a reprinted baseline rather than the
  original source.

  So C12(c) is the open part: retire or generalise those three matchers to the
  idiom's core. **Trade-off worth stating before anyone starts** — generalising
  a matcher widens what it fires on, and this project's standing rule is that a
  wider rule is often strictly worse than a narrow one. Each of the three needs
  its own corpus scan and equivalence argument, not a blanket widening. C12(b),
  fire-rate telemetry, stays blocked on the harness's H10/H11.

- [ ] **D7. T5.7** — C9 hot-path (the Pattern fix loop re-parses the source
  once **per rule**; discovery re-scans `Application.spec` every call), C10
  observability (no `Issue.column`, no telemetry — and nothing downstream yet
  consumes the `:reverted|:patch_rejected|:crashed|:no_op` vocabulary), C16
  (`rule_status/1` exposes neither `priority` nor `unsafe_in_dsl`; no
  `max_passes` config).
- [ ] **D8a. Build the duplicate gate — the fold work is done and it found the
  opposite of what was expected.** docs/12's C11 named three "duplicate
  clusters"; running them refuted two and confirmed one.
  * *Grapheme/count trio — NOT duplicates.* `AvoidGraphemesEnumCount`,
    `AvoidGraphemesLength` and `NoEnumCountForLength` **converge**: every entry
    point reaches `String.length/1`. They do overlap, and `NoEnumCountForLength`
    alone gives the weaker answer (it keeps the list allocation), but the
    Pattern round is a cascade and `AvoidGraphemesLength` finishes the job — so
    the outcome survives a rename, not merely the current alphabetical order.
    Pinned in `test/pattern/graphemes_count_family_test.exs`, and the moduledoc
    that taught the weaker rewrite as its flagship example is fixed.
  * *Length-guard pair — NOT duplicates.* `avoid_length_guard_less_than2`
    (`< 2`/`<= 1`) and `no_length_guard_to_pattern` (`> 0`, `== N`) cover
    disjoint predicates.
  * *Shared predicates — REAL, and already rotted.* `condition_bool?/1` was
    byte-identical (69 lines) in two rules; now `RuleHelpers.boolean_condition?/1`.
    Its sibling `boolean_expr?/1` was copied the same way and has **drifted** —
    the original grew a nested-`if` clause the copy lacks, while the copy's
    comment still claimed they mirrored. Left unsynced deliberately (widening
    changes what the rule fires on and needs its own evidence) but recorded.

  **A mechanical duplicate signal now exists, and it found a real duplicate on
  its first run.** The signature that works is the set of **atom literals in a
  rule's matcher** — the module and function names it keys on — with the
  moduledoc stripped. The obvious signature does not work and is worth recording
  so nobody rebuilds it: the qualified `Module.fun` CALLS in a rule's source are
  its own machinery (`Enum.map`, `Sourceror.*`), so scoring on those gives 133
  pairs at Jaccard >= 0.6 with `prefer_explicit_binary_arithmetic` ~
  `prefer_regex_match` at 1.0. Scoring on matched atoms gives **9** pairs, all
  plausibly related.

  The top pair was an exact duplicate: `no_list_delete_at_length` and
  `no_list_delete_at_with_length` had the same target
  (`List.delete_at(l, length(l) - 1)`), the same repair (`-1`), identical
  behaviour on every shape probed, and only the first ever fired in the pipeline.
  Retired, with its one unique assertion ported.

  **All 8 remaining pairs were triaged: none is redundant** — 6 overlapping, 2
  unrelated — which is the result that makes the signal trustworthy rather than
  merely loud. The one exact duplicate it found was the one it found first.

  **And triaging them found a live defect the probe was not looking for.**
  `prefer_concat_over_flat_map_identity` and `no_identity_enum_map` share a
  copy-pasted `identity_fn?/1`, and asking why only one copy worked exposed two
  **unreachable clauses** in the flat_map version: written as `{:&, [...]}` and
  `{:__aliases__, [:Function]}` — two-tuples, where the AST nodes are
  three-tuples with metadata. Valid Elixir, so nothing warned; no test covered
  the shape; so `Enum.flat_map(l, &Function.identity/1)` was silently missed
  while the identical `Enum.map` form was caught and pinned. Fixed and pinned.
  That is the third instance of copy-pasted predicates rotting in one copy
  (`condition_bool?`, `boolean_expr?`, now `identity_fn?`).

  **What is left is turning the probe into a gate**: ledger the 8 pairs
  C13/C14-style and fail on a new one. The threshold wants choosing on evidence
  — 0.6 is where the prototype ran, and now that every pair above it is known to
  be benign, the ledger would be 8 rows of "related, checked, fine", which is a
  weaker artefact than a gate that fires only on genuine subsumption. Worth
  considering a second signal (firing-set containment on shared fixtures) before
  fixing the number.

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

  That rule is a real check/fix parity violation rather than a cosmetic
  self-revert: on three traversals of one list bound to separate variables,
  `check/2` returns an issue and `fix_patches/2` returns **zero patches** — so it
  reports what it cannot repair, which is the shape the policy forbids. The
  repair is either to narrow `check/2` to what the fix handles, or to widen the
  fix; Semantic solved the same problem with the `should_report?/2` idiom
  (*the decline guard IS the fix*) and Pattern has no equivalent. **Trade-off:**
  narrowing loses a true finding the tool could report, widening needs its own
  equivalence argument for a multi-traversal rewrite.

  Worth keeping the metric: nothing measured fix coverage before, so "does
  coverage go up or down across an evolution" had no answer. It does now.

- [ ] **D11. T5.8 — write the honest build list.** Residue after refutation, and
  it is now **4 rules, not 6**:
  `no_enum_sort_then_map_values`, `no_raw_send_in_genserver_handle_call`,
  `no_stream_data_constant_with_range`, `fix_ets_new_string_name`,
  `fix_ets_options_bare_keypos`.
  * **`no_agent_update_tuple_wrapper` is off the list for good** — built,
    tested green, and deleted the same day: its "before" returns a valid value
    on every input, so the rewrite silently breaks working code. Failure mode
    catalogued as docs/17 entry 28.
  * The `hex_encode64`/`hex_encode32` widening (ledger row 119) **landed** as
    `@qualified_replacements` rows, so it is not build-list work either.

  What is left is the writing: produce the short verified list, respec catalogue
  items 3/5/11, and leave the 56 banked observations banked. The source line is
  docs/18 **end of §3** (~1676), not §5 as T5.8 cites.

All five items landed. The logs are archived, and the reasoning inside them now
lives in `docs/17`: entries **26** and **27** (rows 55 and 73 — `trap_exit`
without an `{:EXIT, _, _}` clause, which fires on the happy path; and the
early-exit belief with `return` removed), a third corruption path on entry
**11** (the `:do =>` emission, re-confirmed on Elixir 1.20.2), and the sister
tree's **25 drop rationales**, which existed nowhere in this repo. One recovered
regression test landed; three others were duplicates and deliberately did not.

Two findings worth carrying: the survivor probes answered both ledger questions
(`FixFunctionInModuleAttributeInlineUsages` is fine; `catch` inside `case` was
owned by nobody, now fixed in `af7b140`), and **one rescued rationale was
refuted by re-running it** — `prefer_enum_frequencies` was dropped for an
enumeration-order divergence that does not reproduce at any size. The drop still
stands, on a stronger argument: the two constructs return different *types*.

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
