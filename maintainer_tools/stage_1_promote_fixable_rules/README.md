# Stage 1 — promote fixable rules

Drives the autonomous review of **fixable** candidate rules: one fresh, sandboxed
Claude session per rule "set" (a rule file + its test file(s)) read top-to-bottom
from `../candidates.md`, promoting the safe ones onto this branch
(`evolution_accepted`).

## The one bar it defends
A fix must give the **exact same answer for every admitted input** (with no
promises / `:strict`, that means *every possible input*). A tidier-but-different
rewrite is a bug, not an improvement. A green suite proves a rule *does
something*, not that it's safe. See `docs/02_rule-review-process.md` and
`docs/04-autonomous-review-loop.md`.

## Sandbox model
The Claude session has **no git** and may edit **only the set's own files**
(`lib/<kind>/<base>.ex` + `test/<kind>/<base>*_test.exs`). The wrapper
(`review_loop.sh`) owns **all** git and **all** list edits. The session's only
output channel is the verdict file `../_verdict`, containing exactly one of:

- `ACCEPT` — the fix is real, the set's tests are the right shape, only the set's
  files changed, and the whole `mix test` suite is green.
- `FOLLOWUP: <reason>` — anything else (no safe fix, duplicate, needs a
  shared-file change, type change, inconclusive).

## Data files (in `maintainer_tools/`)
- consumes `candidates.md` — flat path list, the live queue; drains in place.
  **Generated** by `generate_candidates.sh`, not hand-edited — re-run it whenever
  the evolution branch gains rules.
- writes `followup.md` — structured, needs human attention.
- the stub pre-pass (`move_unfixable_out.sh`) writes `unfixable_unreviewed.md`
  (stage 2's input).
- `_verdict` — transient verdict channel (gitignored).
- sister checkout = `$SISTER` (default `../credence_evolution`, on `evolution`).

## Run
```
./review_loop.sh [cap] [wait_min]      # cap=0 → run until candidates.md empty; wait_min default 15
SISTER=/path CLAUDE_MODEL=… ./review_loop.sh
```
Each row prints a one-line digest (verdict, files, suite count, list size,
push status). Per-row agent transcripts land in `.review_logs/<base>.log`.

## Gate & kinds
After an `ACCEPT` verdict the wrapper independently **re-verifies** before
committing: the rule file exists and is **not** a check-only stub (the fix is
real); the test shape matches the kind; the diff is confined to the set; the full
`mix test` suite is green. Per kind:
- **pattern** — split `<base>_check_test.exs` + `<base>_fix_test.exs`; real
  `fix_patches` (never a constant `[]`).
- **semantic** — `<base>*_check_test.exs` + ≥1 `<base>*_fix_test.exs`.
- **syntax** — `<base>_analyze_test.exs` + `<base>_fix_test.exs`, or a single
  `<base>_test.exs`.

A set is classified **greenfield** (brand-new rule, reviewed from scratch) or
**delta** (already live; only the evolution change is judged). Transient agent
failures (no verdict / crash / token-limit) are not followups — the row reverts
and retries with backoff (15/30/45/60 min, then hourly) until Claude recovers.

## Per-script index
- `generate_candidates.sh` — (re)build `candidates.md` from the sister: every rule
  the evolution branch added/changed vs `main` that has no `accepted`/`promoted`/
  `followup` commit yet, emitted as anchored sets. `--dry-run` to preview. This is
  the queue's source of truth — no more hand-parsing the main↔evolution diff.
- `review_loop.sh` — the orchestrator (self-heal → pick set → classify → run
  session → read verdict → gate → commit/push).
- `review_lib.sh` — shared helpers (`rule_kind`, `rule_base`, `group_tests`,
  `owner_base`, `is_unfixable_stub`).
- `review_set_prompt.md` — the agent protocol (the one bar, sandbox, per-kind
  test shape, verdict).
- `copy_next_candidate.sh` — copy the top set (rule + grouped tests) from `$SISTER`.
- `move_unfixable_out.sh` — one-time pre-pass: strip provably check-only stubs
  from `candidates.md` into `unfixable_unreviewed.md` (flat path-list output).
- `remove_from_list_keep_files.sh` — ACCEPT strip (keep files).
- `remove_from_list_revert_files.sh` — reject strip (revert files + strip lines).
- `changelog_guard.sh` — CI guard: a safety-switch default change needs a
  matching CHANGELOG entry (unrelated to the loop; lives here per "move all of
  `scripts/`").
