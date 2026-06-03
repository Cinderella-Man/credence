# Plan: autonomous fixable-rule review loop

## Context
`docs/pr_diff.md` is a queue of AI-written rule "sets" (rule file + test file(s)) from the
`evolution` branch awaiting review per `docs/02_rule-review-process.md`. We automate the
per-set review with a loop that drives a fresh headless Claude session per candidate.
Hard constraints decided during design:

- The **LLM is sandboxed**: it may edit files and run tests only — **no git**. A wrapper
  script owns **all** git (commit + push) and all list edits. The session's only output
  channel is a verdict file.
- **Only fixable rules are accepted.** The agent must investigate → narrow → try to build a
  real safe fix (even for a tiny core); it may *make* a rule fixable. If no safe fix exists
  (e.g. a type-change like `String.to_charlist` int → `String.at` string), the rule is
  dropped and recorded.
- Deterministically check-only rules never reach the agent — a pre-pass filters them out.

## Three lists (rename `pr_diff.md`)
- `docs/candidates.md` — fixable rules to verify (the work queue; renamed from `pr_diff.md`).
- `docs/unfixable.md` — deterministic check-only stubs, auto-filtered (no agent).
- `docs/followup.md` — agent investigated but couldn't safely fix, or inconclusive runs
  (case-by-case, for human review).

## Scripts (descriptive, effect-based names)
1. **`copy_next_candidate.sh`** (rename of `get_set.sh`) — copy the next set (sister repo →
   tree). Does not touch any list. Points at `candidates.md`.
2. **`remove_from_list_keep_files.sh`** (new) — ACCEPT mechanic: strip the set's lines from
   `candidates.md`, **keep** the working-tree files. (= `drop_set` minus the revert.)
3. **`remove_from_list_revert_files.sh`** (rename of `drop_set.sh`) — REJECT mechanic: revert
   the set's working-tree files **and** strip its lines from `candidates.md`.
4. **`move_unfixable_out.sh`** (new) — one-time pre-pass. For each set in `candidates.md`,
   read its anchor rule from the sister repo and classify (below); move every
   deterministically-unfixable set's lines from `candidates.md` to `docs/unfixable.md`; one
   commit + push (`prefilter: moved N check-only rules to unfixable.md`).
5. **`review_loop.sh`** (new) — the orchestrator.
6. **`scripts/review_set_prompt.md`** (new) — the agent protocol.

## Deterministic unfixable classifier (conservative)
A rule is unfixable iff its **entire** `fix_patches/2` implementation is a single constant
clause returning `[]` (e.g. `def fix_patches(_ast, _opts), do: []`). Any rule with a real or
conditional fix head stays a candidate. (Today: 52 of 180 evolution rules match; evolution
has no `fixable?/0` and no `fix/2`, so `fix_patches` is the only signal.) grep-based, in
`move_unfixable_out.sh`.

## `review_loop.sh`
Precondition: working tree clean except `docs/_verdict` (abort if dirty — never sweep
unrelated WIP). Args: `[cap]` (default: run until `candidates.md` empty) `[wait_min]`
(default 2). Env: `CLAUDE_MODEL`, `SISTER` (forwarded). `set -uo pipefail` (not `-e`).

Per iteration:
1. `candidates.md` empty → print "done", break.
2. `copy_next_candidate.sh`.
3. `rm -f docs/_verdict`; run the sandboxed headless session (below) with the prompt +
   a trailing line naming the current set anchor (first non-blank line of `candidates.md`).
4. Read `docs/_verdict`.
5. **If `ACCEPT`** → independent re-verify gate, all required:
   - both `<base>_check_test.exs` and `<base>_fix_test.exs` exist;
   - wrapper deletes the superseded original `<base>_test.exs` (agent is additive);
   - the rule's `fix_patches` is no longer a constant-`[]` stub;
   - full `mix test` passes.
   Pass → `remove_from_list_keep_files.sh`; `git add` **explicit paths** (rule, the two split
   tests, deletion of the original, `candidates.md`); commit `<rule>: accepted`; **push**.
6. **Else** (`FOLLOWUP`, failed-accept gate, or missing/garbage `_verdict`) → one path:
   `remove_from_list_revert_files.sh`; append a `followup.md` entry (rule, files, reason,
   date); `git add docs/followup.md docs/candidates.md`; commit `<rule>: followup — <reason>`;
   **push**. *(The only exit to "accepted" is a wrapper-verified ACCEPT; everything else →
   followup. This removes the set from the top of the queue, so no infinite re-fetch.)*
7. `rm -f docs/_verdict`; `sleep wait_min*60` unless last iteration / list now empty.

## LLM sandbox (replaces `--dangerously-skip-permissions`)
```
claude -p "$prompt" --permission-mode acceptEdits \
  --allowedTools "Read Edit Write Grep Glob Bash(mix test:*) Bash(mix format:*) Bash(elixir:*)" \
  [--model "$CLAUDE_MODEL"]
```
No git, rm, cp, network, or `mix deps`. (Read reaches the sister repo by absolute path, so
shared-file bring-over is Read-there + Write-here.)

## Agent protocol (`review_set_prompt.md`)
- Follow `docs/02_rule-review-process.md` exactly. Work **only** the injected set; never touch
  another rule; create **no** scratch files (`/tmp` or throwaway tests).
- Run `mix test` first (doc step 2); if a shared-file change is needed
  (`lib/credence.ex`, `lib/rule_helpers.ex`, rule list…), bring the **minimal** piece over
  from the sister repo via Read+Write.
- Read rule + tests; dup-check; correctness analysis with nasty inputs (ASCII / NFC+NFD
  accents / multi-piece emoji / flags; empty/one/nil/negative; **type** checks). Verify
  language semantics with inline `elixir -e`; verify rule behaviour by asserting it in the
  rule's real check/fix test and running it.
- **Acceptance bar:** the rule is fixable (or you made it fixable) with a real `fix_patches`
  + tests **split** into `<base>_check_test.exs` and `<base>_fix_test.exs` (both, derived
  `expected` from real output, "leave it alone" as `fix(code)==code`, skipped-unsafe cases
  pinned as "no issue") + full `mix test` green. Write the two split files (additive); do
  **not** delete the original — the wrapper does.
- If no safe fix exists even for a narrow core (or it would change a value's **type**, or
  only a safety-switch could rescue it) → don't force it.
- **Last action:** write `docs/_verdict` with exactly `ACCEPT` or `FOLLOWUP: <one-line reason>`.
  Never run git.

## Files
- **New:** `scripts/remove_from_list_keep_files.sh`, `scripts/move_unfixable_out.sh`,
  `scripts/review_loop.sh`, `scripts/review_set_prompt.md`, `docs/unfixable.md`,
  `docs/followup.md`; `.gitignore` += `docs/_verdict`.
- **Rename:** `scripts/get_set.sh` → `copy_next_candidate.sh`; `scripts/drop_set.sh` →
  `remove_from_list_revert_files.sh`; `docs/pr_diff.md` → `docs/candidates.md`.
- **Edit:** the two renamed scripts (point `PRDIFF` at `candidates.md`);
  `docs/02_rule-review-process.md` (update `pr_diff.md` references to `candidates.md`).
- Reuse `copy_next_candidate.sh`/`drop_set`'s set-grouping logic in the keep-files and
  pre-pass scripts (same base-name matching).

## Verification
1. `move_unfixable_out.sh` (dry): ~52 sets moved to `unfixable.md`, `candidates.md` shrinks,
   one commit pushed.
2. `review_loop.sh 1 0` on the first candidate: either an **accepted** commit (rule + two
   split tests, original removed, `candidates.md` trimmed, full `mix test` green) or a
   **followup** commit; tree clean afterward; both pushed.
3. Force a red test for an ACCEPT case → confirm the gate fails → followup path fires.
4. Run to empty → "done"; `git log` shows one commit per set; `unfixable.md` + `followup.md`
   populated; `mix test` green on the branch tip.

## Open notes
- **Doc 02 rename churn:** updating `pr_diff.md` → `candidates.md` references in
  `docs/02_rule-review-process.md` is in scope (accepted with the list rename).
- **`mix format`** in the allow-list: kept so the agent can format before asserting exact
  test strings (doc 02 notes `mix format` runs after rules). Drop it if the wrapper formats.
