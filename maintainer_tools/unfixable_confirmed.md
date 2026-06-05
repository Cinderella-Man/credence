# Confirmed-unfixable list

Stubs from `unfixable_unreviewed.md` that stage 2 (`stage_2_promote_non_fixable/`)
reviewed and **proved** have no safe, behaviour-preserving fix for any shape they
flag (or only a value-type-changing fix). Unlike `unfixable_unreviewed.md` — which
was auto-classified by the strict `unfixable_stub?` predicate and never reviewed —
every entry here is a distinct, freshly-proven correctness finding from an agent
that tried to author a fix and couldn't.

This is the durable queue for a later **manual** pass that distills each reason
into `CONTEXT.md` (policy) and `prompt.md` (so the rule-writing AI stops re-making
the same unsafe rewrites). The loop is sandboxed and never edits those shared docs.

Each entry records the rule path, its test file(s), the agent's reason, and the date.
## avoid_charlist_for_iteration — 2026-06-05
- Files:
  - `lib/pattern/avoid_charlist_for_iteration.ex`
  - `test/pattern/avoid_charlist_for_iteration_test.exs`
- Reason: to_charlist→graphemes is a value-type change (integer codepoints vs grapheme strings) on every input incl. ASCII; no safe subset.

