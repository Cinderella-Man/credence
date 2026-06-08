# Stage 3 — resurrect followups

A share-nothing re-examination of the rules rejected into `../followup.md` by
stages 1 and 2 (~40 rules dropped for non-behaviour-preservation, gate-only
test-shape misses, type changes, …). For each, one fresh, sandboxed (no-git)
Claude session decides whether the rejection can now be **overcome** — by splitting
a single-file testsuite, narrowing to a missed fixable core, reusing an existing
switch, or (when only a *new* assumption would rescue it) designing a **proposal**
for a human to land. The 0.7.0 invariant governs every verdict: *Credence never
changes behaviour on any input the stated promises admit*
(`docs/03-safety-switches.md`).

New switches are **propose-only**: the session designs one and writes it to a human
queue; it NEVER edits `../../lib/assumptions.ex` / `CHANGELOG.md`. The wrapper's
confined-diff gate enforces this — a session that edits a shared file fails the
gate and is KEPT, never promoted.

The loop **drains `../followup.md` directly** — there is no intermediate flat
queue. A "row" is one resurrectable `## <base>` section.

## Preconditions
- **Stages 1 AND 2 done** — both `../candidates.md` and `../unfixable_unreviewed.md`
  must be empty (`followup.md` is appended by both; review only after they settle).
  `resurrect_loop.sh` enforces this with a startup guard and aborts otherwise.
- `$SISTER` present (default `../../credence_evolution`, on the `evolution` branch).

## Queue model
`followup.md` is the input AND it **drains as the loop works through the list**:
every verdict except KEEP removes the resolved `## <base>` section (a clean
whole-section delete). A section is a row when it bears no DONE/REJECTED marker,
has a `lib/(pattern|semantic|syntax)/*.ex` path, and that rule exists in `$SISTER`.
The skip-listed narrative entries (global suites, DONE/REJECTED blocks, orphans)
are never picked and so remain; KEEP'd rows also stay. So `followup.md` shrinks
toward only the "out of scope / needs a human" residue.

Preview the rows the loop would process (no session, no writes):
```
LIST=1 ./resurrect_loop.sh
```

## Verdict & routing
The session writes `../_verdict`. The first line is the routing header; for the two
PROPOSE verdicts a design payload follows (see `resurrect_prompt.md`).

| Verdict | followup.md | In-set files | Output |
|---|---|---|---|
| `ACCEPT` | section removed | **keep** | rule lands in the tree (record = tree + git log) |
| `PROPOSE_SWITCH_NEW: n \| why` | section removed | revert | `../proposed_assumptions.md` (design) **+** `../proposed_rules_requiring_assumptions.md` (row) |
| `PROPOSE_SWITCH_REUSE: n \| why` | section removed | revert | `../proposed_rules_requiring_assumptions.md` (row) only |
| `UNFIXABLE: why` | section removed | revert | `../stage3_unfixable.md` |
| `KEEP: why` | **left in place** | revert | none — stays in followup.md, skipped for the rest of the run |

Commits (single commit per resolved row, then push): `<base>: resurrected` /
`<base>: switch proposed (n)` / `<base>: reuses proposed switch (n)` /
`<base>: confirmed unfixable (stage 3)`. **KEEP makes no commit** (nothing changed —
files reverted, followup.md untouched).

- `ACCEPT` must pass the re-verify **gate**: the fix is real (not a stub), split
  `_check`/`_fix` tests exist, a rule that declares `assumptions/0` also ships a
  `<base>_property_test.exs`, the diff is **confined** to the rule's files, and the
  whole `mix test` suite is green.
- The wrapper does **zero** dedup — the session decides, semantically, whether an
  approved switch (→ ACCEPT), a pending catalog entry (→ REUSE), or neither (→ NEW)
  covers its residual divergence. REUSE carries the same `{before, after,
  before==after}` proof obligation as ACCEPT, just unlanded, against the catalog
  promise verbatim. A too-narrow existing promise → NEW (humans merge later).
- **Gate failures and unrecognized verdicts default to KEEP** (left in followup.md),
  never to a promote.
- A **missing** verdict (crash/token-limit) OR a **confused-session** signal (NEW
  naming an existing catalog entry, REUSE carrying an `### Assumption` block, REUSE
  naming an unresolved entry, a missing required section) is *transient*: the row's
  files are reverted and it stays put, retrying with backoff.

KEEP'd rows are skipped only **in memory for the current run** — a fresh run will
re-review them (they are still in followup.md). Run with a cap, or accept the
re-review, if you do not want that.

## Landing a proposed switch (manual, human-driven)
Stage 3 owns no feedback loop. When you land an assumption from
`../proposed_assumptions.md` into `lib/assumptions.ex`, **delete its catalog entry
and the matching rows in `../proposed_rules_requiring_assumptions.md`**, then
re-feed those rule bases through **stage 1** (now that the switch is approved). The
rules are no longer in followup.md (Stage 3 drained them when it proposed), so the
proposed-rules file is their record until you re-feed them.

## Run
```
LIST=1 ./resurrect_loop.sh                       # preview pending rows
./resurrect_loop.sh [cap] [wait_min]             # cap=0 → until none left; wait_min default 15
SISTER=/path CLAUDE_MODEL=… ./resurrect_loop.sh
```
Each row prints a one-line digest; per-row agent transcripts land in
`.review_logs/<base>.log`.

## Per-script index
- `resurrect_loop.sh` — orchestrator. Drains followup.md directly (`split_sections`
  / `each_resurrectable` / `next_set` / `clear_followup_section`), injects the
  rejection reason + `lib/assumptions.ex` + the catalog into the briefing, parses
  the multi-line `_verdict`, runs the 5-way routing with NEW/REUSE handlers and
  confused-session transient retries, and applies the `(b+)` property-test gate
  delta. `LIST=1` previews.
- `resurrect_prompt.md` — the decision ladder + the 5-way verdict contract with the
  exact `_verdict` payload formats (`### Assumption` / `### Rule`).
- `resurrect_lib.sh` — `rule_kind` / `rule_base` / `is_unfixable_stub`.
