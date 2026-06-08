# Resurrect one rejected followup rule (stage 3)

You are re-examining a single AI-written rule for the Credence project that was
**previously rejected** into `followup.md` (stage 1 or 2 could not promote it). A
wrapper script owns everything else; you do exactly one rule and report a verdict.
**The rule, its test file(s), the original rejection reason, the approved safety
switches (`lib/assumptions.ex`), and the pending proposed-assumption catalog are
all in the SET BRIEFING appended at the end of this prompt.** Read it first.

## The one bar (unchanged across all stages)
A fix must give the **exact same answer for every admitted input**. With no
promises (`:strict`) that means **every possible input**; with a switch on, it
means every input that switch's promise admits. The 0.7.0 invariant: *Credence
never changes behaviour on any input the stated promises admit.* A green suite
proves a rule *does something*, not that it is safe. This is the bar you defend.

## What "resurrect" means
The rule was rejected for a reason (in the briefing). Your job is to decide
whether that reason can now be **overcome** by one of the moves below — cheapest
first — or whether it is genuinely terminal. Any safe core, however slim, beats
none.

## Hard constraints (the sandbox)
- **No git, ever.** You cannot commit, branch, diff, or revert. Your only output
  channel is the verdict file (last step).
- **Edit/create ONLY this rule's own files:** `lib/<kind>/<base>.ex` and its tests
  `test/<kind>/<base>*_test.exs` (incl. a new `<base>_property_test.exs`). Touch
  nothing else.
- **NEVER edit shared files** — `lib/assumptions.ex`, `lib/credence.ex`,
  `lib/rule_helpers.ex`, the phase modules, `CHANGELOG.md`, or any curated suite.
  New switches are **propose-only**: you DESIGN one, you never land it. (The
  wrapper's confined-diff gate will reject — and KEEP — any session that edits a
  shared file, so editing `lib/assumptions.ex` cannot ACCEPT.)
- **No scratch files.** No `/tmp`, no throwaway tests. Verify language semantics
  with inline `elixir -e '...'`; verify rule behaviour in the rule's real test file
  and run `mix test`.

## Procedure
1. **Run `mix test` first** to see the current state.
2. **Read `check/2`, the tests, and the original rejection reason.** Enumerate
   every code shape `check/2` flags and pin down *exactly* what divergence caused
   the rejection.
3. **Prove same-answer.** Before any ACCEPT or REUSE, paste a
   `{before, after, before == after}` comparison (run via `elixir -e '...'`) over
   the relevant trap classes — codepoint vs grapheme; negative index; non-list
   enumerables (Range/Map/MapSet); float-vs-int and number `7` vs char `"7"`;
   empty/single/nil; sort stability; side-effects/double-eval; value-type changes.

## The decision ladder (stop at the first that applies)
1. **Gate-only miss** — the rejection was *only* "failed accept gate (needs
   `_check` + `_fix`)" and the fix is already behaviour-preserving → split the
   single `<base>_test.exs` into `_check` + `_fix`, verify, **ACCEPT**.
2. **Missed fixable core** — narrow `check` + `fix` to a provably output-identical
   subset; keep the dropped shapes as explicit "no issue" check tests; ship split
   tests → **ACCEPT**.
3. **Existing approved switch** — if the only residual divergence is covered by a
   switch **already in `lib/assumptions.ex`** (e.g. multi-codepoint graphemes →
   `single_codepoint_graphemes`): shrink-first so the promise covers only that gap,
   add `def assumptions, do: [:<switch>]`, author
   `test/<kind>/<base>_property_test.exs` (StreamData via the matching
   `AssumptionGenerators` generator), verify → **ACCEPT**. (`mix test` enforces
   `assumptions_meta_test`.)
4. **Reuse a PENDING proposed assumption** — if a switch in the briefing's pending
   catalog, **with its promise UNCHANGED**, fully covers your residual divergence:
   you cannot ACCEPT (it is not landed yet), but you must run the **same
   `{before, after, before==after}` proof** as ACCEPT, under that promise, then
   report **`PROPOSE_SWITCH_REUSE`**. If the existing promise would need *widening*
   to cover your rule, that is NOT a reuse → go to 5.
5. **Propose a NEW assumption** — only a genuinely new, checkable promise about
   **running data** (not types — e.g. non-negative indices, proper-list
   enumerables, integer numbers, no comparator-tie elements) rescues it → report
   **`PROPOSE_SWITCH_NEW`** with a full design.
6. **Terminal** — no safe core and no switch helps:
   - a **value-type** change (e.g. charlist→integers) → **`UNFIXABLE`**;
   - a side-effect / double-eval / sort-stability divergence that cannot be framed
     as a data promise → **`UNFIXABLE`**;
   - needs an out-of-set / curated-suite change, is a true duplicate of an accepted
     rule, or is inconclusive → **`KEEP`** (the wrapper leaves the entry in
     `followup.md` as the human-attention residue; nothing is recorded or committed).

## Test shape (you own this)
- **pattern:** exactly `test/pattern/<base>_check_test.exs` (finding only, incl.
  the deliberately-dropped unsafe cases as "no issue") + `test/pattern/<base>_fix_test.exs`
  (exact-string rewrites). The wrapper deletes a superseded single `<base>_test.exs`.
- **semantic/syntax:** the matching `_check`/`_analyze` + `_fix` pair (or a single
  `<base>_test.exs` for syntax).
- **switch-gated ACCEPT** also needs `test/<kind>/<base>_property_test.exs`.
- **Every fix-test assertion compares the WHOLE output** — `assert fix(code) ==
  expected` (or `== code` for a no-op). Grab each `expected` from the rule's real
  output, not by hand. **No** `=~`, `String.contains?`/`match?`,
  `starts_with?`/`ends_with?`, `String.split` slicing, or `Regex.*`. Always use
  triple-quoted heredocs; never single-quoted `\n`-escaped strings.

## Last action — the verdict (do this exactly once, last)
Write `maintainer_tools/_verdict`. The FIRST line is always the routing header.

- One line, nothing after it:
  - `ACCEPT`
  - `UNFIXABLE: <one-line reason>`
  - `KEEP: <one-line reason>`

- `PROPOSE_SWITCH_REUSE: <existing_catalog_name> | <one-line reason>` — then a
  `### Rule` section (NO `### Assumption` section — you are reusing, not redesigning):
  ```
  PROPOSE_SWITCH_REUSE: proper_list_enumerable | reduce over a proper list only
  ### Rule
  - Narrowing: <the shrink-first move that makes this rule fit the existing promise>
  - Property test: <sketch of test/<kind>/<base>_property_test.exs + which AssumptionGenerators generator>
  ```

- `PROPOSE_SWITCH_NEW: <new_name> | <one-line reason>` — then BOTH a `### Assumption`
  section (the reusable promise, registry-shaped) and a `### Rule` section (this
  rule's per-rule narrowing + property sketch):
  ```
  PROPOSE_SWITCH_NEW: proper_list_enumerable | Enum.reduce/3 over a proper list
  ### Assumption
  - Default: false
  - Summary: <one-line promise about RUNNING DATA the switch makes>
  - Rationale: <what class of running-data fact it promises; why it is checkable about data, not types>
  ### Rule
  - Narrowing: <the shrink-first move that makes this rule fit the new promise>
  - Property test: <sketch of test/<kind>/<base>_property_test.exs + the generator it needs>
  ```

Rules the wrapper enforces (a violation is treated as a confused session and
retried, NOT recorded):
- `PROPOSE_SWITCH_NEW` whose `<new_name>` **already exists** in the pending catalog
  → you meant REUSE.
- `PROPOSE_SWITCH_REUSE` that names a catalog entry **not present** in the briefing,
  or that carries an `### Assumption` block.
- Either PROPOSE verdict missing its required section(s).

Write nothing else to that file, and **never run git**. The wrapper reads the
verdict, independently re-verifies, and decides what to commit.
