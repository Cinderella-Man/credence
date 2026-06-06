# Stage 3 — Resurrect followups

## Context
Two autonomous loops exist under `maintainer_tools/`: stage 1 (drain fixable
`candidates.md`) and stage 2 (drain check-only `unfixable_unreviewed.md` stubs).
Both dump rejected rules into the narrative **`followup.md`** with a `## <base> —
<date>` / `- Files:` / `- Reason:` shape. That doc is a graveyard: ~40 rules
rejected for non-behaviour-preservation, gate-only test-shape misses, type
changes, etc. — never re-examined.

**Goal of stage 3:** a share-nothing (standalone copy, no cross-stage sourcing)
loop that re-examines each followup rule and decides whether it can be
**resurrected to a fixable rule** — by splitting a single-file testsuite,
narrowing to a missed fixable core, reusing the existing
`single_codepoint_graphemes` switch, or (when only a *new* assumption would
rescue it) emitting a designed **proposal** for a human to land. The
0.7.0 safety-switch invariant governs every verdict: *Credence never changes
behaviour on any input the stated promises admit* (`docs/03-safety-switches.md`).

**Decisions locked (user):** new switches are **propose-only** — the sandboxed
session NEVER edits the shared `lib/assumptions.ex`/`CHANGELOG.md`; it designs the
switch and writes it to a human queue. The propose-only queue is **two files,
catalog + mapping, deduplicated one-to-many** (a single assumption can rescue many
rules) — see "Propose-switch output model" below. The loop **drains `followup.md`
directly** (no intermediate flat queue). Output files are deliberately minimal:
only the two propose-only files + `stage3_unfixable.md`. ACCEPT needs no ledger
(the rule lands in the tree; git log is the record); KEEP needs none either (the
entry simply **stays in `followup.md`**).

## Architecture
New dir `maintainer_tools/stage_3_resurrect_followups/`. Same spirit as
`stage_2_promote_non_fixable/`: wrapper owns ALL git; session is sandboxed (no
git), allowed tools `Read Edit Write Grep Glob Bash(mix test:*) Bash(mix format:*)
Bash(elixir:*)`; output channel is `maintainer_tools/_verdict`; per-row
`.review_logs/<base>.log`; self-heal + retry/backoff in the spirit of stage 2. The
queue plumbing differs (below): there is no flat-list queue and no separate
pre-pass — the loop reads `followup.md` sections directly.

### Queue model (drains followup.md directly)
`followup.md` is narrative markdown (one `## <base> — <date>` section per rejected
rule). It is the input AND it **drains as the loop works through the list**: every
verdict except KEEP removes the resolved `## <base>` section (`clear_followup_section`
— a clean whole-section delete from the header to the next `## `, not mid-section
line-mangling). The loop picks rows directly from `followup.md`:

- **`each_resurrectable` / `next_set`** (in `resurrect_loop.sh`): `split_sections`
  splits `followup.md` into `## ` sections; a section is a **row** when it (a) bears
  no `DONE`/`REJECTED` marker, (b) has a `lib/(pattern|semantic|syntax)/*.ex` path,
  (c) that rule exists in `$SISTER`, and (d) its base is not in the in-memory KEEP
  skip-set. `next_set` loads the first such section's rule + test paths (parsed from
  the section body) into the working set; `copy_set` copies them from `$SISTER`.
- No `followup_unreviewed.md`, no `extract_followup_candidates.sh`, no
  `copy_next_candidate.sh` / `remove_from_list_*`. Reverting a rejected set is just
  `revert_set_files` (revert the dirty in-set files); there is no list to strip.
- **`LIST=1 ./resurrect_loop.sh`** previews the pending rows (no session, no writes).

Idempotency is structural: a resolved row's section is gone from `followup.md`
outright, so it is never picked again. `followup.md` shrinks toward only the entries
Stage 3 cannot act on — the skip-listed narrative entries (global suites,
DONE/REJECTED blocks, orphans) that are never picked, plus KEEP'd rows. Nothing
Stage 3 produces re-enters the input, so no wheel-spinning.

### Briefing (additions over stage 2)
`build_briefing` additionally:
- greps `followup.md` for the `## <base>` section and includes its original
  **`- Reason:`** text — the session needs *why it was rejected* as the starting
  hypothesis for what a narrowing/switch must overcome.
- injects the **full `lib/assumptions.ex`** (the moduledoc is the rubric for what
  a *valid* assumption even is — a checkable promise about running data, not
  types) **and** `proposed_assumptions.md` **verbatim** (the pending catalog). The
  mapping file `proposed_rules_requiring_assumptions.md` is **excluded** — it is an
  output ledger, not decision input, and injecting it would bloat the prompt and
  anchor the session on one prior narrowing.

These two injections are the dedup menu: the session decides, semantically,
whether its rule's residual divergence is covered by an **approved** switch
(→ ACCEPT path #3), a **pending** catalog entry (→ REUSE), or neither (→ NEW).
Mode classify stays greenfield/delta off `git status` as in stage 2.

### Verdict contract (4-way + transient)
Session writes its verdict to `_verdict` (recreated per row, same channel as
stage 2 — the `_verdict` file *is* the scratch channel; there is no separate
`_proposal` file). It is one line for ACCEPT/UNFIXABLE/KEEP. For the two PROPOSE
verdicts the header line is followed by a **design payload built from named
markdown sections** the wrapper extracts:
- `### Assumption` — the reusable catalog entry body (`- Default:`, `- Summary:`,
  `- Rationale:`). Present for **NEW only**.
- `### Rule` — this rule's per-rule mapping body (`- Narrowing:`, `- Property
  test:`). Present for **both NEW and REUSE**.

The wrapper parses the first line to route, then `tail -n +2` is the payload it
splits by section.

- `ACCEPT` — resurrected within sandbox scope. Allowed moves, cheapest first:
  1. **Gate-only miss** — rejection was just "failed accept gate (needs _check +
     _fix)" and the fix is already behaviour-preserving → split the single-file
     `<base>_test.exs` into `_check`+`_fix`, verify, accept.
  2. **Missed fixable core** — narrow `check`+`fix` to a provably output-identical
     subset (per the rule-evolution methodology); ship split tests.
  3. **Existing switch** — if the only residual divergence is multi-codepoint
     graphemes (NFD/ZWJ/flags): shrink-first so the promise covers only that gap,
     add `def assumptions, do: [:single_codepoint_graphemes]`, author
     `test/pattern/<base>_property_test.exs` (StreamData via
     `AssumptionGenerators.single_codepoint_string`). `mix test` enforces
     `assumptions_meta_test`.
- `PROPOSE_SWITCH_NEW: <name> | <reason>` — a **genuinely new** assumption
  rescues it (a checkable promise about RUNNING DATA, not types — e.g.
  non-negative indices, proper-list enumerables, integer numbers, no
  comparator-tie elements) that matches neither an approved switch nor a pending
  catalog entry. Session does NOT touch `lib/assumptions.ex`; the header is
  followed by **both** an `### Assumption` section and an `### Rule` section (see
  "Propose-switch output model"). When an existing catalog entry is *almost* right
  but **too narrow**, that is strictly NEW (humans merge near-duplicates later) —
  there is no "widen" verdict.
- `PROPOSE_SWITCH_REUSE: <name> | <reason>` — the rule is rescued by an assumption
  **already pending** in `proposed_assumptions.md`. Header followed by an `### Rule`
  section only (**no** `### Assumption` section — reuse, don't redesign). `<name>`
  must verbatim-resolve to a catalog heading. REUSE is legal **only** when the
  existing promise, unchanged, covers the rule's *full* residual divergence — the
  session carries the **same `{before, after, before==after}` proof obligation as
  ACCEPT** (over the trap classes, under the assumed promise), just unlanded. A
  too-weak promise → NEW, not REUSE.
- `UNFIXABLE: <reason>` — no safe core and no switch helps: **type** change
  (charlist→integers, e.g. `no_integer_to_string_digits`), or side-effect /
  double-eval / sort-stability that can't be framed as a data promise.
- `KEEP: <reason>` — needs an out-of-set / curated-suite change, is a true
  duplicate of an accepted rule, or is inconclusive. **No ledger, no commit**: the
  wrapper reverts the in-set files and **leaves the section in `followup.md`** (the
  human-attention residue), skipping it in memory for the rest of the run. (A fresh
  run re-reviews KEEP'd rows — they are still in followup.md.)
- no/garbage verdict → transient agent error → revert, stay on row, retry/backoff
  (in the spirit of stage 2). gate-fail / unrecognized verdict → routed to **KEEP**
  (never a silent promote). **Confused-session signals also retry** (transient,
  not KEEP): `PROPOSE_SWITCH_NEW` whose `<name>` already exists verbatim in the
  catalog, `PROPOSE_SWITCH_REUSE` carrying an `### Assumption` section, `REUSE`
  whose `<name>` does not resolve to any catalog heading, and either PROPOSE verdict
  missing a required section.

### Propose-switch output model (catalog + mapping, dedup'd)
Replaces a single `switch_proposals.md`. The wrapper does **zero** dedup — names
are too vague (a thousand ways to describe one promise), so every semantic call is
the session's. The wrapper only obeys the NEW/REUSE signal:

- `proposed_assumptions.md` — the **catalog**: one `## <name>` entry per *unique*
  assumption, registry-shaped so a human can paste it into `@registry` —
  `- Default:`, `- Summary:` (the one-line promise), `- Rationale:` (the class of
  running-data fact it promises; why it is checkable-about-data-not-types).
  **Per-assumption only**; nothing rule-specific.
- `proposed_rules_requiring_assumptions.md` — the **mapping**: one `## <base>` row
  per rule — `- Assumption:` (the catalog name it points at), `- Files:`,
  `- Original reason:` (from `followup.md`), `- Narrowing:` (this rule's
  shrink-first move), `- Property test:` (this rule's sketch). **Per-rule.** This
  is what makes REUSE coherent: a rule borrows an assumption's *definition* but
  ships its *own* narrowing + property test.

NEW appends its `### Assumption` section (under a wrapper-written `## <name> —
<date>` heading) to the catalog **and** a mapping row to the mapping file; REUSE
appends a mapping row **only**. The mapping row's fixed fields (`- Assumption:`,
`- Files:`, `- Original reason:`) are wrapper-composed; the session's `### Rule`
section supplies `- Narrowing:` / `- Property test:`. Both files live directly under
`maintainer_tools/`, created empty.

**Lifecycle / re-entry (manual, human-driven).** When a human lands a pending
assumption into `lib/assumptions.ex`, they **delete** its `## <name>` entry from
`proposed_assumptions.md` **and** the matching rows from
`proposed_rules_requiring_assumptions.md`, then re-feed those rule bases through
**stage 1** (the switch is now approved → stage 1's normal switch-gated fixable
path resurrects them). Those rules are no longer in `followup.md` (Stage 3 drained
them when it proposed), so the proposed-rules file is their record until re-fed.
Stage 3 owns no feedback loop.

### Routing
| Verdict | followup.md | Files kept? | Records to | Commit msg |
|---|---|---|---|---|
| ACCEPT | section removed | yes (promoted) | the tree + git log (no ledger) | `<base>: resurrected` |
| PROPOSE_SWITCH_NEW | section removed | reverted | `proposed_assumptions.md` (design) **+** `proposed_rules_requiring_assumptions.md` (row) | `<base>: switch proposed (<name>)` |
| PROPOSE_SWITCH_REUSE | section removed | reverted | `proposed_rules_requiring_assumptions.md` (row) only | `<base>: reuses proposed switch (<name>)` |
| UNFIXABLE | section removed | reverted | `stage3_unfixable.md` | `<base>: confirmed unfixable (stage 3)` |
| KEEP | **left in place** | reverted | none (stays in followup.md) | none (no commit) |

Every verdict except KEEP **removes the resolved `## <base>` section from
`followup.md`** (`clear_followup_section`) and is a **single commit per row**. The
PROPOSE handlers read the section's `- Reason:` *before* clearing it (it feeds the
mapping row's `- Original reason:`). ACCEPT keeps + `git add`s the rule, all
`test/<kind>/<base>*` (incl. new `_property_test`), deletes any superseded single
`<base>_test.exs`. KEEP changes nothing on disk (files reverted, followup.md
untouched) so it makes no commit.

### Gate (`gate_accept`)
Checks: rule-exists + not-a-stub (a), pattern needs `_check`+`_fix` (b),
informational `=~` scan (b2), **confined diff (c)** via `confined_to_base` (every
dirty file's basename is `<base>.ex` or `<base>_*`), full `mix test` (d). Two
deltas over stage 2:
- (b+) if the rule file declares a non-empty `assumptions/0` (grep
  `def assumptions, do: [:`), also require `test/<kind>/<base>_property_test.exs`
  to exist (else clear gate message; `mix test` would red anyway via meta-test).
- (c) **the propose-only enforcer** — a session that edits
  `lib/assumptions.ex`/`CHANGELOG.md` fails confined-diff (`confined_to_base`) →
  KEEP. The `<base>_property_test.exs` matches `<base>_*` so it passes.

### Startup guard
Refuse to run until **both** `candidates.md` and `unfixable_unreviewed.md` are
empty (followup.md is appended by stages 1 AND 2 — review only after they settle).

## Files (all under `maintainer_tools/stage_3_resurrect_followups/`)
- `resurrect_loop.sh` — orchestrator. Drains `followup.md` directly
  (`split_sections` / `each_resurrectable` / `next_set` / `copy_set` /
  `clear_followup_section`); 5-way routing
  (`accept`/`propose_switch_new`/`propose_switch_reuse`/`unfixable`/`keep`);
  multi-line `_verdict` parse (`### Assumption`/`### Rule`); confused-session
  transient retries (NEW-name-already-in-catalog, REUSE-with-`### Assumption`,
  REUSE-name-unresolved, missing section); briefing reason + assumptions + catalog
  injection; two-empty startup guard; `LIST=1` preview.
- `resurrect_lib.sh` — `rule_kind` / `rule_base` / `is_unfixable_stub`.
- `resurrect_prompt.md` — the decision ladder + hard constraints
  (no git; edit ONLY set files; NEVER edit `lib/assumptions.ex`/`lib/credence.ex`/
  `lib/rule_helpers.ex`/curated suites; `mix test` first; whole-string `==`
  heredoc fix tests; split `_check`/`_fix`; codepoint↔grapheme bans; mandatory
  `{before, after, before==after}` `elixir -e` proof over trap classes before
  ACCEPT **and before REUSE**) + the 5-way verdict contract (NEW/REUSE split) +
  the dedup ladder (approved switch → ACCEPT path #3; pending catalog entry whose
  promise fully covers the residual divergence → REUSE; else → NEW; too-narrow
  existing promise → NEW, never widen).
- `README.md` — purpose, preconditions (stages 1&2 drained), verdict table,
  propose-only note, the catalog+mapping output model, the **load-bearing
  human-deletion re-entry contract**, run instructions.
- Output files created empty (header only): `maintainer_tools/proposed_assumptions.md`
  (header states the deletion contract from "Lifecycle / re-entry"),
  `proposed_rules_requiring_assumptions.md`, `stage3_unfixable.md`. **No**
  `followup_unreviewed.md` / `resurrected.md` / `stage3_keep.md` — the loop drains
  followup.md directly, ACCEPT records to the tree, KEEP stays in followup.md.

Reuse (do NOT re-solve): the existing switch + property-test machinery
(`lib/assumptions.ex`, `test/support/assumption_generators.ex`,
`test/assumptions_meta_test.exs`), and the two reference rules
`avoid_graphemes_enum_count_with_predicate` / `no_codepoint_string_reverse`
as the template for any switch-gated ACCEPT.

## Single-file-testsuite watch-out (explicit)
Two places: (1) every `ACCEPT` path must split a copied single `<base>_test.exs`
into `_check`+`_fix` — already enforced by the prompt + the gate's
superseded-single-file deletion (inherited from stage 2). (2) A whole class of
followup entries was rejected ONLY for "failed accept gate (needs _check +
_fix)" (`no_guard_equality_for_pattern_match`, `no_identity_function_in_enum`,
`no_list_to_tuple_for_access`, `unused_variable`) — these are the cheapest
resurrections; the prompt's decision step 1 targets them first.

## Verification
1. `LIST=1 ./resurrect_loop.sh` — assert it lists real rule rows (e.g.
   `no_filter_then_map`, `no_rem_for_parity_check`,
   `no_guard_equality_for_pattern_match`) and omits the global-suites, the
   `lib/syntax.ex` REJECTED/DONE blocks, and the orphan `debug_ast_test`.
2. One gate-only row end-to-end (`./resurrect_loop.sh 1 0`, e.g.
   `no_identity_function_in_enum`): expect split tests → `ACCEPT` → rule + tests
   committed `<base>: resurrected` + `mix test` green + that `## <base>` section
   gone from `followup.md`.
3. One new-switch row (e.g. `no_range_comparison_for_membership`): expect
   `PROPOSE_SWITCH_NEW` → `### Assumption` appended to `proposed_assumptions.md`
   **and** a row to `proposed_rules_requiring_assumptions.md`, files reverted,
   section drained. Then a second row needing the *same* assumption →
   `PROPOSE_SWITCH_REUSE` → mapping row only, catalog unchanged. Negative checks: a
   REUSE naming a nonexistent catalog entry → transient retry; a NEW reusing an
   existing catalog name → transient retry.
4. One type-change row (`no_integer_to_string_digits`): expect `UNFIXABLE` →
   `stage3_unfixable.md`, section drained.
5. Sandbox check: confirm a session edit to `lib/assumptions.ex` trips
   confined-diff (c) and routes to KEEP (section stays in followup.md), not ACCEPT.
6. Idempotency / drain: after a non-KEEP row resolves, its `## <base>` section is
   gone from `followup.md`, so it is never picked again. A KEEP'd row stays in
   followup.md and is skipped only in-memory for the current run. Confirm the
   skip-listed narrative entries (global suites, DONE/REJECTED, orphans) survive.
   Re-run startup guard with a non-empty upstream queue → refuses.
7. `mix test` green after every ACCEPT commit (3213+ baseline).

## Unresolved questions
~~1. Pre-pass scope~~ — **resolved:** the loop auto-skips every `## ` section that
   lacks a `lib/(pattern|semantic|syntax)/*.ex` path (and DONE/REJECTED, and
   absent-from-sister), in `each_resurrectable`. No hand-curated skip-list.
~~2. semantic/syntax handling~~ — **resolved:** the loop handles all three kinds
   (`fix_range_step`, `unused_variable` included); `gate_accept` branches on kind
   for the test-shape check.
~~3. `PROPOSE_SWITCH` granularity~~ — **resolved:** catalog + mapping, two files,
   dedup'd one-to-many (`proposed_assumptions.md` + `proposed_rules_requiring_assumptions.md`).
~~4. Re-feed path after a human lands a switch~~ — **resolved:** manual, via
   **stage 1**; the human's deletion of the catalog entry + mapping rows un-skips
   the rules. Stage 3 owns no re-review pass.

## Open question (introduced by the drain change)
- **KEEP re-review across runs.** KEEP leaves the entry in followup.md and skips it
  only in-memory, so a fresh run re-reviews KEEP'd rows. Acceptable for now (run
  with a cap, or let it re-review). If it becomes noise, options: a `stage3_keep.md`
  ledger after all, or a lightweight in-followup marker — both were deliberately
  dropped to keep the output surface minimal.
