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
switch and writes it to a human queue. Terminal outcomes go to **separate
stage-3 files** (not stage 1/2's `unfixable_confirmed.md`).

## Architecture (clone of stage 2, repointed)
New dir `maintainer_tools/stage_3_resurrect_followups/`. Same skeleton as
`stage_2_promote_non_fixable/`: wrapper owns ALL git + list edits; session is
sandboxed (no git), allowed tools `Read Edit Write Grep Glob Bash(mix test:*)
Bash(mix format:*) Bash(elixir:*)`; sole output channel is one line in
`maintainer_tools/_verdict`; per-row `.review_logs/<base>.log`; self-heal +
retry/backoff verbatim from stage 2.

### Queue model (differs from stage 2)
followup.md is narrative markdown, NOT a flat path list. So:

- **Pre-pass `extract_followup_candidates.sh`** (markdown distiller, analog of
  `move_unfixable_out.sh`): walk each `## ` section of `followup.md`; **skip** a
  section if it (a) already bears a `- Stage 3:` resolution marker, (b) bears a
  `DONE`/`REJECTED` marker, (c) has no `lib/(pattern|semantic|syntax)/*.ex` path
  in its `- Files:` (global-suite / orphan / syntax.ex narrative entries), or (d)
  the rule file is absent from `$SISTER`. For the rest, strip bullets/backticks
  and emit the rule line + its test line(s) into a flat
  **`followup_unreviewed.md`** (candidates.md shape). Idempotent; `DRY_RUN=1`
  supported; one commit.
- Stage 3 then drains `followup_unreviewed.md` in place with the same line-strip
  helpers (`copy_next_candidate.sh`, `remove_from_list_*` — copies repointed to
  this queue). The narrative `followup.md` stays the durable human archive,
  **annotated** (never line-mangled) by a `- Stage 3: <VERDICT> (<date>)` marker.

### Briefing (one addition over stage 2)
`build_briefing` additionally greps `followup.md` for the `## <base>` section and
includes its original **`- Reason:`** text — the session needs *why it was
rejected* as the starting hypothesis for what a narrowing/switch must overcome.
Mode classify stays greenfield/delta off `git status` as in stage 2.

### Verdict contract (4-way + transient)
Session writes exactly one line to `_verdict`:

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
- `PROPOSE_SWITCH: <name> | <reason>` — only a **new** assumption rescues it (a
  checkable promise about RUNNING DATA, not types — e.g. non-negative indices,
  proper-list enumerables, integer numbers, no comparator-tie elements). Session
  does NOT touch `lib/assumptions.ex`; it writes the design (name, default,
  one-line promise, the shrink-first narrowing, property-test sketch) for a human.
- `UNFIXABLE: <reason>` — no safe core and no switch helps: **type** change
  (charlist→integers, e.g. `no_integer_to_string_digits`), or side-effect /
  double-eval / sort-stability that can't be framed as a data promise.
- `KEEP: <reason>` — needs an out-of-set / curated-suite change, is a true
  duplicate of an accepted rule, or is inconclusive. Stays archived.
- no/garbage verdict → transient agent error → revert, stay on row, retry/backoff
  (verbatim stage 2). gate-fail / unrecognized verdict → routed to **KEEP**
  (never a silent promote).

### Routing → separate stage-3 files
| Verdict | Files kept? | Records to | Commit msg | followup.md marker |
|---|---|---|---|---|
| ACCEPT | yes (promoted) | `resurrected.md` | `<base>: resurrected` | `Stage 3: ACCEPT` |
| PROPOSE_SWITCH | reverted | `switch_proposals.md` | `<base>: switch proposed` | `Stage 3: PROPOSE_SWITCH` |
| UNFIXABLE | reverted | `stage3_unfixable.md` | `<base>: confirmed unfixable (stage 3)` | `Stage 3: UNFIXABLE` |
| KEEP | reverted | `stage3_keep.md` | `<base>: stage 3 keep` | `Stage 3: KEEP` |

All four strip the entry from `followup_unreviewed.md` and append the marker line
under the `## <base>` section of `followup.md` (new helper
`mark_followup_section.sh`), so a future pre-pass skips it (idempotent). ACCEPT
keeps + `git add`s the rule, all `test/<kind>/<base>*` (incl. new `_property_test`),
deletes any superseded single `<base>_test.exs`.

### Gate (`gate_accept`, near-verbatim stage 2)
Reused: rule-exists + not-a-stub (a), pattern needs `_check`+`_fix` (b),
informational `=~` scan (b2), **confined diff (c)**, full `mix test` (d). Two
deltas:
- (b+) if the rule file declares a non-empty `assumptions/0` (grep
  `def assumptions, do: [:`), also require `test/<kind>/<base>_property_test.exs`
  to exist (else clear gate message; `mix test` would red anyway via meta-test).
- (c) **unchanged on purpose** — this is what enforces propose-only: a session
  that edits `lib/assumptions.ex`/`CHANGELOG.md` fails confined-diff → KEEP. The
  `<base>_property_test.exs` is owned by `<base>` (prefix match in `owner_base`)
  so it passes.

### Startup guard
Refuse to run until **both** `candidates.md` and `unfixable_unreviewed.md` are
empty (followup.md is appended by stages 1 AND 2 — review only after they settle).

## Files to create (all under `maintainer_tools/stage_3_resurrect_followups/`)
- `resurrect_loop.sh` — clone of `stage_2/promote_loop.sh`; repoint
  `CANDIDATES=followup_unreviewed.md`; new outputs; 4-way routing
  (`accept`/`propose_switch`/`stage3_unfixable`/`keep`); briefing reason-injection;
  two-empty startup guard.
- `resurrect_lib.sh` — byte-copy of `promote_lib.sh` (`rule_kind/base`,
  `group_tests`, `owner_base`, `is_unfixable_stub`).
- `resurrect_prompt.md` — new; the decision ladder + hard constraints
  (no git; edit ONLY set files; NEVER edit `lib/assumptions.ex`/`lib/credence.ex`/
  `lib/rule_helpers.ex`/curated suites; `mix test` first; whole-string `==`
  heredoc fix tests; split `_check`/`_fix`; codepoint↔grapheme bans; mandatory
  `{before, after, before==after}` `elixir -e` proof over trap classes before
  ACCEPT) + the 4-way verdict contract.
- `extract_followup_candidates.sh` — markdown-section pre-pass → `followup_unreviewed.md`.
- `mark_followup_section.sh` — append `- Stage 3: <verdict> (<date>) — <reason>`
  under a `## <base>` section.
- `copy_next_candidate.sh`, `remove_from_list_keep_files.sh`,
  `remove_from_list_revert_files.sh` — copies, repointed to `followup_unreviewed.md`.
- `README.md` — purpose, preconditions (stages 1&2 drained), verdict table,
  propose-only note, run instructions.
- Queue/record files created empty: `maintainer_tools/followup_unreviewed.md`,
  `resurrected.md`, `switch_proposals.md`, `stage3_unfixable.md`, `stage3_keep.md`.

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
1. `DRY_RUN=1 ./extract_followup_candidates.sh` — assert it enqueues real rule
   entries (e.g. `no_filter_then_map`, `no_rem_for_parity_check`,
   `no_guard_equality_for_pattern_match`) and SKIPS the global-suites, the
   `lib/syntax.ex` REJECTED/DONE blocks, and the orphan `debug_ast_test`.
2. One gate-only row end-to-end (`./resurrect_loop.sh 1 0`, e.g.
   `no_identity_function_in_enum`): expect split tests → `ACCEPT` →
   `resurrected.md` line + commit `<base>: resurrected` + `mix test` green +
   `followup.md` section marked.
3. One new-switch row (e.g. `no_range_comparison_for_membership`): expect
   `PROPOSE_SWITCH` → designed entry in `switch_proposals.md`, files reverted,
   queue drained, section marked.
4. One type-change row (`no_integer_to_string_digits`): expect `UNFIXABLE` →
   `stage3_unfixable.md`.
5. Sandbox check: confirm a session edit to `lib/assumptions.ex` trips
   confined-diff (c) and routes to KEEP, not ACCEPT.
6. Idempotency: re-run the pre-pass after a row resolves → no-op (marked section
   skipped). Re-run startup guard with a non-empty upstream queue → refuses.
7. `mix test` green after every ACCEPT commit (3213+ baseline).

## Unresolved questions
1. Pre-pass scope: auto-skip every `## ` section that lacks a
   `lib/(pattern|semantic|syntax)/*.ex` path (current plan), or hand-curate a
   skip-list for borderline entries first?
2. Should stage 3 also handle **semantic/syntax** followup entries
   (`fix_range_step`, `unused_variable`), or pattern-only for the first cut?
3. `PROPOSE_SWITCH` granularity: one shared `switch_proposals.md` (current), or
   one file per proposed switch so a human can pick them off independently?
4. After a human lands a proposed switch, is re-feeding that rule back through
   **stage 1** the intended path, or should stage 3 own a re-review pass?
