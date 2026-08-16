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

- [ ] **A1. Identify and verify the PR.** docs/22 struck T0.2 on "a PR for the
  whole 3rd evolution already exists", but **no PR number, head, or base is
  recorded anywhere in the repo**, and `gh` is unauthenticated on this box, so
  no session has ever verified it. It MUST have head `evolution_accepted` —
  **not `evolution`** (`b83d623`, which lacks all 362 acceptance commits and
  every new meta-gate; merging that head would look like "the evolution PR" and
  be wrong). `gh auth login && gh pr list --state all --json
  number,headRefName,baseRefName`. Record the number here and in docs/22.
- [ ] **A2. Merge with an SHA-preserving method only** — fast-forward or merge
  commit, **never GitHub squash/rebase**: 362 commit ids are cited across
  docs/16, docs/22 Part III, the escalation ledger, IMPROVEMENTS.md and the
  session memory; squash would orphan every one and make the sister reset (B2)
  produce a tree unrelated to the documented history. Verified today after
  `git fetch`: `origin/main` = `fb6473c` and is an ancestor of
  `evolution_accepted` (0 commits behind → clean ff). Re-verify at merge time:
  `git merge-base --is-ancestor origin/main evolution_accepted`.
- [ ] **A3. Refresh the PR body.** `docs/PR_BODY_phase4.md` says 286 commits /
  9,615 tests; the branch now carries **362 commits / 9,975 tests**, and the
  defect table predates the T3.6 series, T2.5's gate, T2.4's re-measurement and
  T3.12.
- [ ] **A4. Finish the release test matrix.** Run today at `6962b7c`: full
  suite ✅ (9,975 + 6 properties, 0 failures), formatter ✅, zero-warning
  compile ✅, full `:idempotency` sweep ✅ (the ONE default-excluded credence
  tag; green in 650s on a quiet box — the first attempt hit its `timeout:
  900_000` under concurrent load, so run it quiet; the cap has only ~38%
  headroom), harness suite ✅ 326/326 (but it flaked 325/326 on the first run,
  test identity unknown — live evidence for C3/T4.7). Still never run:
  **harness `:integration` tests** (default-excluded; shell into the live
  clone — need `CEV_CREDENCE_CLONE` + `CEV_ACCEPTING_REPO` set, see B3).
  Re-run the whole matrix **on `main` after the merge** — see A6.
- [ ] **A5. The release acts on main.** (1) stamp the date on `CHANGELOG.md`
  `## [0.8.1] - Unreleased` (docs/22 T0.4: "stamping a date is the release
  act"); (2) `git tag v0.8.1` — the repo has **zero tags**; do not cut a
  v0.7.0 (folded into 0.8.1 by `24ce7df`); (3) push the tag; (4) decide
  hex.publish or not — `mix.exs` carries hex-shaped `package()` metadata but
  nothing was ever published.
- [ ] **A6. Know that there is no CI.** Neither repo has any CI (no `.github/`
  at all): the merge triggers zero checks and the local matrix in A4 is the
  only verification the release will ever get. Optional but cheap insurance:
  add a workflow running the A4 matrix before the next evolution.

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
- [ ] **B5. Minimum in-loop gates: T4.2 (c) and (d)** [H]. (c) require the
  classifier to quote the verbatim offending line from the `credence_fix`
  trace — the `Spec` struct has no field that could even carry it
  (`classify.ex:152-172`, `spec.ex:18-28`); (d) mechanically validate the
  repro against the accused rule before booking a BUGFIX (rows 40/50/59 were
  live over-fires talked away exactly here). Strongly recommended alongside:
  **T2.3** — see C1.
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
- [ ] **C2. T3.4 — equivalence probe upgrades** [C] (unblocks 3 diverged
  re-queues): (a) battery structs + MapSet dims; (b) tolerant `repair?/1` —
  now at `lib/mix/tasks/credence.equiv.ex:166-169`, not the tracker's
  `:131-134`; **row 105 is the mandatory positive control** for any probe
  change; (c) stacktrace normalization in `behaviour_equivalence.ex`.
  T5.5 (StreamData layer) is blocked only on this — T3.5 already landed.
- [ ] **C3. T4.7** flake-aware Gate (H19): a genuinely red flake still
  hard-rejects with no re-run (`gate_test.exs:226` pins the absence).
- [ ] **C4. T4.8** bounded auto-retry on corpus rejects (H6) — now affordable,
  T2.1's scoped dispatch landed.
- [ ] **C5. T4.9** H1 gold over-fire ratchet (diff against an
  accepted-gold-findings snapshot — 76/304 golds carry findings, never
  zero-assert) + H2 executable fix-safety oracle (needs H10's solve archive).
- [ ] **C6. T4.10** — all eight sub-items open: H4 (mutation check's vacuous
  RED for new rules — `gate.ex:231-262`'s own comment concedes it), H7
  (novelty is advisory; `router.ex:132-143` logs and builds anyway), H3
  (equiv single-var only; `:error` silently `:skipped`), H10, H11
  (`mix cev.report`), H16 (`solve.ex:38` deps one-liner), H17, H18.
- [ ] **C7. H5 residue the T4.6 DONE note narrowed away:** `sweep_scratch` has
  zero test references, and the corpus-reject Gate path has never been driven
  red through the Gate by a fixture bad rule (only unit tests of
  `Corpus.findings/diff`).

## D. Credence rule work (independent of the merge)

- [ ] **D1a. Re-audit the other message-matching Semantic rules for the same
  shape.** Row 183 turned out to be *three* unrepaired shapes, not the one it
  recorded: the matcher's trailing `/` excluded `defpstructp`, and the fix knew
  only the block form, so `defpstruct now: 0` — no `p` involved — was claimed
  and no-opped too. Both are now repaired. The transferable question is how many
  other rules pair a literal `@match_msg` with a `fix/2` that covers a narrower
  set of shapes than the matcher admits; `FixLocalFunctionInGuard` was the same
  story (T3.6), which makes three. Worth one sweep: for each Semantic rule, does
  every input its `match?/1` accepts have a `fix/2` branch?
- [ ] **D2. T3.6 — the 4.6d deferred salvage rows**: `Agent`, `NaiveDateTime`,
  `List.keystore`, `exit/2` into `UndefinedFunction`'s tables; blocked on
  call-boundary anchoring; `exit/2` also needs the arity check
  `replace_call_on_line/4` doesn't do. Salvage sources survive in the sister
  tree (never deleted by its 4.6c purge).
- [ ] **D3. T5.1 — C14 sweep**: exactly 40 DSL-unclassified rules remain
  (17 family-attributed first, then 23); delete the sweep tooling when empty.
- [ ] **D4. T5.2 — C13(b) paydown**: `prefer_heredoc_for_multi_line_doc`
  holds 1,298 of 6,366 accepted findings (20%) — narrow, demote, or retire;
  `prefer_erlang_float` taste review (37 gold findings); re-run
  `corpus_whitelist_validator` — its local snapshot is the stale 2026-07-03
  7,113-row copy vs the live 6,155-row whitelist, so the current whitelist has
  **never** been validated.
- [ ] **D5. T5.3 — C15 rule cards + intent line** (docs/19 requirement 6, the
  first of the three still ungated) — also the dedup signal H8 consumes.
- [ ] **D6. T5.4 — C12 alpha-rename generality** (requirement 7) + the three
  named over-fit rules, all still shipped un-generalized.
- [ ] **D7. T5.7** — C9 hot-path (the Pattern fix loop re-parses the source
  once **per rule**; discovery re-scans `Application.spec` every call), C10
  observability (no `Issue.column`, no telemetry — and nothing downstream yet
  consumes the `:reverted|:patch_rejected|:crashed|:no_op` vocabulary), C16
  (`rule_status/1` exposes neither `priority` nor `unsafe_in_dsl`; no
  `max_passes` config).
- [ ] **D8. Duplicates — the one stated goal with NO gate.** 25 of 143
  rejects were duplicates-of-live (G5, five literal same-name copies), yet
  docs/19's nine requirements contain no distinctness requirement and nothing
  mechanical checks it. Two halves: (a) the manual C11 folds — the
  grapheme/count trio (`avoid_graphemes_enum_count` / `no_enum_count_for_length`
  / `avoid_graphemes_length`), the length-guard pair
  (`avoid_length_guard_less_than2` / `no_length_guard_to_pattern`), the
  copy-pasted `condition_bool?`/`boolean_expr?` predicates; (b) consider a
  duplicate-mechanism meta-gate so the class cannot regrow (generation-side
  half is H8's verdict memory, already landed).
- [ ] **D9. Mutant-survivor triage** — untracked until now: T2.4's sweep is
  report-only *by design*, but nothing owns triaging the **221 surviving
  mutants** and then setting `--fail-under` (docs/19 row 9 stays "not
  measured" until this happens).
- [ ] **D10. Fix-coverage decision** — untracked until now: FIX_LOG.md defers
  "make ~20 Tier-3 no-op/self-revert rules check-only or comment-preserving".
  Check-only collides with the *fix-or-drop* policy, so the real choice per
  rule is comment-preserving vs retire-with-failure-mode. No metric exists for
  fixable-fraction of corpus findings; decide before Phase 9 generates against
  these rules.
- [ ] **D11. T5.8 — write the honest build list.** Residue after refutation:
  **6 rules to build** (`no_enum_sort_then_map_values`,
  `no_agent_update_tuple_wrapper`, `no_raw_send_in_genserver_handle_call`,
  `no_stream_data_constant_with_range`, `fix_ets_new_string_name`,
  `fix_ets_options_bare_keypos`) + respec catalogue items 3/5/11 + fold in the
  `NoHallucinatedBaseHexEncode` `hex_encode64/32` widening (ledger row 119).
  The "2 lines to widen" and "4 shipped bugs" halves already landed. The
  source line is docs/18 **end of §3** (~1676), not §5 as cited.
- [ ] **D12. T1.2 ledger paydown** — all **9** rows of the undocumented-winner
  ledger remain (docs/22's "one was paid down in this pass" is refuted by the
  code: the T1.2 repair was the two priorities, not a ledger row).

## E. Evidence salvage — **DONE 2026-08-16** (`42d3a59`)

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

## F. Tracker & doc hygiene (30 minutes; a tracker that lies is worse than one that is late)

- [ ] **F1. docs/22:** flip T2.5's checkbox (done, `8f400fd`); fix the T3.6
  header ("2 of 6" → five of six, only row 183 + 4.6d remain); "290/290" →
  **289** rules (157 Pattern / 89 Semantic / 43 Syntax after `no_else_if`
  retired); stale cites — `credence.equiv.ex:131-134` → `:166-169`,
  `gate.ex:116` → `:128/:198-202`, "three meta-gate files" → five,
  `docs/16:772-775` pointer is dead, "row 120" doesn't exist (the log-budget
  victims are rows 6/59/87/88/175/210/224; the fabricated-diff victim is 181);
  T1.2 "one pair paid down" → none (see D12).
- [ ] **F2. docs/21:** still says the STATUS.md interlock "is not implemented"
  — T4.1 landed; amend.
- [ ] **F3. docs/12/13/14** carry no banner pointing at docs/22 despite
  docs/22 claiming they do; **docs/19** §5 says "six of nine ungated" while
  its own §1 table shows three (6, 7, 9), and row E predates T2.4's measured
  0.740 kill rate.
- [ ] **F4. CONTEXT.md** says 155 Pattern rules in both trees; it is 157.
- [ ] **F5. Harness IMPROVEMENTS.md** "Landed so far" list is eleven commits
  stale.
- [ ] **F6.** Record the verified PR number + merge method (A1/A2) in docs/22;
  retire the `credence-evolution-harness-backup` clone (nothing unique in it).
