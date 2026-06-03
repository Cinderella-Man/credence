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
Precondition: tree clean except `docs/_verdict` (abort if dirty). Args: `[cap]` (default:
run until `candidates.md` empty) `[wait_min]` (default 2). Env: `CLAUDE_MODEL`, `SISTER`.
`set -uo pipefail`.

Per iteration:
1. `candidates.md` empty → "done", break.
2. `copy_next_candidate.sh`; derive **kind** from the anchor path (`pattern|semantic|syntax`).
3. `rm -f docs/_verdict`; run the sandboxed session (below) with the prompt + a trailing
   line naming the anchor and its kind.
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
No git/rm/cp/network/`mix deps`. (Read reaches the sister repo by absolute path for
shared-file bring-over.)

## Agent protocol (`review_set_prompt.md`) — per-kind bar
- Follow `docs/02_rule-review-process.md`; work **only** the injected set; **no** scratch
  files (`/tmp` or throwaway tests). Verify language semantics with inline `elixir -e`;
  verify rule behaviour by asserting it in the rule's real test and running it.
- Run `mix test` first; bring any needed shared-file change over from the sister repo via
  Read+Write (minimal).
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
