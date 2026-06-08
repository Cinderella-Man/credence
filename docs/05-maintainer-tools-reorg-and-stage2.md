# Plan: reorg into `maintainer_tools/` + build stage_2_promote_non_fixable

## Context
The autonomous rule-review system (`scripts/` + `docs/{candidates,followup,unfixable}.md`)
promotes AI-written rules from the `credence_evolution` sister into the accepted branch.
**Stage 1** (`scripts/review_loop.sh`) drained `candidates.md` (fixable rules). A pre-pass
(`move_unfixable_out.sh`) deterministically pulled **51 check-only stubs**
(`fix_patches/2 -> []`, no fix) into `unfixable.md` — these were *never* agent-reviewed.

Two goals:
1. **Reorg** scripts + the list files under one `maintainer_tools/` tree, stage_1 tooling in
   its own subdir.
2. **Build stage_2** — a second loop that drains the stubs, asking per stub: *can a safe,
   exact-same-answer fix be authored for all or a NARROWER subset of what `check/2` flags?*
   → author the fix + split tests (promote), or record the verdict.

### Locked decisions (from design review)
- **Full standalone copy.** Stage_2 copies & adapts whatever it needs; **zero shared code**
  with stage_1 (one-time pass). The flow is **near-identical** to stage_1.
- **Input renamed + reformatted to a flat list.** `unfixable.md` →
  **`unfixable_unreviewed.md`**, converted from per-block markdown to a **pure path list**
  (exactly `candidates.md` shape: bare `lib/...ex` + `test/...exs` lines, no header). Every
  entry is there for the *same* reason (`unfixable_stub?`), so the per-block prose was pure
  redundancy. This lets stage_2 reuse stage_1's flat-list helpers **byte-identical** — no
  markdown parser, no transient view, no block-delete script.
- New output **`unfixable_confirmed.md`** = proven unfixable after review — **structured**
  (like `followup.md`), because its per-entry reasons are *distinct* agent findings.
- **Three-way verdict.** `UNFIXABLE:` means *only* "no safe behavior-preserving fix for any
  shape." Duplicates and shared-file needs → `followup.md`.
- **Slim rules are fine** — any rule beats none; over-narrowing is **accepted risk** (stage_1
  had it too). **One stub → at most one rule** (no splitting).
- **Single-agent**, trusting Opus as stage_1 did. No adversarial pass; the prompt **mandates**
  a `{before, after, before == after}` nasty-input proof before ACCEPT.
- **Single source of truth:** `unfixable_unreviewed.md` *is* the live queue; it drains in
  place via the same line-strip mechanics stage_1 uses on `candidates.md`.
- `_verdict` → `maintainer_tools/_verdict`.

---

## Part A — Reorg (mechanical, one commit)

Target layout:
```
maintainer_tools/
  candidates.md            # stage_1 input (drained/empty)
  followup.md              # shared output: needs human attention (structured)
  unfixable_unreviewed.md  # stage_2 input — flat path list (renamed+converted)
  unfixable_confirmed.md   # stage_2 output — proven unfixable (NEW, structured)
  _verdict                 # transient, gitignored
  stage_1_promote_fixable_rules/        # all current scripts/*
    README.md                           # NEW — documents stage 1
    review_loop.sh review_lib.sh review_set_prompt.md
    copy_next_candidate.sh move_unfixable_out.sh
    remove_from_list_keep_files.sh remove_from_list_revert_files.sh
    changelog_guard.sh  .review_logs/
  stage_2_promote_non_fixable/          # Part B (new copies)
    README.md                           # NEW — documents stage 2
    .review_logs/
```

Steps:
- `git mv docs/candidates.md docs/followup.md maintainer_tools/`
- `git mv docs/unfixable.md maintainer_tools/unfixable_unreviewed.md`, then **convert it
  in place** to a flat path list: one-time extraction of the backtick `lib/...ex` +
  `test/...exs` paths from the 51 `##` blocks, in document order (rule line then its test
  line(s)). Result is `candidates.md`-shaped (pure paths, no header). *(Cannot regenerate by
  re-running `move_unfixable_out.sh` — it iterates `candidates.md`, now empty.)*
- Create `maintainer_tools/unfixable_confirmed.md` (header parallel to `followup.md`).
- `git mv scripts/* maintainer_tools/stage_1_promote_fixable_rules/`; remove empty `scripts/`.
- **Repath every stage_1 script:**
  - `REPO="$(cd "$SCRIPT_DIR"/../.. && pwd)"` (now 2 levels up).
  - `CANDIDATES/FOLLOWUP` → `maintainer_tools/...`; `move_unfixable_out.sh`'s `UNFIXABLE` →
    `maintainer_tools/unfixable_unreviewed.md`.
  - `VERDICT` → `maintainer_tools/_verdict`; `LOGDIR` → `$SCRIPT_DIR/.review_logs`.
  - `source "$SCRIPT_DIR/review_lib.sh"` unchanged (same dir).
- **`move_unfixable_out.sh` output format → flat:** append bare `rule` + `test` path lines
  instead of `##` blocks (so the format stays consistent if ever re-run on a future batch).
- `review_set_prompt.md`: `docs/_verdict` → `maintainer_tools/_verdict` (keep the
  `docs/02_rule-review-process.md` ref — that doc stays in `docs/`).
- `.gitignore`: `docs/_verdict` → `maintainer_tools/_verdict`; `scripts/.review_logs/` →
  `maintainer_tools/stage_1_promote_fixable_rules/.review_logs/` **+**
  `maintainer_tools/stage_2_promote_non_fixable/.review_logs/`.
- Ref touch-up: `docs/02` (`docs/candidates.md` → `maintainer_tools/candidates.md`).
  `docs/04` is a dated historical plan — leave as-is.
- **Dead `docs/unfixable_rules/` sweep** — that directory was a *pre-evolution* parking spot
  for warn-only rules; it's gone, and the references dangle. Remove all **live** pointers,
  keeping the surrounding policy intact:
  - **Docs:** `CONTEXT.md` (×4: lines 6, 119, 210, 238), `docs/02` (×3: row 111 + the
    "Writing it down" bullets 232/237), top-level `README.md:44`. In `docs/02` the policy
    ("every rule fixes or doesn't exist; no warn-only mode") **stays** — drop only the
    `unfixable_rules/` parking pointer.
  - **Code/test comments (comment-only, suite stays green):** `lib/pattern/rule.ex:7`,
    `test/fix_showcase_test.exs:181`.
  - **`lib/pattern/no_enum_at_midpoint_access.ex:102`** — the comment says the rule was
    "archived to `docs/unfixable_rules/`" yet the file is present → **human read, not a blind
    edit** (possible stale/contradictory comment to resolve separately).
  - **Leave `docs/01`** (×6) untouched — it's a dated record of the past "15 rules moved"
    event; editing it would falsify history.
- Verified: **no CI/Makefile/hook references** to `scripts/` — move is safe.

Verify A: `bash -n` each script; `review_loop.sh` paths resolve; converted
`unfixable_unreviewed.md` is pure paths (102 lines: 51 rules + their tests); `git mv`
preserves history; `mix test` green.

---

## Part B — stage_2_promote_non_fixable

All files in `maintainer_tools/stage_2_promote_non_fixable/`, each a standalone copy of the
stage_1 analog (no cross-stage sourcing). Because the queue is now a **flat path list**, the
mechanics are reused essentially verbatim.

### Copied byte-identical (only `CANDIDATES` repointed to `unfixable_unreviewed.md`)
- `promote_lib.sh` — copy of `review_lib.sh` (`rule_kind`, `rule_base`, `group_tests`,
  `owner_base`, `is_unfixable_stub`).
- `copy_next_candidate.sh` — copies the top set (rule + grouped tests) from `$SISTER`.
- `remove_from_list_keep_files.sh` — ACCEPT strip (keep files).
- `remove_from_list_revert_files.sh` — negative strip (revert files + strip lines).

### `promote_prompt.md` — NEW (derived from `review_set_prompt.md`, **pattern bar only**)
All 51 stubs are `pattern`. Same hard sandbox (no git; edit only `lib/pattern/<base>.ex` +
`<base>*_test.exs`; no scratch files; exact `==` heredoc fix-tests; verdict file). Reframe:
- "This rule is a **check-only STUB**: `check/2` fires but `fix_patches/2` is the dead `[]`
  form — auto-classified unfixable, **never reviewed**. Decide whether a behaviour-preserving
  (exact-same-answer on **every** admitted input) fix can be authored for **all or a narrower
  subset** of what `check/2` flags. **Any safe core, however slim, is worth promoting.**"
- Procedure: run `mix test`; read `check/2` → enumerate flagged shapes; for each, find the
  canonical replacement and **prove same-answer**. **Mandatory before ACCEPT:** paste a
  `{before, after, before == after}` comparison (via `elixir -e`) for the relevant trap
  classes — codepoint vs grapheme (Unicode), negative index, non-list enumerables
  (Range/Map raise), float-vs-int, empty/nil, sort stability, side-effect double-eval, and
  **value-type changes (can't be narrowed away)**.
- **Narrow `check/2`** to only the safe shapes; keep dropped shapes as explicit "no issue"
  check tests; author `fix_patches/2` for exactly those; split into `<base>_check_test.exs` +
  `<base>_fix_test.exs`. `check` and `fix` must agree.
- **Verdict (exactly one):**
  - `ACCEPT` — real fix authored, suite green.
  - `UNFIXABLE: <reason>` — proven no safe core for **any** shape (or only a type-changing
    fix). The genuine correctness verdict.
  - `FOLLOWUP: <reason>` — duplicate of an accepted rule (fold/drop), needs an out-of-set
    shared-file change, or inconclusive.

### `promote_loop.sh` — copy of `review_loop.sh`, adapted
Self-heal, retry/backoff, greenfield classify (always greenfield for a copied stub — kept
verbatim), `run_session`, **and `gate_accept` reused verbatim** (already enforces
`is_unfixable_stub`==false + the pattern `_check`/`_fix` shape + confined diff + full
`mix test` green — exactly "the fix is now real"). Diffs from stage_1:
- Vars: queue=`unfixable_unreviewed.md`, `CONFIRMED=unfixable_confirmed.md`,
  `PROMPT=promote_prompt.md`, `VERDICT=maintainer_tools/_verdict`, `FOLLOWUP=followup.md`.
- **Startup guard:** refuse to run unless `candidates.md` is empty (stage_1 done) and
  `$SISTER` exists (on `evolution`).
- The verdict `case` gains a third branch; `accept_commit` commits `promoted`; a new
  `confirmed_unfixable()` handler = clone of `followup()` writing to `unfixable_confirmed.md`:

  | Verdict (after gate) | In-set files | Strip queue via | Record | Commit msg |
  |---|---|---|---|---|
  | `ACCEPT` ✓ | **keep** | `remove_from_list_keep_files.sh` | rule joins tree | `<base>: promoted` |
  | `UNFIXABLE:` | revert | `remove_from_list_revert_files.sh` | append `unfixable_confirmed.md` (`## <base> — date`, files, agent reason) | `<base>: confirmed unfixable` |
  | `FOLLOWUP:` / gate-fail / missing verdict | revert | `remove_from_list_revert_files.sh` | append `followup.md` | `<base>: followup — <reason>` |

  Gate failures and missing/garbage verdicts default to `followup.md`, **never** to confirmed
  (a confirmed claim must be an explicit `UNFIXABLE:` verdict). Transient (no verdict /
  crash / token-limit) → stay on the row, retry with backoff (verbatim stage_1).

End state: `unfixable_unreviewed.md` empty — each stub became a `promoted` commit, an
`unfixable_confirmed.md` entry, or a `followup.md` entry.

### Propagation of confirmed findings (manual, out of the loop)
Per `docs/02` ("a correctness finding isn't done until it's written where it'll be read
again"), every `UNFIXABLE:` reason is a freshly-proven unsafe-rewrite class. The loop stays
**sandboxed** (the agent can't touch `CONTEXT.md`/`prompt.md`), so propagation is **manual**:
`unfixable_confirmed.md` is the durable queue for a **later human pass** that distills its
reasons into `CONTEXT.md` (policy) and `prompt.md` (so the rule-writing AI stops re-making
them). Matches stage_1 (no auto-edit of shared docs). No automated synthesis step.

---

## READMEs (one per stage dir — required deliverables)

Both are written so a maintainer returning months later can run and trust the loop without
re-reading the source. Each ≈ a page; concrete commands, not prose.

### `stage_1_promote_fixable_rules/README.md`
- **Purpose** — drive the autonomous review of *fixable* candidate rules: one sandboxed
  Claude session per set from `../candidates.md`, promoting safe ones to the accepted branch.
- **The one bar it defends** — a fix must give the exact same answer for every admitted input
  (`:strict` ⇒ every input); link `docs/02_rule-review-process.md` and `docs/04`.
- **Sandbox model** — the session has **no git**; the wrapper owns all git + all list edits;
  the session's only output is `../_verdict` (`ACCEPT` | `FOLLOWUP: <reason>`).
- **Data files** (in `maintainer_tools/`) — consumes `candidates.md`; writes `followup.md`;
  the stub pre-pass writes `unfixable_unreviewed.md`. Sister checkout = `$SISTER`
  (default `../credence_evolution`, on `evolution`).
- **Run** — `./review_loop.sh [cap] [wait_min]` (env `SISTER`, `CLAUDE_MODEL`); what a row
  prints; where per-row transcripts land (`.review_logs/<base>.log`).
- **Per-script index** — one line each: `review_loop.sh`, `review_lib.sh`,
  `review_set_prompt.md`, `copy_next_candidate.sh`, `move_unfixable_out.sh` (now flat output),
  `remove_from_list_keep_files.sh`, `remove_from_list_revert_files.sh`, `changelog_guard.sh`.
- **Gate & kinds** — the per-kind acceptance bar + re-verify gate (real fix, test shape,
  confined diff, full `mix test` green); greenfield vs delta; self-heal + retry/backoff.

### `stage_2_promote_non_fixable/README.md`
- **Purpose** — second pass over the **check-only stubs** (`unfixable_unreviewed.md`): per
  stub, try to author a safe fix for all or a **narrower** subset of what `check/2` flags,
  else record why not. States plainly: stage 2 is a near-identical copy of stage 1 with a
  flat-list queue, a stub-focused prompt, and a **three-way** verdict.
- **Preconditions** — stage 1 done (`candidates.md` empty — enforced by a startup guard);
  `$SISTER` present on `evolution`.
- **Verdict & routing** — reproduce the routing table: `ACCEPT`→`promoted`;
  `UNFIXABLE:`→`unfixable_confirmed.md` (no safe core for any shape); `FOLLOWUP:`→`followup.md`
  (duplicate / needs shared-file change / inconclusive); gate-fail & missing verdict →
  followup, never confirmed.
- **Data files** — input `unfixable_unreviewed.md` (flat path list, drains in place); outputs
  `unfixable_confirmed.md` (structured) + `followup.md`.
- **Run** — `./promote_loop.sh [cap] [wait_min]`; logs in `.review_logs/`.
- **Per-script index** — note which files are byte-identical copies of stage 1 (`promote_lib`,
  `copy_next_candidate`, both `remove_from_list_*`) vs genuinely new (`promote_prompt.md`,
  `promote_loop.sh`'s `UNFIXABLE:` branch).
- **Downstream** — `unfixable_confirmed.md` is the **manual** queue for later
  `CONTEXT.md` / `prompt.md` updates (the loop is sandboxed and won't touch shared docs).

## Files
- **Moved:** `docs/candidates.md`, `docs/followup.md` → `maintainer_tools/`;
  `docs/unfixable.md` → `maintainer_tools/unfixable_unreviewed.md` (rename **+ convert to
  flat list**); `scripts/*` → `maintainer_tools/stage_1_promote_fixable_rules/`.
- **New (reorg):** `maintainer_tools/unfixable_confirmed.md`;
  `stage_1_promote_fixable_rules/README.md`.
- **Edited (stage_1):** all moved scripts repathed; `move_unfixable_out.sh` output → flat;
  `review_set_prompt.md` verdict path; `.gitignore`; `docs/02`.
- **Edited (dead-ref sweep):** `CONTEXT.md`, `docs/02`, `README.md`, `lib/pattern/rule.ex`,
  `test/fix_showcase_test.exs` (drop `docs/unfixable_rules/` pointers);
  `lib/pattern/no_enum_at_midpoint_access.ex` flagged for human read; `docs/01` left as-is.
- **New (stage_2, under `maintainer_tools/stage_2_promote_non_fixable/`):** `promote_lib.sh`,
  `copy_next_candidate.sh`, `remove_from_list_keep_files.sh`,
  `remove_from_list_revert_files.sh` (copies, repointed), `promote_prompt.md` (new),
  `promote_loop.sh` (copy + three-way verdict), `README.md` (new).

## Execution & commits
- Work happens on **`evolution_accepted`** (where stage_1's accepted rules already live); no
  feature-branch/PR ceremony, matching the existing direct-commit workflow.
- **Reorg = one self-contained commit** (all `git mv`s + repaths + dead-ref sweep + READMEs +
  empty `unfixable_confirmed.md`), **verified before stage_2 runs** (Verify A below). One
  isolated commit ⇒ trivially revertable if a path rewrite is wrong.
- **Stage_2 = per-stub commits** on the same branch (`promoted` / `confirmed unfixable` /
  `followup`), pushed each — identical cadence to stage_1.

## Verification
1. **Reorg:** `bash -n` all scripts; stage_1 `review_loop.sh` paths resolve;
   `unfixable_unreviewed.md` = 102 pure path lines; `mix test` green; history preserved.
2. **Startup guard:** `promote_loop.sh` aborts cleanly if `candidates.md` non-empty.
3. **One promote (`no_double_filter`):** `promote_loop.sh 1 0` → stub copied from sister →
   agent authors narrowed fix + split tests + nasty-input proof → gate (fix real,
   `mix test` green) → commit `"no_double_filter: promoted"`; its lines gone from
   `unfixable_unreviewed.md`; tree clean; pushed.
4. **Confirmed-unfixable stub:** agent writes `UNFIXABLE: <reason>` → `unfixable_confirmed.md`
   entry added, lines removed, `"<base>: confirmed unfixable"` commit, files reverted.
5. **Duplicate / shared-file stub:** agent writes `FOLLOWUP:` → `followup.md` entry, lines
   removed, `"<base>: followup — <reason>"` commit.
6. **Forced-red gate** on an ACCEPT → gate fails → followup path (no partial promote).
7. **Run to empty:** `unfixable_unreviewed.md` drained; one commit per stub;
   `unfixable_confirmed.md`/`followup.md` populated; `mix test` green at tip.
8. **READMEs:** each stage dir has a `README.md`; the exact run command it documents
   (`./review_loop.sh` / `./promote_loop.sh`) works from that dir; the per-script index
   matches the files actually present.
9. **Dead-ref sweep:** `grep -rn 'docs/unfixable_rules' .` returns **only** `docs/01`
   (historical) and `no_enum_at_midpoint_access.ex` (flagged) — no live doc/README/comment
   pointer remains; `mix test` still green (comment-only edits).

## Open / confirm-if-wrong
- `changelog_guard.sh` is a CI guard unrelated to the loop; moved under stage_1 per "move all
  of scripts/." Nothing references it — flag if it should live elsewhere.
- `docs/04` historical plan doc left with its dated stage_1 paths (not updated).
