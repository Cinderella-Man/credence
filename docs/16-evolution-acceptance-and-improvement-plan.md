# 16 — Forward plan: accepting the evolution and executing the improvement program

**Status:** plan · **Date:** 2026-07-21, updated 2026-07-27 · **Owner:** maintainer + Claude sessions
**Companions:** `docs/17-failure-mode-catalogue.md` (what the rejected rules taught us),
`docs/18-final-143-disposition.md` (per-rule verdicts + cross-rule reconciliation)
**Inputs:** `docs/12` (C1–C18), `docs/13` (P1–P7), `docs/14` (scrutiny E1–E9),
`docs/15` (hand-off index), `credence-evolution-harness/docs/IMPROVEMENTS.md`
(H1–H19 + addenda — currently only in the `-backup` copy, restored in Phase 0),
`maintainer_tools/candidates.md` (782 entries today; 776 after Phase 0.3), and a full read of the
evolution run's logs (`credence-evolution-harness/var/run/logs/`, summarized in
Appendix A).

This document is the single execution plan. Work top to bottom; each phase has
a **Definition of done**. Phases 5 and later can interleave once Phase 4 is
running, but nothing may skip Phase 0.

---

## START HERE (updated 2026-07-27, Phase 4 CLOSED)

**Phase 4 is COMPLETE.** All queues drained, all 143 rejected rules
dispositioned and applied, **nine live shipped defects across seven rules
repaired**. Suite 8058 → 8114 green in `credence`; 6842 green in the sister
after the deletion. Next: **Phase 5** (harness escalations) and **Phase 6**
(the C-items + the rebuild backlog below).

The evidence is in two companion documents, both **required reading before
touching the backlog**:

- **`docs/17-failure-mode-catalogue.md`** — what each rejected rule *taught us*.
  137/140 encode a real defect. Ranked "what is worth building" list at the end.
- **`docs/18-final-143-disposition.md`** — per-rule verdicts for all 143, with
  full failure-mode and action text, the cross-rule reconciliation, and the 56
  uncaught failure modes. Generated from **`docs/18-per-rule-verdicts.json`**,
  which is the source of truth; if the prose and the JSON disagree, the JSON wins.

### What is left, in order

1. **Phase 5** — triage the harness escalations (Appendix A). Untouched.
2. **Phase 6** — the 17 rebuild-later rules and the 56 uncaught modes. Ranked
   build list at the end of docs/17, but read §5.3 of docs/18 first: that list
   took heavy damage on review and has not been rewritten.
3. **Phases 7–9** — performance tail, harness improvements, next run.

### Five findings that will mislead you if you don't know them

- **Do NOT "rehome" a rejected semantic rule to the pattern phase.** It is the
  obvious remedy and it is wrong: adversarial testing overturned **17 of 17**.
  Semantic gets the compiler as a free correctness *oracle* (it already proved the
  code broken, so a repair cannot destroy a working program). Pattern has no
  oracle — `apply_or_revert` reverts only when output fails to *compile*, so
  broken-but-compiling output ships. See docs/18 §Reconciliation.
- **Green tests are not evidence.** A fabricated diagnostic appears in three
  mutually-consistent files (the rule's `@match_msg`, the check test, the fix
  test), so the rule agrees with itself and passes. Always compile the target.
  Two tests in this repo asserted a *silent branch deletion* as correct output
  and passed for as long as the defect shipped — see 4.6a. When a fix's meaning
  matters, assert behaviour with `Credence.RuleCase.call_fixed/4`, not text.
- **`lib/semantic.ex:191` is `Enum.find` — first match wins, no fall-through.**
  One rule per diagnostic. If the winner's `fix/2` no-ops, every other matching
  rule is silently dead. 12 dispatch slots are contested; `undefined variable
  "<name>"` alone is claimed by 17 rejected rules.
- **A wider rule is often strictly worse than a narrow one.** Twice during 4.6a
  a designed widening was rejected because it converted a *loud* failure into a
  *silent wrong answer* — the Python operators `&` and `%` bind more loosely
  than Elixir's, so rewriting only the immediate operands regroups the
  expression. Declining leaves a compile error, which names the file and line.
- **Never put load-bearing prose in a Markdown table cell.** docs/18's first
  revision lost ~162k characters that way, silently. See docs/15 gotcha 7.

---

## 0. State of the world (verified 2026-07-21; Phase-4 outcome appended 2026-07-27)

> **2026-07-27 update.** Phase 4 is closed. `credence` on `evolution_accepted`
> holds **295 live rules** (156 pattern, 92 semantic, 47 syntax — the new
> `lib/source_mask.ex` is a shared helper, not a rule) and an **8114-test** green
> suite. The sister `credence_evolution` has had the 112 dead rejected modules
> and their 227 tests removed (commit `b83d623`); it is on branch `evolution`,
> **pushed to `origin/evolution`**, so every deleted file remains recoverable and
> every verdict reversible. The 27 kept rules (17 rebuild + 9 salvage + 1
> already-live) are still there.
>
> Five rejected names also exist live as same-name siblings (`fix_div_rem`,
> `no_capture_as_bitwise_and`, `no_or_in_case_pattern`, `prefer_explicit_range_step`,
> `undefined_function`). Check which one you mean before acting on those — and
> note the trap 4.6c hit: in the *sister* these are deltas of files that exist on
> `main`, so rejecting the delta means restoring `main`'s version, not deleting
> the file. The numbers in the table below are the *pre-drain* snapshot and are
> kept for history.

**Branch topology.** `credence` is on `evolution_accepted` = `main` (`fb6473c`)
+ the setup commit + the research docs. `credence_evolution` (the sister
worktree, `$SISTER`, default `../credence_evolution`) is on `evolution` =
`main` + **294 cred-gen commits** + one docs commit (`f41a5f6`). The harness
(`credence-evolution-harness`) holds the run state; `-backup` is byte-identical
except for two docs it alone has.

**What the evolution produced** (A = this repo, B = sister):

| Round | A rules | B rules | Δ new | Δ modified |
|---|---|---|---|---|
| pattern | 146 | 158 | +12 | 5 |
| semantic | 16 | 190 | +174 | 6 |
| syntax | 19 | 81 | +62 | 1 |
| **total** | **181** | **429** | **+248** | 12 |

Plus 3 shared lib files (`lib/dsl_guard.ex`, `lib/rule_helpers.ex`,
`lib/semantic.ex`), 3 global test files, and 508 new + 8 modified test files.
`candidates.md` describes the A→B delta **completely and exactly** (verified by
`diff -rq`). `test/corpus/accepted_findings.txt` is **identical** in A and B —
no committed rule added corpus findings, so the drain's over-fire exposure is
limited to the 17 pattern candidates.

**The run behind it:** 5 passes over 230 dataset tasks (215 usable), 1,280
rows, ~165 h, 288 committed-rule rows (155 with retained logs: 98 new(semantic),
28 new(syntax), 5 new(pattern), 24 bugfix), 213 no_action, 45 escalated, 52
classifier errors, 13 behaviour-diverged, 26 transient, 1 switch proposal
(row 2, stored as a `.log` + `.json` pair).
Pass 5 is mid-flight: 125/230 done.

**Key operational facts:**

- All three stage-loop gates run a plain **`mix test` (full suite incl. the
  ~8.5-min corpus scan)** per row. The 1 GB corpus cache in this repo is warm,
  so there is no fetch danger — but ~260 rule-sets × ~9 min ≈ **37+ hours of
  gate time** unless Phase 3 lands first.
- `SISTER` defaults to `../credence_evolution` — correct as-is; no env needed.
- Stage 2/3 queue files and the stage-1 stub-pre-pass target file **do not
  exist** (deleted after the first cycle); the loops hard-error without them
  (Phase 0 recreates them).
- `candidates.md` as staged **violates the queue contract**: shared lib/test
  files can't be routed by `rule_kind` and would kill `review_loop.sh` on row 1
  (Phase 0 moves them out).

---

## 1. The plan at a glance

| Phase | What | Depends on | Rough size | Status |
|---|---|---|---|---|
| 0 | Restore/unblock the machinery | — | hours | **done** 2026-07-21 (`e4b343e`, `6581528`, `3e8c4d1`, `f178e26`) |
| 1 | Land the execution-verified defect fixes | 0 | hours | **done** 2026-07-21 (`69aa2ec`) |
| 2 | Apply shared-file deltas by hand | 1 | hours | **done** 2026-07-21 (`3a64b6f`; two hunks deferred by design) |
| 3 | Make the full suite cheap (P1+P2) | 1 | 1–2 days | **done** 2026-07-22 (`1e6e8c6`; 516 s → 251 s, targets recalibrated) |
| 4 | Drain the candidate queue (stages 1→2→3) | 0–3 | days (mostly unattended) | **done** 2026-07-27 (259 rows: 116 accept / 143 followup; 4.3–4.6 closed) |
| 5 | Triage the harness escalations | 0 (parallel with 4) | ~1 day | — |
| 6 | Credence improvement program (C-items) | 4 | ongoing, ordered | — |
| 7 | Remaining performance items (P3–P6) | 3 | days | — |
| 8 | Harness improvement program (H-items + log-derived) | 5 | ongoing, ordered | — |
| 9 | Next evolution run | 4, 7, 8 (order-1/2 items) | continuous | — |

---

## Phase 0 — Restore and unblock the machinery

Everything here is mechanical; nothing needs review judgment.

1. **Restore the harness research docs into the live harness repo.** They are
   referenced by docs/12/13/15 and exist only in the backup:
   ```bash
   cp ~/projects/credence-evolution-harness-backup/docs/IMPROVEMENTS.md \
      ~/projects/credence-evolution-harness/docs/
   mkdir -p ~/projects/credence-evolution-harness/docs/research
   cp ~/projects/credence-evolution-harness-backup/docs/research/harness-internals.md \
      ~/projects/credence-evolution-harness/docs/research/
   cd ~/projects/credence-evolution-harness && git add docs && git commit -m "Restore IMPROVEMENTS.md + harness-internals research doc" && git push
   ```
   After this the `-backup` clone has nothing unique; retire it when convenient.
2. **Recreate the stage data files** (all in `maintainer_tools/`, header-only,
   copying the header style visible in `git show main:maintainer_tools/followup.md`):
   - `unfixable_unreviewed.md` (stage-1 `move_unfixable_out.sh` target, stage-2 queue)
   - `proposed_assumptions.md`, `proposed_rules_requiring_assumptions.md`,
     `stage3_unfixable.md` (stage-3 outputs; `resurrect_loop.sh` errors if absent)
   - restore the explanatory headers in the zero-byte `followup.md` and
     `unfixable_confirmed.md`.
3. **Fix the queue-contract violation.** Remove these 6 lines from
   `candidates.md` and record them in a new `maintainer_tools/shared_deltas.md`
   (with the per-file notes from §Phase 2 below):
   `lib/dsl_guard.ex`, `lib/rule_helpers.ex`, `lib/semantic.ex`,
   `test/credence_test.exs`, `test/dsl_safety_classification_test.exs`,
   `test/fix_showcase_test.exs`.
   Queue drops to 776 lines, all per-kind rule/test paths.
4. **Fix `.gitignore` line 38** — a missing newline glued two entries into
   `.claudemaintainer_tools/corpus_whitelist_validator/accepted_findings.txt`.
   Split into `.claude/` and the validator path. (Note the validator's
   `accepted_findings.txt` copy is currently *tracked*; decide to untrack or
   keep — the corpus README says gitignored.)
5. Delete the orphan `maintainer_tools/.review_loops_run.log` (tracked, empty,
   referenced by nothing).
6. **Sanity-check the loop preconditions:** `claude` CLI on PATH; `$SISTER`
   resolves; stage-3's startup guard refuses while upstream queues are
   non-empty (by design); `./stage_1_promote_fixable_rules/generate_candidates.sh --dry-run`
   compared against the staged queue. **Executed 2026-07-21 — finding:** the
   generator would drop the 11 re-review bases (cycle-1-accepted rules with new
   sister deltas) because its resolved-base subtraction keys on "ever decided";
   the staged queue is authoritative — do not regenerate it this cycle (see
   `maintainer_tools/shared_deltas.md` §Queue provenance).
7. Commit all of the above as one `maintainer_tools: reset for the evolution
   acceptance cycle` commit.

**Definition of done:** `review_loop.sh 0` *would* start cleanly (verify with a
cap-1 pilot in Phase 4); all four stage data files exist; harness docs restored.

**Executed 2026-07-21.** Commits `e4b343e` (gitignore + untrack), `6581528`
(stage data files), `3e8c4d1` (queue contract + `shared_deltas.md` + orphan
log), `f178e26` (sanity findings). The harness docs were already on the
harness remote (`d3c426c`) — only the local clone was stale; fast-forwarded,
and its origin switched from HTTPS (hung on auth) to SSH.

## Phase 1 — Land the execution-verified defect fixes

One commit/PR on `evolution_accepted`. Every item has an executable proof in
docs/14 (appendices B.2, B.11, C.2); do them together because the battery
entries turn the two rule bugs red:

1. `lib/pattern/no_sort_then_at.ex` — replace the two max-direction
   `Enum.max(c, fn -> nil end)` templates with the strict sorter
   `Enum.max(c, &>/2, fn -> nil end)` (docs/12 C1). Update its fix-test
   fixtures (`mix credence.fix_tests` canonicalizes).
2. `lib/pattern/no_sort_for_top_k.ex` — same repair for its
   `sort |> reverse |> at(0)` → `Enum.max` mapping (docs/14 E1).
3. `test/support/equivalence_inputs.ex` — append `[1.0, 1]` and `[1, 2, 2.0]`
   to `term_lists/0`; `[1, 1.0, 1]` and `[2.0, 2]` to `stability_lists/0`
   (docs/12 C2.1). Triage any *other* equivalence test that goes red — by
   construction a new red is a real divergence.
4. **Stdlib sentinel test** — new tiny test asserting
   `Enum.sort([1, 1.0], :desc) === [1.0, 1]` (and friends), with a comment
   naming `no_sort_then_reverse` + `no_double_sort_same_list` as the rules that
   die if an Elixir upgrade changes tie behaviour.
5. **E9 one-liner** — in the `reject_dsl_unfixable` path (`lib/pattern.ex:34-41`
   → `rule_helpers.ex` `dsl_dropped_ranges`), skip `fix_patches` when `check`
   returned `[]`. Scope note: the existing short-circuit already skips DSL-*safe*
   rules; this fix targets the 12 DSL-unsafe rules, where the measured waste is
   2,878 calls per 240 clean files (+30% on their scans).

**Definition of done:** full equivalence suite green (~180 tests, <2 s);
`elixir -e` brute-force snippets from docs/14 B.11 still print `0, 0`;
commit pushed.

**Executed 2026-07-21.** Commit `69aa2ec` — all five items. 179 equivalence
tests green (no rule beyond the two fixed ones diverged on the new entries);
full corpus-free suite 5,269 tests green; brute force 0/65 + 0 on the
`:desc` form. Two additions beyond the letter of the plan: both rules joined
`@verified_dsl_safe` (the DSL meta-gate flags the new `&>/2`'s `/` as a
construct delta — it is capture arity, not division, the gate's documented
exemption), and the sentinel test also pins that `:desc` *reverses* tie
groups rather than keeping them stable. Corpus layers provably unaffected
(check sides unchanged; zero whitelist entries for either rule).

## Phase 2 — Apply the shared-file deltas (by hand, not by the loop)

These are the 6 files moved out of the queue in Phase 0.3. Sequencing matters:

1. **`lib/semantic.ex` — land now, before any semantic rule is reviewed.**
   The delta (from sister commit `5fac292`) turns `match_rules/1` into
   `match_rules/2` (receives `source`) and adds an optional per-rule
   `should_report?(diagnostic, source)` callback. New semantic rules in the
   queue depend on this extension point; without it their tests fail at review
   time and produce spurious FOLLOWUPs.
2. **`lib/dsl_guard.ex` + `lib/rule_helpers.ex` — land now.** Three trivial
   dead-clause deletions/simplifications (sister commit `42866b8`); no
   behaviour change; full suite must stay green.
3. **`test/dsl_safety_classification_test.exs` — land now.** Adds
   `@verified_dsl_safe` entries for `prefer_stdlib_gcd` and
   `no_defp_already_defined_as_def`. Verified safe to pre-apply: the stale-entry
   assertion only fires for rules whose fixtures were actually exercised, so
   entries for not-yet-accepted rules are inert.
4. **`test/credence_test.exs` + `test/fix_showcase_test.exs` — do NOT land
   now.** Both relax `issues == []` to
   `issues == [:no_private_fn_called_from_macro_quote]` — that only passes once
   that rule exists and fires. Record in `shared_deltas.md`: *apply these two
   hunks as a companion commit at the moment stage 1 accepts
   `no_private_fn_called_from_macro_quote`* (the loop's confined-diff gate
   rightly prevents the session itself from touching global tests). If that
   rule is instead rejected, the hunks are dropped and the sister's relaxation
   documented in the rejection entry.

**Definition of done:** `mix test --exclude corpus` green on
`evolution_accepted` with items 1–3 committed; `shared_deltas.md` records the
deferred pair with its trigger condition.

**Executed 2026-07-21.** Commit `3a64b6f` — items 1–3 (lib files copied
wholesale from the sister after re-verifying the diffs matched recon; the two
allowlist entries inserted by hand). Suite green (5,269). Item 4 remains
deferred with its trigger in `shared_deltas.md`.

## Phase 3 — Make the full suite cheap before the drain (docs/13 P1+P2)

**Why now:** each stage-gate run costs ~8.5 min of corpus scan; the drain will
run it ~260+ times (≈37 h). P1+P2 cut the full suite to **~30–60 s** — they pay
for themselves several times over during Phase 4, and again at every future
harness Gate run.

1. **P1 (as revised by docs/14 E4):** put `Task.async_stream` over files
   *inside* the corpus entry tests (primary lever, 12.6× measured); split the
   big-repo entries (elixir_lang ≈4k files, blockscout) into chunked modules
   (secondary). Keep per-entry test names so snapshot failures stay
   per-package.
2. **P2:** compute the per-file `Pattern.analyze` **once** per suite run
   (ETS/`setup_all` cache keyed by path) and let `over_firing`, `fix_safety`,
   and `scope_parity` consume the shared results.
3. **A/B safety check (docs/13 §5.3):** run old and new corpus checks on the
   same tree once; verdicts must be identical.
4. Defer P3 (rule-scoped scan), P4 (AST cache), P5 (harness one-liner), P6 to
   Phase 7 — they optimize the *Gate*, not the drain.

**Alternative if the drain must start immediately:** skip this phase and eat
the 8.5-min gates; nothing else breaks. Recommended not to — Phase 3 is 1–2
days against ~30 saved wall-hours plus every future run.

**Definition of done:** `time mix test` ≤ ~1.5 min on this box, verdicts
A/B-identical, committed.

**Executed 2026-07-22.** Commit `1e6e8c6`. A/B verdict parity confirmed
(1501 tests green, both sides). Measured on this box — **24 schedulers /
~12 physical cores, not the research box's 32** — the full corpus suite went
**516 s / 336% CPU → 251 s / 983% CPU** (2.06×). The ≤ 1.5-min DoD was
mis-calibrated (docs/13 §6 required re-measuring on the real box, and the
projection also underestimated scope-parity's inherent per-file cost);
**~4 min is the honest recalibrated full-suite cost here** — the drain's
per-row gate cost drops accordingly (~9 min → ~4.5 min incl. the corpus-free
phase). Implementation landed as: flat full-corpus `Task.async_stream`
sweeps in `setup_all` with per-entry tests reduced to slice assertions
(docs/14 E4's shape), a run-wide shared analysis cache
(`Credence.Corpus.AnalysisCache`), opposite-direction sweeps instead of
claim/wait (a killed claimant strands waiters — observed), ETS (not
`:persistent_term` — per-put area copies stalled all schedulers) for the
glob memo, and `:infinity` sweep-task timeouts (serial semantics). Further
Gate-facing speed (P3 scoped scans ~seconds, P4 AST cache) stays in
Phase 7.

## Phase 4 — Drain the candidate queue

The machinery is proven (250 decision commits in the first cycle). Scale:
~260 rule bases — 12 new + 5 modified pattern, 174 new + 6 modified semantic,
62 new + 1 modified syntax.

**4.1 Stub pre-pass.**
```bash
cd maintainer_tools/stage_1_promote_fixable_rules
DRY_RUN=1 ./move_unfixable_out.sh   # inspect
./move_unfixable_out.sh             # strips provable check-only stubs → unfixable_unreviewed.md
```

**4.2 Stage 1 — pilot, then batches. ✅ COMPLETE 2026-07-27 16:14.**

Final: **259 rows = 116 accepts / 143 followups / 0 orphans.** `candidates.md`
empty, suite **8058 green**, tree clean, 0 unpushed commits, loop exited on its
own (`done — candidates.md empty`). One console throughout:
`.review_logs/console.log` (append on relaunch — keep it that way).

Operational notes worth keeping for the next cycle:
- The loop passes `--model` to the inner `claude -p` **only** when `CLAUDE_MODEL`
  is set (`review_loop.sh:246`); unset, inner sessions silently inherit the
  launching session's model. Always relaunch as
  `CLAUDE_MODEL=opus setsid nohup ./review_loop.sh 0 >> .review_logs/console.log 2>&1 &`.
- A **weekly account limit** (distinct from a per-model limit) stalls the loop
  with `exit=1` and no verdict; it retries forever and no model switch helps.
  Symptom in the row log: `You've hit your weekly limit`. Only waiting clears it.
- `copy_next_candidate.sh` groups tests by basename, so a same-named rule in
  another phase has its test lines swept into the wrong set (hit once:
  `no_or_in_case_pattern`). Harmless here, but check for same-name pairs first.

*Historical instructions for running the loop (kept for the next cycle):*
```bash
./review_loop.sh 1                          # pilot row; read .review_logs/<base>.log end-to-end
nohup ./review_loop.sh 25 > .review_logs/console_$(date +%F_%H%M).log 2>&1 &
```
- Pilot must show the full chain: COPY → CLASSIFY → SCAN → SESSION → GATE
  (a)(b)(b2)(c)(d) → verdict → PUSH.
- Run in batches of ~25 with a human checkpoint between: skim new `followup.md`
  sections, `git log --oneline -30`, and `wc -l candidates.md` for progress.
  Move to `cap 0` (drain) once two consecutive batches produce no surprises.
- **Progress arithmetic:** each ACCEPT strips its set's lines; queue length is
  the live progress meter.
- **Known review traps to watch for** (from the log/diff recon — the session
  prompt already checks overlap, but these clusters span rows):
  - `no_process_send_after_infinity` / `_literal_infinity` /
    `_with_variable_infinity` — three overlapping rules; the first one's fix is
    **confirmed broken** (returns identical source — flagged independently by
    escalated/20, a classifier-error rationale, and the switch proposal).
  - `no_hallucinated_math_round` vs `no_hallucinated_math_round2`.
  - `no_or_in_case_pattern` exists in **both** semantic and syntax rounds.
  - `fix_string_replace_multi_arity_fn` (pattern) vs
    `no_multi_arity_fn_in_string_replace` (pattern) vs
    `no_string_replace_arity_mismatch` (semantic) — three rules, one territory.
  - `fix_after_or_rescue_in_case` (semantic) vs `no_after_or_rescue_in_case`
    (syntax).
  - Four sister test files carry known compile warnings (unused `defp fix/3`
    default args) that crashed the harness suite twice:
    `fix_undefined_struct_in_pattern_fix_test.exs`,
    `no_exit_two_args_fix_test.exs`, `fix_multiple_default_args_fix_test.exs`,
    `fix_raise_in_keyword_value_fix_test.exs` — the reviewing session should
    clean the warnings as part of those rows.
- Companion commit for the two deferred global-test hunks when
  `no_private_fn_called_from_macro_quote` is decided (see Phase 2.4).

**4.3 Stage 2 — promote/confirm the non-fixable stubs. ✅ COMPLETE (vacuous).**
The stage-2 queue is empty and always was: `unfixable_unreviewed.md` is 0 bytes,
because the 4.1 stub pre-pass moved **zero** rules into it — every candidate
carried a real `fix/1`, so none was a provable check-only stub. There is nothing
to promote or confirm, and `unfixable_confirmed.md` correctly holds only its
header. Re-run the pre-pass at the start of the next cycle rather than assuming
the same result.

*Original instructions, kept for that next cycle:*
`./stage_2_promote_non_fixable/promote_loop.sh` (guard requires `candidates.md`
empty). Verdicts land in `unfixable_confirmed.md`; afterwards distill the
confirmed reasons into `CONTEXT.md` / the harness prompts (that distillation is
explicitly a human step).

**4.4 Stage 3 — resurrect followups. ✅ COMPLETE, by hand rather than by loop.**

The loop was deliberately **not** run. Its job — re-examine each rejected
followup and decide whether a safety switch would rescue it — had already been
done for all 143, one agent per rule with executed probes, cross-reconciled and
adversarially verified. Re-running it would have spawned ~143 fresh sessions to
re-litigate a more rigorous answer. The outputs it would have produced are
instead recorded as:

- **17 rebuild-later** and **9 salvage** rules (docs/18) — the resurrections.
- **`stage3_unfixable.md`, `proposed_assumptions.md` and
  `proposed_rules_requiring_assumptions.md` stay empty**, and that is a finding,
  not an omission: **no rejected rule was blocked on a missing safety switch**.
  The rejections were implementation-dead (82), duplicates (25) or false
  premises (9) — none of them "correct but needs an assumption to be safe".
- **The dangling `fix_process_send_after_infinity` switch proposal
  (`switch_proposals/2`, `default: true`) is DECLINED.** It was filed to rescue
  a rule that cannot exist: all three `Process.send_after(:infinity)` rules key
  on *fabricated* diagnostics, and the real failure mode emits **zero** compiler
  output, so no semantic rule can ever reach it. A switch that gates an
  unreachable rule buys nothing. The failure mode survives as a report-only
  **pattern**-phase rebuild item (docs/18 §Corrections).

*Original instructions, kept for the next cycle:*
`LIST=1 ./stage_3_resurrect_followups/resurrect_loop.sh` to preview, then run.
Switch proposals it emits go to `proposed_assumptions.md` +
`proposed_rules_requiring_assumptions.md`; landing a switch is manual
(`lib/assumptions.ex`, property test, CHANGELOG per `changelog_guard.sh`), then
re-feed those bases through stage 1. Fold the harness's own pending proposal
(Appendix A, switch_proposals/2: `fix_process_send_after_infinity`,
`default: true`, documented no-`:cleanup`-message divergence) into this same
decision batch.

**4.5 Close the cycle.**
- Re-run the corpus whitelist validator if any accepted pattern rule added
  whitelist entries; execute the outstanding action item in
  `maintainer_tools/corpus_whitelist_validator/FIX_LOG.md` (*regenerate
  `accepted_findings.txt`* to drop stale entries).
- CHANGELOG entry summarizing the acceptance cycle (counts per round,
  notable rejects).
- Full `mix test` green; merge `evolution_accepted` → `main` via PR.

**4.6 Work the followup backlog (143 rules). ✅ COMPLETE 2026-07-27.**

Full evidence: **`docs/18-per-rule-verdicts.json`** (source of truth),
**`docs/18-final-143-disposition.md`** (generated prose) and
**`docs/17-failure-mode-catalogue.md`** (what each rule taught us).

Reconciled verdict split — eight rules were relabelled to settle the cases where
the overturn pass and the cross-rule pass disagreed (per-rule reasoning is in
docs/18's `Reconciled / resolved` callouts):

| disposition | n |
|---|---|
| delete — implementation dead | 82 |
| delete — duplicate of a live rule | 25 |
| delete — premise false | 9 |
| rebuild later from catalogue | 17 |
| salvage — small fix | 9 |
| already live (never belonged on the list) | 1 |

135/143 encode a **real** failure mode; **56 are caught by nothing** — not the
compiler, not Credo, not Dialyzer. Those 56 are the actual product of the
evolution cycle. 43 of 143 verdicts were overturned on adversarial review, so
treat any "this is salvageable" instinct with suspicion.

---

**4.6a — Repair the live shipped defects. ✅ DONE.**

Scoped as three bugs. It was **nine defects across seven rules**, every one
verified by executed probe through the real pipeline before and after:

| rule | defect | commit |
|---|---|---|
| `Semantic.NoCaptureAsBitwiseAnd` | `flags & 0xFF` → `Bitwise.band(flags, 0)xFF`; same for `0b`, `0o` and `1_000` | `4abafed` |
| `Syntax.FixDivRem` | a `def` head swallowed into the left operand | `2964ab4` |
| `Syntax.FixDivRem` | rewrote inside string literals | `2964ab4` |
| `Semantic.NoBareReturnInUnless` | early exit deleted, not restructured — silent wrong answer | `86ee66b` |
| `Syntax.FixPythonModulo` | rewrote inside string literals | `9fc30a3` |
| `Syntax.FixPythonModulo` | read `%Name{}` struct literals as modulo | `9fc30a3` |
| `Syntax.FixPythonModulo` | `a * b % 2` regrouped — silent wrong answer | `9fc30a3` |
| `Syntax.FixPythonFloorDiv` / `FixScientificNotation` | rewrote inside string literals | `9fc30a3` (via `SourceMask`) |
| `Semantic.UndefinedFunction` | rewrote a user's own nested-alias call | `891a05c` |

Three findings worth carrying forward:

1. **The string-literal defect was systemic, not local.** Four line-based syntax
   rules regexed over raw bytes with no notion of literals. The fix is
   **`lib/source_mask.ex`** — a same-length shadow with literals, sigils,
   heredocs, char literals and comments blanked. Rules match the shadow and
   splice into the real line at the matched offsets. It is a hand-rolled byte
   scanner rather than `:elixir_tokenizer` *on purpose*: these rules only run on
   source that does not parse, so a tokenizer is exactly what you cannot rely
   on, and this scanner degrades to a missed fix instead of a corrupted string.
2. **Two designed widenings were rejected on adversarial review**, both because
   they converted a loud failure into a silent one. `h * 31 + c & 0xFFFFFFFF`
   became `h * 31 + Bitwise.band(c, 0xFFFFFFFF)` — compiles, returns
   4294967306356 instead of 10356. Python's `&` and `%` bind more loosely than
   Elixir's, so any repair that wraps only the immediate operands regroups the
   expression. Both rules now decline those shapes.
3. **Two existing tests asserted the bug.** `NoBareReturnInUnless`'s discarded
   -branch output was written into the fix tests as the expected result, and
   passed for as long as the defect shipped. `Credence.RuleCase.call_fixed/4`
   now exists so a test can assert what a fix *means*.

**4.6b — The three deferral chains. ✅ DONE.**

1. *Nested-module structs.* `fix_undefined_nested_module_struct` → delete
   (its `match?/1` keys a fabricated message, so it never fires);
   `fix_undefined_struct_in_pattern` **promoted** to rebuild-later. Deleting
   both would have dropped the mode to zero while live
   `FixCyclicStructReference` kept the slot and no-opped on it.
2. *return-in-unless.* Resolved by repairing the live rule (`86ee66b`).
3. *`elif`.* Resolved by widening the live `FixElsifInIfChain` regexes to
   `els?if` (`fe6c2f7`). Verified `elif` was `analyze == []` and a no-op fix
   before, and `elsif` output is byte-identical after.

**4.6c — Delete the dead rules. ✅ DONE** (sister commit `b83d623`): 112
modules + 227 tests, 339 files.

One trap worth recording. **Four of the 116 delete verdicts are not standalone
rules** — `fix_div_rem`, `no_capture_as_bitwise_and`, `prefer_explicit_range_step`
and `undefined_function` are *deltas of modules that already exist on `main`*.
"Reject the delta" means **restore `main`'s version**, not remove the file.
Deleting them outright stripped capability `main` has, and the sister's suite
caught it — four pipeline-integration failures on `n * (n + 1) div 2`, which no
longer had any rule to repair it. docs/18 flags these five same-name pairs, but
only for the reassurance that deleting them cannot harm the *live* repo; the
harm is to the sister.

**4.6d — Fold the salvages into `@qualified_replacements`. ✅ PARTIAL, by design**
(`891a05c`).

Landed: the `parse_qualified_ref` widening `(\w+)` → `(:?\w+)` — load-bearing,
because the compiler writes `:math.round/1` *with* the colon and `\w` cannot
match it — plus six Erlang rows (`:crypto.hex`, `:erlang.warn`, `:queue.empty`,
`:math.min`, `:math.max`, `:math.round`). Verified safe for all 27 pre-existing
rows across 146 message shapes and 213 assertions.

**Not landed, and the reason matters more than the rows do.** The integrator
overturned docs/18's verdicts on two rules and docs/18 was right both times:

- `:persistent_term.get_keys` — the proposed repair emits
  `Enum.map(:persistent_term.get(), &elem(&1, 0))`. That call is **VM-global**
  (27 OTP-internal keys on a stock VM), so paired with its erase loop it
  terminates the BEAM — and the pipeline reports a clean success with zero
  residual diagnostics.
- `Base.hex_encode` — `replace_first_on_line/4` is a substring search and
  `hex_encode` is a prefix of the real `Base.hex_encode32`, which the compiler
  lists in that very diagnostic's did-you-mean block. One broken call became two.

The `Agent`, `NaiveDateTime`, `List.keystore` and `exit/2` rows are **deferred,
not dropped** — sound in themselves, but each needs the call-boundary anchoring
to have settled first, and `exit/2` additionally needs an arity check
`replace_call_on_line/4` does not do. Also refuted: docs/16's proposed
`:drop_erlang_module` handler is unnecessary once the regex is widened.

**4.6e — The 17 rebuild-later + 56 uncaught modes** feed Phase 6. Ranked build
list at the end of docs/17 — but read docs/18 §5.3 first: that list took heavy
damage on review and has not been rewritten.

**Definition of done:** ✅ all queues drained; every base has a decision commit;
4.6a–4.6d applied; the cycle summary is in the CHANGELOG.


## Phase 5 — Triage the harness escalations (parallel with Phase 4)

The full per-file analysis is in **Appendix A**. Record every decision in a new
`maintainer_tools/escalation_ledger.md` (one section per cluster, DROP/ACCEPT/
RE-QUEUE per row). Actions by cluster:

1. **Massive corpus over-fires — drop** (`no_stacktrace_in_term` 810 hits,
   `no_discarded_early_return_guard` 1064, `prefer_guard_over_nil_filter_in_for`
   35). Delete their `.patch`/`.corpus.md`; add the three names to the
   classifier prompt's rejected-over-fire list when Phase 8/H8 lands.
2. **Small over-fires — per-hit review** (rows 137, 150, 162, 199, 221; 1–6
   hits each). If a hit is a true positive: `git apply` the preserved patch in
   the sister + `mix credence.corpus --update-snapshot`, then the rule joins a
   future queue; else drop.
3. **Real bugs surfaced, unfixed:** `PreferSigilCharlist` double-quote escaping
   (row 134) — file as a credence bugfix task (Phase 6 worklist);
   `fix_reduce_with_halt` (144) and `no_trap_exit_without_exit_handler` (55) —
   likely drop after a short look.
4. **Suite-noise victims (rows 2, 100, 119):** root cause is the four warning-
   carrying test files fixed during Phase 4.2 — re-queue these three rows for
   the next harness run.
5. **`:no_lib_change` cluster (11 rows):** no per-row action; feeds two Phase 8
   policy items (test-only-diff handling; known-good rule list —
   `NoPythonMultiReturn` was re-suspected 5×).
6. **behaviour_diverged (13 rows):** no per-row action; all are the
   hallucinated-API class auto-killed by the equivalence probe's
   `before = raise UndefinedFunctionError` asymmetry — Phase 8 LD2 fixes the
   gate, then these rows re-queue.
7. **classifier_errors (52):** investigate the closed-set bug (Phase 8 LD1);
   salvage the two concrete bug reports buried in rationales (row 69:
   `NoRemoteFunctionInGuard` emits invalid `:do =>` syntax; row 90:
   `no_bare_names_in_spec` no-op fix) → Phase 6 worklist.

**Definition of done:** `escalation_ledger.md` covers all 45 escalated files +
13 diverged + the one switch proposal (its `.log`/`.json` pair) with a decision
each; the re-queue list for the next run is explicit.

## Phase 6 — Credence improvement program (C-items, docs/12 order with docs/14 corrections)

Phase 1 already landed C1 (+ the NoSortForTopK extension), C2.1's tie entries,
and the E9 micro-fix. Remaining, in docs/12's sequencing:

| Step | Items | Notes / corrections |
|---|---|---|
| 6.1 | **C5** | Surface the silent patch-drop path: `{rule, :patch_rejected}` in the trace + suppress-or-report the finding (H1's `:reverted` sibling) |
| 6.2 | **C2.1 (rest), C2.2, C6** | The other half of C2.1: add the missing battery dimensions (`maps`, `keyword_lists`, `tuples`, `mixed_numeric`) — C2.2's Map/Keyword mapping and H3's `--dim` inference depend on them; then the mandatory dimension-mapping meta-test; per-rule crash isolation + sandboxed compiles with timeout |
| 6.3 | **C3, C4** | Syntax all-or-nothing + progress guard; Semantic per-pass compile-revert with bisect |
| 6.4 | **C7, C8, C11** | C7 in its E7-revised form: idempotency gate over fix-test fixtures + one Semantic re-pass after Pattern changes (full fixpoint loop deprioritized, ~1.5% incidence). C8 ordering policy doc + explicit priorities for feeds-into pairs. C11 folds — extend with the duplicate clusters the drain surfaces (4.2 watch-list) |
| 6.5 | **C2.3, C2.4, C13, C12, C14** | Seeded StreamData layer; `mix credence.equiv` vacuous-verdict fix (with H3); whitelist budget gate first then evidence-ranked paydown (`prefer_heredoc_for_multi_line_doc` first; `prefer_erlang_float` review — 37 gold findings); alpha-rename generality check; DSL-safety static scan for the 132 unclassified rules. Add the Phase 5 salvage items (PreferSigilCharlist escaping, NoRemoteFunctionInGuard `:do =>`, no_bare_names_in_spec no-op) to this tier's worklist |
| 6.6 | **C9, C10, C15, C16** | Engine hot-path (parse-once, memoized discovery); Issue column + telemetry + per-rule trace API (unblocks H12-adjacent consumers); rule-card template; docs/config debt |
| 6.7 | **C17** | Rule Standard v1 (versioned checklist), stratification audit table, `STATUS.md` mode file shared with the harness. Cheap to *write* early — do the doc as soon as Phase 4 ends so the standard exists before the next generation round; the retrofit sweeps are the later work |
| 6.8 | **C18** | Semantic-mutant sweep of rule implementations: report-only → publish per-rule kill rates → fix the tail → only then a floor gate. Budget for equivalent-mutant triage noise (E6). Every new gate ships with a positive control |

**Definition of done per step:** its meta-gate/oracle is green on the full
(post-drain) rule set, with a positive control proving the gate can fail.

## Phase 7 — Remaining performance items (docs/13, Gate-facing)

Sequencing note: docs/13 §5.1 and docs/15 move 3 say P5 + the syntax/semantic
corpus skip should come *first*. This plan consciously defers them here because
they speed the harness **Gate**, which doesn't run again until Phase 9 — the
drain (Phases 3–4) is what needs speed first. Not an oversight.

1. **P5** (harness one-liner): Gate phase 2 → `mix test --only corpus`.
2. **P3**: `mix credence.corpus --only-rule <Module>` + Gate dispatch on staged
   paths (conservative: anything shared ⇒ full scan). Honest cost range
   10–20 ms/file (docs/14 E3); syntax/semantic-only candidates skip the corpus
   phase entirely.
3. **P4**: on-disk AST cache (`term_to_binary` compressed, keyed by entry pin)
   — makes scoped scans check-bound (~2–8 s).
4. **P6**: only if P1–P4 leave the full sweep as a real bottleneck (unlikely).

**End state (docs/13 §4):** Gate deterministic cost ~20–40 s per candidate.

**Definition of done:** measured Gate corpus phase for a new-pattern-rule
candidate ≤ ~40 s; A/B verdict parity for the scoped scan (docs/13 §5.3).

## Phase 8 — Harness improvement program (H-items + log-derived items)

Work in IMPROVEMENTS.md's sequencing, with docs/14 corrections applied, plus
four items the log analysis surfaced (LD1–LD4). Everything is harness-side
unless noted.

| Order | Items | Notes / corrections |
|---|---|---|
| 8.1 | **H13, H12, LD1, LD2** | H13: dead `:claude_code` preflight branch (one-liner). H12: APPLIED_RULES sidecar contract. **LD1 (new): fix the classifier closed-set** — 44/52 classifier errors were `rule_name_not_in_closed_set`, several for rules that *exist* (`NoRedundantAssignment`, `UndefinedFunction`, `NoBareNamesInSpec`, `NonGroupedClauses`) — closed-set construction or name normalization is broken and is silently discarding valid BUGFIX lanes. **LD2 (new): equivalence-probe vacuous class** — treat `before = {:raise, UndefinedFunctionError}` (and harness-frame-only term diffs, cf. row 33) as vacuously passable: hallucinated-API repairs are the harness's *most productive rule class* (98/155 commits) yet the probe auto-kills them (13/13 diverged rows) |
| 8.2 | **H4 (scoped), H1.1 (as ratchet)** | H4 only for `mark_equivalence_*` rules + syntax/semantic + hollow-test insurance (E5: the equivalence precheck already kills both mutant classes for ordinary pattern rules). H1.1 as an accepted-gold-findings **ratchet**, never zero-assert (E2: 25% of golds carry findings) |
| 8.3 | **H2, H1.2, H5, H19** | H2 with the cheap standalone runner (E2b: 0.6 s/subject for pure-OTP). H1.2 per-candidate (1.1 s full-gold scan) — diffed against the gold-findings snapshot per 8.2's ratchet, **never** the refuted any-rewrite-rejects form. H5 Gate tests + timeouts, with positive controls. H19 flake ledger + stability re-run |
| 8.4 | **H7 (span-overlap), H8, H9, LD3, LD4** | H7's rescue = diff-span non-overlap (E8; the covers-rerun variant is non-discriminating). H8 verdict memory + positive exemplars — seed its rejected-over-fire list with Phase 5's three dropped rules. H9 environmental-failure triage (would have saved rows 2/100/119). **LD3 (new): BUGFIX test-only-diff policy** — 11 `:no_lib_change` escalations were agents correctly concluding "rule already handles it"; let the Gate accept regression-test-only diffs on BUGFIX rows (or add a distinct `verified_good` outcome). **LD4 (new): known-good rule list** — classifier re-suspected `NoPythonMultiReturn` 5×; a per-rule verified-good marker (fed from LD3 outcomes) stops the churn |
| 8.5 | **H6, H3** | Bounded auto-retry on corpus rejects + auto-repin own-rule `gone` lines; equiv reach extension (with C2.4's vacuous-verdict fix) |
| 8.6 | **H10, H11, H14–H17, H18** | Provenance birth certificates (+ record which gates ran in what mode); `mix cev.report` (+ difficulty metadata); push-failure breaker; dead-code sweep; solve-prompt/workspace-deps alignment; spine unit tests; spec-entailment judge |
| 8.7 | **Addendum 2** | Gate dispatch by staged paths — lands with Phase 7's P3/P5 |

**Definition of done per item:** IMPROVEMENTS.md's own acceptance notes, plus
(for every new gate) a positive control that has been seen red on purpose.

## Phase 9 — The next evolution run

1. **Archive the current run's logs first** — `cev.reset` deletes them and
   Phase 5 depends on them (`cp -r var/run/logs var/archive/run-2026-07-06/`
   or similar, committed nowhere but kept on disk).
2. **Branch strategy.** After Phase 4's merge to `main`: reset the sister's
   `evolution` branch onto the new `main` (fresh start, accepted rules now in
   the baseline) and keep the harness pointed at the sister
   (`CEV_CREDENCE_CLONE=/home/kamil/projects/credence_evolution`, or the
   config's `credence_clone` key — note the commented example at
   `config/config.exs:167` points at a stale `/home/car/...` path from another
   machine; rewrite it, don't just uncomment) so this accepting repo never
   needs branch flips again. Preflight requires: sister on `evolution`, clean tree,
   push-able, **full suite green at HEAD**.
3. **Re-queue list** (from Phase 5): rows 2, 100, 119 (suite noise — fixed),
   the 13 behaviour-diverged rows (after LD2), rows 6/169/225 (scaffold
   give-ups worth one retry), and the classifier-error rows freed by LD1.
   Plus the 105 remaining pass-5 rows.
4. **Infra:** address the transient tail before a long run — 16 classifier
   timeouts/closed + 5 quota-429s on the Mimo endpoint, 3 implementer
   timeouts. Raise quota or add backoff headroom.
5. Start: `CEV_RUN=1 mix run --no-halt` after `mix cev.preflight` passes; watch
   `var/run/rows.jsonl` and the lane dirs; `mix cev.usage` for spend.

**Definition of done:** preflight green with the new clone target; run resumes
pass 5 (or starts pass 6) with order-8.1/8.2 items active.

---

## Appendix A — Harness log triage (full detail)

Counts: committed 155 · no_action 213 · escalated 45 (29 logs + 8
`.corpus.md` + 8 `.patch`) · classifier_errors 52 · transient 26 ·
behaviour_diverged 13 · switch_proposals 2 files (1 proposal) · duplicate 0 ·
too_slow 0. Logs
are per-attempt, not per-row (153/155 committed rows also have a no_action log
from another pass — normal).

| Cluster | Files (in `var/run/logs/`) | Decision needed |
|---|---|---|
| Massive corpus over-fires | escalated/48 (`no_stacktrace_in_term`, **810** hits), 73 (`no_discarded_early_return_guard`, **1064**), 124 (`prefer_guard_over_nil_filter_in_for`, 35) | Drop all three; they fire on ubiquitous idiomatic code. Feed names to the classifier's rejected list (H8) |
| Small corpus over-fires | escalated/199 (`no_negative_step_in_string_slice`, 6), 150 (`fix_ets_bare_concurrency_option`, 4), 221 (`prefer_float_cast_for_dynamic_multiplicand`, 4), 137 (`no_missing_state_key_in_genserver`, 1), 162 (`no_reraise_after_atom_catches`, 1) | Per-hit review; each has a maintainer-facing `.corpus.md` with exact ACCEPT/DROP instructions and a preserved `.patch` |
| Implementer gave up — suite noise | escalated/2, 100, 119 | Root cause is pre-existing warnings in 4 sister test files (see Phase 4.2) + a `NoKeywordIfBareInTuple.fix/1` crash; fix in review, re-queue rows |
| Implementer gave up — scaffold/hard | escalated/6, 169, 225 (placeholders never made green; 80-turn cap) | One retry each next run; drop on second failure |
| Real bugs surfaced, unfixed | escalated/134 (`PreferSigilCharlist` `~c"say \"hi\""` escaping), 144 (`fix_reduce_with_halt` equivalence red), 55 (`no_trap_exit_without_exit_handler` overlap) | 134 → Phase 6 bugfix; 144/55 likely drop |
| `:no_lib_change` (rule already correct) | escalated/20, 40, 50, 59, 78, 82, 95, 97, 123, 145, 178 | Policy items LD3/LD4; `NoPythonMultiReturn` re-suspected ×5 |
| Unproven bugfix | escalated/116 (`mutation_no_effect` on `NoPostfixIfExpression`) | Drop, or re-run demanding a failing-first test |
| Equivalence probe vs hallucinated-API class | behaviour_diverged/1, 7, 12, 18, 31, 33, 105, 106, 107, 162, 164, 185, 205 | Gate design fix LD2, then re-queue — all 13 are `before = raise UndefinedFunctionError` by construction (33 is the harness-frame variant) |
| Closed-set rejections | classifier_errors: 44/52 `rule_name_not_in_closed_set` (incl. rules that exist in-repo); 6 `decision_not_offered`; 1 `bad_decision`; 1 `does_not_parse` | LD1 investigation; salvage rows 69 + 90 rationales (concrete rule bugs) |
| Switch proposal | switch_proposals/2.json — `fix_process_send_after_infinity` (`default: true`; divergence: no `:cleanup` message ever arrives) | Decide with Phase 4.4's stage-3 batch; the underlying rule's no-op fix is confirmed broken |
| Transient/infra | transient/26: 11 classifier `:timeout`, 7 `:closed`, 5 HTTP 429, 3 implementer 3600-s kills | No per-row action; Phase 9.4 capacity fixes |

## Appendix B — Working conventions for the whole program

- **One decision, one commit** — the stage loops already enforce
  `<base>: accepted|promoted|followup|resurrected|confirmed unfixable`; manual
  phases follow suit (`C5: patch-drop surfaced`, `H13: preflight branch fix`).
- **Every loop/batch runs under `nohup … | tee`** into the stage's
  `.review_logs/console_<date>.log`; per-row transcripts are already written by
  the wrappers. Nothing runs unlogged.
- **Ledgers over memory:** `escalation_ledger.md` (Phase 5),
  `shared_deltas.md` (Phase 2), `followup.md`/`unfixable_confirmed.md` (the
  loops), C18's mutant ledger, H19's flake ledger. A decision that isn't in a
  ledger didn't happen.
- **`STATUS.md` mode file** (C17.3) at the credence repo root once Phase 6.7
  lands: says whether the pair is *producing rules* or *catching up on a
  standard bump*, and which plan phase is active.
- **Gates ship with positive controls** (docs/12 amendment): a gate nobody has
  seen red is unverified.
- **When numbers disagree** between docs/13 §1 and docs/14 C.4 (e.g. 8 vs
  19 ms/file), plan with the range — measured VM-warmth variance.
- **Never run plain `mix test` outside this repo's warm-corpus checkout**
  (docs/15 gotcha #1) — and after Phase 3, a plain `mix test` here is cheap
  anyway.
