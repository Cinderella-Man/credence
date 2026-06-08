# Plan: autonomous fixable-rule review loop

## Context
`docs/candidates.md` (renamed from `pr_diff.md`) is a queue of AI-written rule "sets"
(rule file + test file(s)) from the `evolution` branch awaiting review per
`docs/02_rule-review-process.md`. We automate the per-set review with a loop that drives
a fresh headless Claude session per candidate. Decided constraints:

- The **LLM is sandboxed**: it edits files and runs tests only — **no git**. A wrapper
  script owns **all** git (commit + push) and all list edits. The session's only output
  channel is a verdict file.
- **Only fixable rules are accepted.** The agent investigates → narrows → tries to build a
  real safe fix (it may *make* a rule fixable). If no safe fix exists, the rule is dropped
  and recorded in `followup.md`.
- The loop handles **all three rule kinds** (pattern, semantic, syntax), dispatching by
  the anchor path. Each kind has its own gate and acceptance bar (below).

## Three lists (rename `pr_diff.md`)
- `docs/candidates.md` — rules to verify (the work queue; renamed from `pr_diff.md`).
- `docs/unfixable.md` — deterministic check-only **pattern** stubs, auto-filtered.
- `docs/followup.md` — agent couldn't safely fix / inconclusive / non-loopable items.

## Rule kinds (the list, by category)
| Kind | Count in list | Shape | Test split convention | Coupling |
|---|---|---|---|---|
| pattern (`lib/pattern/`) | 129 | `fix_patches/2` | `_check_test` + `_fix_test` | none |
| semantic (`lib/semantic/`) | 3 | `fix(source, %{diagnostic})` | `*_check_test` + ≥1 `*_fix_test` variant | none (`lib/semantic.ex` unchanged) |
| syntax (`lib/syntax/`) | 4 | `analyze/1` + `fix/1` (broken→valid fixer) | `_analyze_test` + `_fix_test`, or single `_test` | none — all 4 target **unparseable** code (the syntax phase's actual job) |

All three kinds now flow through the loop with no special obstacle: there is **no
`lib/syntax.ex` change** and no cross-phase coupling left to untangle.

**The 2 misfiled syntax rules are already done.** `fix_module_attr_outside_module` and
`fix_typespec_literal_list` targeted code that **parses**, so by the phase taxonomy (syntax =
won't parse; semantic = compiler diagnostic; pattern = AST-detectable) they were **pattern
rules**, not syntax. They have been **reimplemented as AST-based pattern rules**
(`no_attr_before_defmodule`, `no_literal_list_typespec`), each narrowed to its safe core with
split check/fix tests — see `docs/followup.md`. Consequently the `evolution` `lib/syntax.ex`
"run on parseable source" runner change is **rejected**: it was a workaround for this
misclassification and shipped a confirmed masking regression (a structural syntax issue made
`analyze/2` suppress all semantic+pattern findings). `lib/syntax.ex` stays byte-identical, and
only the 4 genuinely-unparseable fixers remain as syntax candidates.

## Scripts (descriptive, effect-based names)
1. **`copy_next_candidate.sh`** (rename of `get_set.sh`) — copy the next set (sister repo →
   tree). Points at `candidates.md`. **Set-grouping = prefix match `<base>*_test.exs`** with
   a *longest-rule-base-prefix-wins* guard (a test belongs to the rule whose base is the
   longest rule-base prefix of the filename) so multi-variant tests are captured and
   `no_filter` can't steal `no_filter_then_map`'s tests.
2. **`remove_from_list_keep_files.sh`** (new) — ACCEPT mechanic: strip the set's lines from
   `candidates.md`, **keep** files.
3. **`remove_from_list_revert_files.sh`** (rename of `drop_set.sh`) — REJECT mechanic: revert
   the set's files **and** strip its lines from `candidates.md`.
4. **`move_unfixable_out.sh`** (new) — one-time pre-pass, **pattern-only**: move every
   pattern rule whose entire `fix_patches/2` is a constant `[]` to `docs/unfixable.md`; one
   commit + push. (Semantic/syntax have no check-only stubs, so nothing to pre-filter.)
5. **`review_loop.sh`** (new) — the orchestrator.
6. **`scripts/review_set_prompt.md`** (new) — the agent protocol (per-kind sections).

## `review_loop.sh`
Precondition: **self-healing** (Decision 6) — an in-set-only dirty tree (+ stale
`docs/_verdict`) is reverted and the candidate retried; only *broader/unexpected* dirtiness
aborts. Args: `[cap]` (default: run until `candidates.md` empty) `[wait_min]` (default 2).
Env: `CLAUDE_MODEL`, `SISTER`. `set -uo pipefail`.

Per iteration:
1. `candidates.md` empty → "done", break.
2. Read the top anchor. **Orphan check** (Decision 8): if it's a test file with no owning
   rule → followup-route, commit, continue (no session). Else `copy_next_candidate.sh`
   (pure copy) and derive **kind** from the anchor path (`pattern|semantic|syntax`).
3. **Classify** the copied paths via `git status --porcelain` + `git diff` (greenfield `??`
   vs delta ` M`/`MM`) and write the **set briefing** (files, new-vs-modified, diff for
   modified). `rm -f docs/_verdict`; run the sandboxed session (below) with the
   greenfield-or-delta prompt section + the briefing + a trailing line naming the anchor and
   its kind.
4. Read `docs/_verdict`.
5. **If `ACCEPT`** → independent per-kind re-verify gate:
   - **all kinds:** full `mix test` green; the agent's fix is real (not a constant-`[]`
     stub for pattern);
   - **pattern:** exactly `<base>_check_test.exs` + `<base>_fix_test.exs` exist (wrapper
     deletes a superseded single `<base>_test.exs`);
   - **semantic:** ≥1 `<base>*_check_test.exs` + ≥1 `<base>*_fix_test.exs`;
   - **syntax:** `<base>_analyze_test.exs` + `<base>_fix_test.exs`, or a single `<base>_test.exs`.
   Pass → `remove_from_list_keep_files.sh`; `git add` **explicit paths**; commit
   `<rule>: accepted`; **push**.
6. **Else** (`FOLLOWUP`, failed gate, or missing/garbage `_verdict`) → one path:
   `remove_from_list_revert_files.sh`; append a `followup.md` entry (rule, files, reason,
   date); commit `<rule>: followup — <reason>`; **push**. *(Only a verified ACCEPT exits to
   "accepted"; everything else → followup, so a set never re-fetches in a loop.)*
7. `rm -f docs/_verdict`; sleep `wait_min` unless last / list empty.

## LLM sandbox (no git)
```
claude -p "$prompt" --permission-mode acceptEdits \
  --allowedTools "Read Edit Write Grep Glob Bash(mix test:*) Bash(mix format:*) Bash(elixir:*)" \
  [--model "$CLAUDE_MODEL"]
```
No git/rm/cp/network/`mix deps`. The agent edits/creates **only** the set's rule file + its
`<base>*_test.exs`; it needs no sister access (the delta, if any, is in the briefing — see
Decision 2: shared-file resolution is out of scope).

## Agent protocol (`review_set_prompt.md`) — per-kind bar
- Follow `docs/02_rule-review-process.md`; work **only** the injected set; **no** scratch
  files (`/tmp` or throwaway tests). Verify language semantics with inline `elixir -e`;
  verify rule behaviour by asserting it in the rule's real test and running it.
- Run `mix test` first. **Shared-file changes are out of scope** (Decision 2) — touch nothing
  outside the set's rule + `<base>*_test.exs`; if a fix would require it, write `FOLLOWUP`.
- **Greenfield vs delta** (the wrapper picks the section from the briefing): for a *delta*,
  the rule is already live — judge **only** evolution's change shown in the briefing; a
  reject just leaves the accepted version in place.
- **Acceptance bar by kind:**
  - **pattern:** behaviour-preserving — same output for **every** input (the doc-02 bar);
    real `fix_patches`; tests split `_check`+`_fix`.
  - **semantic:** the fix correctly resolves the flagged diagnostic without breaking
    otherwise-valid code; tests = check + ≥1 fix variant.
  - **syntax:** transforms the target **malformed** code into a valid equivalent and never
    misfires on valid code; tests = analyze+fix or single.
  - If no safe fix exists even for a narrow core (or it changes a value's **type**) → don't
    force it.
- **Last action:** write `docs/_verdict` with exactly `ACCEPT` or `FOLLOWUP: <reason>`.
  Never run git.

## Sequencing (follow `candidates.md` order)
Every kind goes through the loop the same way — no prerequisites, no special-casing.
0. **Done already** — the 2 misfiled syntax rules, reimplemented as the pattern rules
   `no_attr_before_defmodule` and `no_literal_list_typespec` (out of the queue; full suite
   green). `lib/syntax.ex` left untouched.
1. **Pattern (129)** — the bulk; fully independent. Pre-pass (`move_unfixable_out.sh`) first,
   then loop.
2. **Semantic (3)** — independent (dispatcher unchanged); loop with the semantic gate/bar.
3. **Syntax (4)** — loop the genuinely-unparseable fixers (`fix_div_rem`,
   `fix_scientific_notation`, `fix_python_floor_div`, `fix_python_augmented_assignment`) on the
   existing runner; no `lib/syntax.ex` change, no prerequisite.
4. **Global suites** (`test/credence_test`, `debug_ast_test`, `fix_examples_test`,
   `fix_showcase_test`) — stay on followup; reconcile **last**, once the rule set has settled.
5. **Orphan test entries** (no matching rule left in the list) → triage to followup at the
   end of each phase.

## Files
- **New:** `scripts/remove_from_list_keep_files.sh`, `scripts/move_unfixable_out.sh`,
  `scripts/review_loop.sh`, `scripts/review_set_prompt.md`, `docs/unfixable.md`,
  `docs/followup.md` (exists); `.gitignore` += `docs/_verdict`.
- **Rename:** `get_set.sh` → `copy_next_candidate.sh`; `drop_set.sh` →
  `remove_from_list_revert_files.sh`; `docs/pr_diff.md` → `docs/candidates.md`.
- **Edit:** renamed scripts (point at `candidates.md`; prefix-match grouping);
  `docs/02_rule-review-process.md` (`pr_diff.md` → `candidates.md` references).

## Verification
1. `move_unfixable_out.sh`: pattern check-only stubs moved to `unfixable.md`; one push.
2. `review_loop.sh 1 0` on a pattern candidate → accepted commit (rule + split tests, full
   `mix test` green) or followup commit; tree clean; pushed.
3. A semantic candidate (e.g. `unused_variable`) → captured with all its `*_fix_test`
   variants by the prefix-match; gate passes on check + ≥1 fix variant.
4. Force a red test on an ACCEPT → gate fails → followup path fires.
5. Reclassified rules (already verified): `no_attr_before_defmodule` + `no_literal_list_typespec`
   flag + fix their cases as pattern rules, `Credence.analyze` still reports co-located
   pattern/semantic issues (no masking), and `lib/syntax.ex` is byte-identical to the accepted
   branch. Full suite green (3213 tests).
6. Run to empty → "done"; `git log` one commit per set; `unfixable.md`/`followup.md`
   populated; `mix test` green on the branch tip.

## Open / confirm-if-wrong
- **Per-kind dispatch lives in the wrapper** (kind derived from anchor path); the agent gets
  a kind-specific prompt section. Trivial and deterministic.
- **`mix format`** kept in the allow-list so the agent can format before asserting exact test
  strings. Drop it if the wrapper formats instead.

## Decisions locked in review (2026-06-04)
Resolved while grilling the plan against the real repo state. These override any
contradicting wording above.

1. **Two candidate shapes — delta vs greenfield.** `candidates.md` mixes brand-new rules
   with **deltas to already-shipped rules** (e.g. `undefined_function`, `unused_variable`,
   `fix_div_rem` are byte-identical to `main` on this branch; `evolution` only *modifies*
   them). `copy_next_candidate.sh` stays a **pure copy mechanic**. `review_loop.sh` runs
   `git status --porcelain` + `git diff` **after** the copy: `??` ⇒ greenfield, ` M`/`MM` ⇒
   delta. It writes a **set briefing** (files, new-vs-modified, and the `git diff` for
   modified paths) that the agent reads, and selects the matching prompt section. The agent
   never runs git — the diff arrives as text.
2. **Shared files are out of scope.** `candidates.md` contains only `lib/<kind>/` +
   `test/<kind>/` paths, and `evolution` leaves `lib/credence.ex`, `lib/pattern.ex`,
   `lib/semantic.ex`, `lib/rule_helpers.ex`, `mix.exs` byte-identical to `main`. There is no
   coupling. Delete the "bring shared-file change over" instruction from the prompt; leave a
   one-line note that shared-file resolution was done manually and is out of scope. The agent
   may edit/create **only** the set's rule file + its `<base>*_test.exs`; a need to touch
   anything else ⇒ automatic `FOLLOWUP`.
3. **Rules auto-register.** `RuleHelpers.discover_rules/1` scans
   `Application.spec(:credence, :modules)` for behaviour-implementers. Dropping a compiled
   rule file is enough — no registry edit, no "silently unregistered" failure mode.
4. **`unfixable_stub?` is one kind-dispatched predicate, used twice.** Strict and light
   (only the provably-dead; the agent makes every non-trivial call in the loop):
   - pattern → single-clause `def fix_patches(...), do: []` (51 of 129 candidates today);
   - semantic → **every** `fix/2` clause returns `source` verbatim (0 today);
   - syntax → **every** `fix/1` clause returns `source` verbatim (0 today).
   Used as the **pre-pass filter** (against the sister) and as the **accept-gate "fix is
   real" guard** (against the in-tree accepted file). Conservative: never abandons a
   salvageable rule silently; ambiguous cases fall through to the loop.
5. **Pre-pass is list-only bookkeeping, all kinds.** `move_unfixable_out.sh` reads the sister
   to apply `unfixable_stub?`, then strips the rule line **and** its prefix-grouped
   `<base>*_test.exs` line(s) from `candidates.md` and records both in `unfixable.md`
   (paths, per-kind reason, date). No files enter the accepted branch. One commit + push.
6. **Self-healing loop.** At startup / top of each iteration, if the tree is dirty: when the
   dirtiness is **confined to the current top candidate's set paths** (+ `docs/_verdict`),
   revert those + `rm -f docs/_verdict` and **re-process that candidate** (the list is only
   mutated on a *completed* outcome, so the top entry is still correct). Any **broader/
   unexpected** dirtiness ⇒ abort for a human.
7. **Role split at the gate.** *Agent owns test shape* (normalize to the kind's form: pattern
   ⇒ exactly `{_check,_fix}` — split a single, complete a partial; semantic ⇒ check + ≥1 fix
   variant; syntax ⇒ analyze+fix or single). *Wrapper owns verification + destructive ops*:
   full `mix test` green (always — catches auto-discovered end-to-end regressions, ~12 s
   warm) → confined diff (only set paths changed) → `unfixable_stub?` false on the accepted
   file → kind-specific test shape present (pattern: delete any superseded single
   `<base>_test.exs`). Any failure ⇒ followup path, never a partial accept.
8. **Orphan/global tests skip the agent.** A set whose **anchor is a test file with no owning
   rule** (`test/<kind>/X_test.exs` with no `lib/<kind>/X.ex` in tree or sister — e.g.
   `debug_ast_test.exs`, the global suites) is routed straight to `followup.md` ("orphan
   test — no owning rule", date), stripped from `candidates.md`, committed; no session spawned.

## Implementation task list
Ordered; each task is independently testable. Renames first (mechanical), then the unfixable
pre-pass, then the loop, then the prompt, then end-to-end verification.

### A. Renames & list rename (mechanical, one commit)
- [ ] `git mv docs/pr_diff.md docs/candidates.md`.
- [ ] `git mv scripts/get_set.sh scripts/copy_next_candidate.sh`;
      `git mv scripts/drop_set.sh scripts/remove_from_list_revert_files.sh`.
- [ ] Repoint both renamed scripts at `docs/candidates.md` (the `PRDIFF=` var).
- [ ] Update `docs/02_rule-review-process.md`: every `pr_diff.md` → `candidates.md`.
- [ ] `.gitignore` += `docs/_verdict`.
- [ ] Create empty `docs/unfixable.md` with a header (parallel to `followup.md`).

### B. Set-grouping fix (in `copy_next_candidate.sh`)
- [ ] Replace the current **exact-basename** test match (fixed suffix set) with
      **longest-rule-base-prefix-wins** `<base>*_test.exs` grouping, so multi-variant tests
      (`undefined_function_*_fix_test.exs`) are captured and `no_filter` can't steal
      `no_filter_then_map`'s tests. Keep it a **pure copy** — no git, no list edits, no
      status/diff (that moves to the loop).
- [ ] Unit-check grouping on: `undefined_function` (6 variants), `no_filter` vs
      `no_filter_then_map`, a single-`_test.exs` rule, a `_check`+`_fix` pair.

### C. `unfixable_stub?` predicate (shared shell function, sourced by pre-pass + loop)
- [ ] Implement kind dispatch on anchor path → predicate from Decision 4. Pattern: 1 clause
      `do: []`. Semantic/syntax: **all** `fix` clauses return `source` verbatim.
- [ ] Verify against sister: pattern ⇒ 51 hits; semantic/syntax ⇒ 0; no false positives on
      `unused_variable` (has `-> source` fallbacks but a real path).

### D. `move_unfixable_out.sh` (pre-pass, list-only)
- [ ] For each candidate rule line, dispatch by kind, read the **sister** file, apply
      `unfixable_stub?`. On hit: strip rule + prefix-grouped test line(s) from
      `candidates.md`; append `unfixable.md` entry (paths, reason, date).
- [ ] One commit (`move N check-only stubs to unfixable`) + push. Idempotent (re-run = no-op).
- [ ] Verify: queue drops by ~102 lines (51 rules + their tests); `mix test` still green;
      no stub remains in `candidates.md`.

### E. `remove_from_list_keep_files.sh` (new, ACCEPT mechanic)
- [ ] Strip the set's lines (rule + grouped tests, incl. a deleted superseded single) from
      `candidates.md`; **keep** files. No file reverts. (Mirror of the revert script's list
      logic.)

### F. `review_loop.sh` (orchestrator)
- [ ] Args `[cap]` `[wait_min=2]`; env `CLAUDE_MODEL`, `SISTER`; `set -uo pipefail`.
- [ ] **Startup/iteration self-heal** (Decision 6): clean an in-set-only dirty tree + stale
      `_verdict` and retry; abort on broader dirtiness.
- [ ] Loop: empty list ⇒ "done". Else read top anchor → **orphan check** (Decision 8): if
      anchor is a test with no owning rule ⇒ followup-route, commit, continue (no session).
- [ ] `copy_next_candidate.sh`; derive **kind** from anchor path.
- [ ] **Classify** copied paths via `git status --porcelain` + `git diff`; write the **set
      briefing** (files, new-vs-modified, diff for modified). Greenfield vs delta selects the
      prompt section.
- [ ] `rm -f docs/_verdict`; run the sandboxed session (prompt + briefing + trailing
      anchor/kind line). Read `docs/_verdict`.
- [ ] **ACCEPT** ⇒ run the gate (Decision 7). Pass ⇒ `remove_from_list_keep_files.sh`;
      `git add` **explicit set paths** (incl. test deletions); commit `<rule>: accepted`;
      push. Fail ⇒ followup path.
- [ ] **Else / failed gate / missing-garbage verdict** ⇒ `remove_from_list_revert_files.sh`;
      append `followup.md` (rule, files, reason, date); commit `<rule>: followup — <reason>`;
      push. (Only a verified ACCEPT exits to "accepted"; everything else ⇒ followup, so a set
      never re-fetches in a loop.)
- [ ] `rm -f docs/_verdict`; sleep `wait_min` unless last / list empty.
- [ ] Sandbox invocation: `claude -p` `--permission-mode acceptEdits`
      `--allowedTools "Read Edit Write Grep Glob Bash(mix test:*) Bash(mix format:*)
      Bash(elixir:*)"` `[--model "$CLAUDE_MODEL"]`. **Residual risk (note, low priority):**
      `Bash(elixir:*)` can `System.cmd("git", …)`; the prompt forbids git and the wrapper is
      the source of truth (explicit-path staging + confined-diff gate), so a stray agent git
      op is at worst caught as unexpected dirtiness on the next iteration.

### G. `scripts/review_set_prompt.md` (agent protocol)
- [ ] Follow `docs/02_rule-review-process.md`; work **only** the injected set; **no** scratch
      files. Run `mix test` first. Verify semantics with inline `elixir -e`; verify rule
      behaviour by asserting in the rule's real test and running it.
- [ ] **Remove** the shared-file bring-over line; add the out-of-scope note (Decision 2).
- [ ] **Greenfield** section vs **delta** section (selected by the wrapper from the briefing):
      delta = "this rule is already live; judge **only** evolution's change shown in the
      briefing; reject ⇒ wrapper restores the accepted version."
- [ ] Per-kind acceptance bar + required test shape (pattern exact `{_check,_fix}`; semantic
      check + ≥1 fix variant; syntax analyze+fix or single). If no safe fix even for a narrow
      core (or it changes a value's **type**) ⇒ don't force it.
- [ ] **Last action:** write `docs/_verdict` with exactly `ACCEPT` or `FOLLOWUP: <reason>`.
      Never run git.

### H. End-to-end verification (the existing "Verification" section)
- [ ] Run B–G checks above, then the 6 scenarios in **Verification**: pre-pass; a pattern
      ACCEPT; a semantic multi-variant ACCEPT; a forced-red gate→followup; a **delta**
      candidate (e.g. `undefined_function`) reviewed as a diff; run-to-empty ⇒ "done", one
      commit per set, lists populated, `mix test` green on tip.
