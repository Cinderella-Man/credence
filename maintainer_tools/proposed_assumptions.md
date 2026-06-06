# Proposed assumptions (stage 3 — dedup catalog)

Designs for **new safety switches** that stage 3 found would rescue one or more
rejected followup rules, but which a human must land into `lib/assumptions.ex`.
Each `## <name>` entry is registry-shaped (`- Default:` / `- Summary:` /
`- Rationale:`) so it can be pasted almost verbatim into the `@registry`. One
entry per *unique* assumption; the rules waiting on it are listed in
`proposed_rules_requiring_assumptions.md` (keyed by `- Assumption:`).

This file is **injected into every stage-3 session** alongside `lib/assumptions.ex`
so a session can REUSE a pending design instead of coining a near-duplicate.

## Landing one (the load-bearing human step)
When you land an assumption here into `lib/assumptions.ex`:
1. **delete** its `## <name>` entry from this file, AND
2. **delete** every row in `proposed_rules_requiring_assumptions.md` whose
   `- Assumption:` names it.

That deletion is what removes those rule bases from the stage-3 pre-pass skip-set,
so re-feeding them through **stage 1** (now that the switch is approved) resurrects
them. Skip the deletion and those rules stay permanently stranded.

<!-- entries appended below by resurrect_loop.sh -->
