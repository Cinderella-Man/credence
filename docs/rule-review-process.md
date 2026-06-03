# Rule review & hardening process

How we evaluate and land rules contributed to the `evolution` branch (the
LLM-generated rule stream) into the main rule set. The driving principle is
simple and non-negotiable, and everything below is in service of it:

> **A fix must preserve behaviour for every input. If we can't preserve
> behaviour, we don't change the code.**

A "more idiomatic" or "faster" rewrite that changes the result on *any* input
is not an improvement — it's a bug. "Correct for the common case" is not
acceptable. See the Project policy section of `CONTEXT.md` for the canonical
statement; this doc is the working procedure that enforces it.

## Why this process exists

The `evolution` branch accumulates many machine-generated rules. They compile
and their tests pass, but passing tests only prove the rule does *something* —
not that the something is safe, non-duplicative, or worth shipping. Each rule
is reviewed by hand before it joins the main set. We take **one rule's file set
at a time** (the rule file + its test file(s)) and run it through the steps
below.

## The review steps

For each candidate rule:

1. **Read the rule and its tests.** Understand exactly what AST it matches and
   what it rewrites to.

2. **Duplication check.** Grep the existing rules for the same target
   functions / anti-pattern. If another rule already covers it, stop — either
   fold the new idea into the existing rule or drop it.

3. **Correctness audit — the core step.** Ask: *is the rewrite output-identical
   to the input for every possible value?* Construct the adversarial inputs,
   don't reason in the abstract:
   - Unicode: ASCII vs NFC vs NFD, combining marks, ZWJ emoji, flags.
   - Empty / single-element / nil / negative-index edge cases.
   - The variable being touched is used **elsewhere** (see below).
   - Side effects in any sub-expression we might duplicate or reorder.

   Run the before/after in `iex`/`elixir` and compare actual values. A green
   test suite is not evidence of correctness; a `{before, after, before ==
   after}` check on the adversarial input is.

4. **Decide the rule's fate** based on the audit:

   | Audit result | Action |
   |---|---|
   | Rewrite is behaviour-identical for all inputs | **Keep / accept.** |
   | Safe only on a *subset* of what it currently matches | **Narrow** (see below). |
   | No input is safely fixable | **Delete** it (or archive to `docs/unfixable_rules/` if the detection is still worth documenting). Never ship a check-only "warn" rule — the project has no warn-only mode. |

5. **Split and simplify the tests** (see "Test layout").

6. **Verify**: targeted test file(s) green, then the **full suite** green
   (rules are auto-discovered and run in the pipeline, so a new/changed rule
   can affect integration tests).

## Narrowing: shrink a greedy rule to its provably-safe core

The most common outcome is a rule that is *almost* right: it fires on a broad
pattern, but only part of that pattern can be rewritten safely. Don't delete
it and don't ship it as-is — **narrow it**:

- Restrict `check/2` to fire **only** on the cases that have a
  behaviour-preserving fix.
- Implement `fix_patches/2` for exactly those cases.
- The cases you drop are not lost — they resurface naturally later. When a
  dropped case shows up again in the logs, you either expand this rule to cover
  it (once you've found a safe fix) or spin up a new companion rule. That is
  the normal life-cycle of a rule.

`check` and `fix` must agree: never flag a case the fix won't touch (that would
report an "issue" we refuse to fix). When in doubt, both sides consult the same
classification helper.

### Worked examples

- **`avoid_charlist_enum_at` — deleted.** It rewrote
  `Enum.at(String.to_charlist(s), i)` → `String.at(s, i)`. But
  `String.to_charlist` indexes codepoints (returns an integer) while
  `String.at` indexes graphemes (returns a string); the index spaces diverge on
  any multi-codepoint grapheme. Its *only* fixable shape was the unsafe one, so
  there was nothing to narrow to — deleted.

- **`no_grapheme_palindrome_check` — narrowed, then sharpened.** It detected
  both `String.graphemes`-based and `String.to_charlist`-based palindrome
  comparisons and rewrote both to `String.reverse`. The `graphemes` path is
  grapheme→grapheme and safe; the `to_charlist` path is codepoint→grapheme and
  flips on NFD input (verified). We narrowed it to the graphemes-only path. A
  later pass also found and fixed a latent bug in its binding rewrite (below).

- **`no_integer_to_string_digits` — deleted.** Different mechanism, same rule:
  `String.to_charlist(Integer.to_string(10, 2))` is `[49, 48, 49, 48]` (ASCII
  codes) but `Integer.digits(10, 2)` is `[1, 0, 1, 0]` (values). Not equal, no
  safe fix — deleted.

## The "used elsewhere" trap

When a fix rewrites or removes a **variable binding**, check whether that
variable is referenced anywhere besides the spot you're fixing. Rewriting the
binding in place silently changes those other uses.

Real example from `no_grapheme_palindrome_check`: the old fix turned
`graphemes = String.graphemes(s)` into `graphemes = s` unconditionally. If the
code also did `Enum.count(graphemes)`, that became `Enum.count(s)` on a binary
— a runtime crash. The corrected rule counts references and branches:

- used **only** in the fixed expression → safe to drop / rewrite the binding;
- used **elsewhere** → leave the binding intact and inline the original value
  into the fixed expression instead (so the other uses are untouched);
- if neither is safe (e.g. inlining would duplicate an effectful expression) →
  don't fix, and don't flag.

This "recover the original value, count references, drop the binding only when
dead, keep it when still used" shape has recurred across rules
(`avoid_charlist_enum_at` had it before deletion; `no_grapheme_palindrome_check`
uses it now). If it shows up a third time, extract it into `RuleHelpers`.

## Test layout

Split a rule's tests into two files following the repo convention:

- `test/pattern/<rule>_check_test.exs` — detection only. Asserts which inputs do
  and do **not** produce issues (include the deliberately-skipped unsafe cases
  as negative tests, so the safety decision is locked in).
- `test/pattern/<rule>_fix_test.exs` — the rewrites.

**Fix tests use a plain exact-string comparison:**

```elixir
code = """
graphemes = String.graphemes(s)
graphemes == Enum.reverse(graphemes)
"""

expected = """
s == String.reverse(s)
"""

assert fix(code) == expected
```

Capture the `expected` value from the rule's actual output rather than
hand-writing it. Formatting differences don't matter — `mix format` runs after
all rules are applied — so the goal of the string compare is to pin the
*semantic* shape of the output, not its layout. For "leaves it alone" cases the
cleanest assertion is `assert fix(code) == code`.

## Documentation & guardrails

A correctness decision isn't done until it's written where it will be re-read:

- **`CONTEXT.md` → Project policy** — the durable statement of the rule (e.g.
  "behaviour preservation is absolute"; "codepoint↔grapheme rewrites are
  forbidden"). This is what a human or agent consults before touching a rule.
- **`prompt.md`** — the generator's guardrails, so the same unsafe rule isn't
  produced again on the next pass.
- **`docs/unfixable_rules/`** — archived rules kept as reference, with the
  reason each can't be fixed.

When you discover a new class of unsafe rewrite, update all three: state the
policy in `CONTEXT.md`, teach the generator in `prompt.md`, and (if archiving)
drop the rule in `docs/unfixable_rules/` with its rationale.
