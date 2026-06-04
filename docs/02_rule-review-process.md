# How we check and accept rules

How we look over rules and let them into the main set. New rules show up on the
`evolution` branch (where an AI writes them). The one rule we never bend, and
everything below exists to protect it:

> **A fix must give the exact same answer for every input the user's promises
> admit. With no promises (`:strict`), that means every possible input.**

A "tidier" or "faster" rewrite that changes the answer on *even one* admitted
input is not an improvement — it's a bug. "Right for the usual case" is not good
enough.

The one escape hatch is a **safety switch** (`Credence.Assumptions`): a checkable
promise about the program's running data that a rule can declare via
`assumptions/0`. A rule may rely on a switch only after it's been shrunk so the
promise covers *only* the rare-text gap, and only with a property test proving
old == new across promise-satisfying inputs (see `docs/03-safety-switches.md`).
`:strict` makes zero promises, so it stays bit-identical for every input. The
`CONTEXT.md` "Project policy" section is the official statement of this; this doc
is the step-by-step way we make it stick.

## Why we have this process

The `evolution` branch piles up lots of AI-written rules. They compile and their
tests pass — but passing tests only prove the rule *does something*, not that
the something is safe, not a copy of an existing rule, or worth keeping. So a
person checks each rule by hand before it joins the main set. We take **one
rule at a time** (the rule file plus its test file(s)) and walk it through the
steps below.

## Setting up the branch and the to-do list

- **`evolution_accepted`** branches off **`main`**. We move checked rules into
  it one at a time *from* `evolution`. `main` stays untouched until a batch is
  ready.
- The **to-do list** is the difference between `evolution` and `main`, copied
  into **`docs/candidates.md`**. Work it **top to bottom**.
- A **set** is one rule plus its test file(s) — for example
  `lib/pattern/avoid_charlist_enum_at.ex` +
  `test/pattern/avoid_charlist_enum_at_test.exs`.
- When a set is done, **delete its lines from `docs/candidates.md`**. The
  shrinking file *is* the progress bar: whatever's left is whatever's still to
  do.

### One set at a time — the list is the plan

Only touch the set you're on right now. While working one rule you'll often
spot problems in *other* rules (a duplicate, a rule aimed at the wrong thing, a
shared file they both lean on). **Don't run off and fix those.** Jot down the
finding if it's worth remembering, leave the rule on the list, and deal with it
when the list gets there. We can't — and shouldn't — fix every rule at once.
The value is in giving each rule full attention one by one, and the list makes
sure nothing slips through. Undoing a little detour is cheaper than a
half-checked batch.

## The steps

For each rule, going top to bottom through `docs/candidates.md`:

1. **Copy the set in** from `evolution` to `evolution_accepted` (rule file +
   test file(s)), and delete its lines from `docs/candidates.md`.

2. **Run `mix test` right away — before judging anything.** A rule often can't
   stand on its own: the `evolution` branch may also have changed shared files
   (`lib/credence.ex`, `lib/rule_helpers.ex`, the rule list, etc.) that this
   rule needs. If the tests fail or the rule acts up because a supporting change
   is missing:
   - **Bring that supporting change over** — some or all of the change to that
     shared file, whatever this rule actually needs. The to-do list shows
     exactly what `evolution` did to it.
   - Or **just fix it directly** if copying the change would drag in unrelated
     clutter. Either way it's usually small — don't drop the rule over it.

   Write down any shared-file edits you bring over: later rules may need them
   too (or already have them), so check again when the same file shows up again.

3. **Read the rule and its tests.** Be sure you know exactly what code shape it
   matches and what it turns that into.

4. **Check for duplicates.** Search the existing rules for the same target
   functions or the same bad habit. If another rule already handles it, stop —
   either fold the new idea into the old rule or drop it.

5. **Check it's correct — the heart of the job.** Ask: *does the rewrite give
   the exact same answer as the original, for every possible value?* Don't think
   about it in the abstract — build the nasty inputs on purpose:
   - **Unicode:** plain ASCII, and the two ways of typing accented letters
     (one ready-made piece, or a letter plus a separate accent mark), and emoji
     built from several pieces, and flag symbols.
   - **Edge cases:** empty, one element, `nil`, a negative index.
   - **Wrong kind of value:** the *number* 7 vs. the *character* `"7"`,
     codepoints vs. graphemes (the small pieces a character is made of vs. the
     whole character you see), bytes vs. codepoints — the thing the rewrite
     produces has to be the same kind of value as the original.
   - **The variable you're touching is used somewhere else too** (see below).
   - **Side effects** in any part you might copy or move around.

   Run the before and after in `iex`/`elixir` and compare the real values. A
   green test suite is not proof of correctness; a `{before, after, before ==
   after}` check on the nasty input is.

6. **Decide what happens to the rule** based on what you found:

   | What you found | What you do |
   |---|---|
   | Same answer for every input | **Keep it.** |
   | Safe only on *some* of what it currently matches | **Narrow it** (see below). |
   | Safe only when a checkable promise about the data holds (and the leftover difference is *rare text*, not a plain bug) | **Gate it behind a switch** — shrink first, then declare the switch in `assumptions/0` and add a property test (`docs/03-safety-switches.md`). A type change can't be promised away. |
   | Right bad habit, wrong replacement | **Re-aim it** — point the fix at the correct function (one that gives the same kind of value), rename the rule if its name now lies, and keep the safe cases. |
   | No input is safe to fix | **Delete it** (or park it in `docs/unfixable_rules/` if it's still worth writing down). Never ship a rule that only warns — Credence has no warn-only mode. |

7. **Split and tidy the tests** (see "How tests are laid out").

8. **Check it works:** the rule's own test file(s) green, then the **whole
   suite** green (rules are found and run automatically, so a new or changed
   rule can affect the end-to-end tests).

## Narrowing: shrink a too-eager rule to its safe core

The most common outcome is a rule that's *almost* right: it fires on a wide
pattern, but only part of that pattern can be rewritten safely. Don't delete it
and don't ship it as-is — **narrow it**:

- Make `check/2` fire **only** on the cases that have a safe, same-answer fix.
- Write `fix_patches/2` for exactly those cases.
- The cases you drop aren't lost — they'll come back later. When a dropped case
  turns up again in the logs, you either grow this rule to cover it (once you've
  found a safe fix) or start a new sister rule for it. That's the normal life
  of a rule.

`check` and `fix` must agree: never flag a case the fix won't touch (that would
report a "problem" we refuse to fix). When unsure, have both sides ask the same
helper.

### Worked examples

- **`avoid_charlist_enum_at` — deleted.** It rewrote
  `Enum.at(String.to_charlist(s), i)` → `String.at(s, i)`. But
  `String.to_charlist` counts in codepoints (the small pieces, and it hands back
  a number) while `String.at` counts in graphemes (whole characters, and it
  hands back a string); the two ways of counting drift apart the moment a
  character is made of more than one piece. Its *only* fixable shape was the
  unsafe one, so there was nothing safe to shrink down to — deleted.

- **`no_grapheme_palindrome_check` — narrowed, then sharpened.** It spotted
  palindrome checks done two ways — with `String.graphemes` and with
  `String.to_charlist` — and rewrote both to `String.reverse`. The `graphemes`
  way is whole-character to whole-character and safe; the `to_charlist` way
  mixes the small pieces with whole characters and gives a different answer on
  accent-mark text (checked). We narrowed it to the `graphemes`-only way. A
  later pass also found and fixed a hidden bug in how it rewrote variables
  (below).

- **`no_integer_to_string_digits` — wrong target, left on the list for later.**
  While working a *different* rule we noticed this one rewrites to
  `Integer.digits`, which hands back the digit *numbers* (`[1, 0, 1, 0]`),
  while the original code hands back the digit *characters*
  (`String.to_charlist(Integer.to_string(10, 2)) == [49, 48, 49, 48]`) — wrong
  kind of value. The same-kind fix is `Integer.to_charlist/1,2`
  (`Integer.to_charlist(10, 2) == ~c"1010"`, checked equal for negatives, bases
  2–36, and zero), dropping the `String.graphemes` version as unfixable. But
  this rule was nowhere near the set we were on, so we **undid the rework and
  left it on the list** instead of fixing it off to the side — it gets done when
  the list reaches it. (See "One set at a time".)

## The "used somewhere else" trap

When a fix rewrites or removes a **variable**, check whether that variable is
used anywhere other than the spot you're fixing. Rewriting it in place quietly
changes those other uses too.

A real example from `no_grapheme_palindrome_check`: the old fix turned
`graphemes = String.graphemes(s)` into `graphemes = s`, always. If the code also
did `Enum.count(graphemes)`, that became `Enum.count(s)` on a string — a crash
at runtime. The fixed rule counts how many times the variable is used and picks
a path:

- used **only** in the spot being fixed → safe to drop or rewrite the variable;
- used **elsewhere too** → leave the variable alone and drop the original value
  straight into the fixed line instead (so the other uses don't change);
- if neither is safe (for example, dropping it in would run an effectful
  expression twice) → don't fix it, and don't flag it.

This "get the original value back, count the uses, drop the variable only when
nothing else needs it, keep it when something does" shape has come up in more
than one rule (`avoid_charlist_enum_at` had it before it was deleted;
`no_grapheme_palindrome_check` uses it now). If it shows up a third time, pull
it out into `RuleHelpers`.

## How tests are laid out

Split a rule's tests into two files, the way the repo does it:

- `test/pattern/<rule>_check_test.exs` — finding problems only. Says which
  inputs do and do **not** raise an issue (include the unsafe cases you
  deliberately skip as "no issue" tests, so the safety choice is locked in).
- `test/pattern/<rule>_fix_test.exs` — the rewrites.

**Fix tests compare exact strings:**

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

Grab the `expected` value from the rule's real output rather than typing it by
hand. Spacing and layout don't matter — `mix format` runs after all the rules —
so the point of the string compare is to pin down the *meaning* of the output,
not its layout. For "leaves it alone" cases the cleanest check is
`assert fix(code) == code`.

## Writing it down

A correctness decision isn't finished until it's written where it'll be read
again:

- **`CONTEXT.md` → Project policy** — the lasting statement of the rule (for
  example, "the answer must never change"; "don't swap codepoint operations for
  grapheme ones"). This is what a person or an agent reads before touching a
  rule.
- **`prompt.md`** — the instructions for the AI that writes rules, so the same
  unsafe rule isn't made again next time.
- **`docs/unfixable_rules/`** — parked rules kept as notes, each with the reason
  it can't be fixed.

When you find a new kind of unsafe rewrite, update all three: state the rule in
`CONTEXT.md`, teach the AI in `prompt.md`, and (if you're parking it) drop the
rule in `docs/unfixable_rules/` with the reason.
