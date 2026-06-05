# Stage 2 — promote non-fixable (check-only) stubs

A second pass over the **check-only stubs** in `../unfixable_unreviewed.md` — the
rules whose `check/2` fires but whose `fix_patches/2` is the dead `[]` form, which
stage 1 auto-classified *unfixable* and **never reviewed**. For each stub, one
fresh, sandboxed Claude session tries to author a **safe** fix for **all or a
narrower subset** of what `check/2` flags (any safe core beats none); if it can't,
it records why.

Stage 2 is a **near-identical copy of stage 1** with three differences: a flat-
list queue, a stub-focused prompt (`promote_prompt.md`), and a **three-way**
verdict. All scripts are standalone copies — no cross-stage sourcing.

## Preconditions
- **Stage 1 done** — `../candidates.md` must be empty. `promote_loop.sh` enforces
  this with a startup guard and aborts otherwise.
- `$SISTER` present (default `../credence_evolution`, on the `evolution` branch).

## Verdict & routing
The session writes exactly one line to `../_verdict`:

| Verdict | In-set files | Strip queue via | Record | Commit |
|---|---|---|---|---|
| `ACCEPT` | **keep** | `remove_from_list_keep_files.sh` | rule joins the tree | `<base>: promoted` |
| `UNFIXABLE: <reason>` | revert | `remove_from_list_revert_files.sh` | `../unfixable_confirmed.md` | `<base>: confirmed unfixable` |
| `FOLLOWUP: <reason>` | revert | `remove_from_list_revert_files.sh` | `../followup.md` | `<base>: followup — <reason>` |

- `ACCEPT` must pass the same re-verify **gate** as stage 1 (the fix is now real —
  not a stub — the split `_check`/`_fix` tests exist, the diff is confined to the
  rule's files, and the whole `mix test` suite is green).
- `UNFIXABLE:` means *no safe, behaviour-preserving fix for any shape it flags* (or
  only a value-type-changing fix). The genuine correctness verdict.
- `FOLLOWUP:` means a duplicate of an accepted rule, a needed out-of-set shared-
  file change, or an inconclusive review.
- **Gate failures and unrecognized verdicts default to `followup.md`, never to
  confirmed** — a confirmed claim must be an explicit `UNFIXABLE:` verdict.
- A **missing** verdict (agent crash / token-limit) is *transient*, not a
  decision: the row's files are reverted and it stays put, retrying with backoff
  (15/30/45/60 min, then hourly) until Claude recovers.

## Data files (in `maintainer_tools/`)
- input: `unfixable_unreviewed.md` — flat path list (rule line + its test line(s),
  candidates.md shape); the live queue, drains in place.
- output: `unfixable_confirmed.md` — structured, proven-unfixable (distinct
  per-entry agent reasons).
- output: `followup.md` — structured, needs human attention.
- `_verdict` — transient verdict channel (gitignored).

## Run
```
./promote_loop.sh [cap] [wait_min]      # cap=0 → run until the queue is empty; wait_min default 15
SISTER=/path CLAUDE_MODEL=… ./promote_loop.sh
```
Each row prints a one-line digest; per-row agent transcripts land in
`.review_logs/<base>.log`.

## Per-script index
- `promote_loop.sh` — the orchestrator. **Genuinely new vs stage 1:** the startup
  guard, the `UNFIXABLE:` verdict branch, and `confirmed_unfixable()` (a clone of
  `followup()` that writes to `unfixable_confirmed.md`). Everything else — self-
  heal, classify, `run_session`, the re-verify `gate_accept` — is reused verbatim.
- `promote_prompt.md` — **new**: the stub-focused agent protocol (pattern bar
  only; mandates a `{before, after, before == after}` nasty-input proof before
  ACCEPT; three-way verdict).
- `promote_lib.sh` — **byte-identical** copy of stage 1's `review_lib.sh`.
- `copy_next_candidate.sh` — copy of stage 1's, queue repointed.
- `remove_from_list_keep_files.sh` — copy of stage 1's, queue repointed.
- `remove_from_list_revert_files.sh` — copy of stage 1's, queue repointed.

## Downstream (manual, out of the loop)
`unfixable_confirmed.md` is the durable queue for a **later human pass** that
distills each proven reason into `CONTEXT.md` (policy) and `prompt.md` (so the
rule-writing AI stops re-making the same unsafe rewrites). The loop is sandboxed
and never edits those shared docs — propagation is manual, matching stage 1.
