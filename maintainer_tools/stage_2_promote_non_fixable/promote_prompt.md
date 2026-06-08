# Promote one check-only stub (stage 2)

You are reviewing a single AI-written **`pattern`** rule for the Credence project,
following `docs/02_rule-review-process.md`. A wrapper script owns everything else;
you do exactly one rule and report a verdict. **The rule and its test file(s) are
named in the SET BRIEFING appended at the very end of this prompt.** Read it first.

## What this rule is
This rule is a **check-only STUB**: its `check/2` fires, but `fix_patches/2` is the
dead `[]` form. It was auto-classified *unfixable* by a strict static predicate and
**never reviewed**. Your job: decide whether a **behaviour-preserving** fix — one
that gives the **exact same answer for every admitted input** (no promises /
`:strict` ⇒ *every possible input*) — can be authored for **all or a narrower
subset** of what `check/2` flags. **Any safe core, however slim, is worth
promoting** — any rule beats none. One stub → at most one rule (no splitting).

## The one bar
A fix must give the **exact same answer for every admitted input**. A tidier or
faster rewrite that changes the answer on even one admitted input is a bug, not an
improvement. A green suite proves a rule *does something*, not that it's safe. This
is the bar you are defending.

## Hard constraints (the sandbox)
- **No git, ever.** You cannot commit, branch, diff, or revert. The wrapper does
  all of that. Your only output channel is the verdict file (last step).
- **Edit/create ONLY this rule's own files**: `lib/pattern/<base>.ex` and its test
  files `test/pattern/<base>*_test.exs`. Touch nothing else.
- **Shared-file changes are out of scope.** Supporting files (`lib/credence.ex`,
  `lib/rule_helpers.ex`, the phase modules, …) are already reconciled. If a fix
  would require changing anything outside this rule, **do not do it** — write
  `FOLLOWUP` instead.
- **No scratch files.** No `/tmp`, no throwaway test files. Verify language
  semantics with inline `elixir -e '...'`; verify rule behaviour by asserting it in
  the rule's real test file and running `mix test`.
- Rules auto-register (the phase discovers any compiled module implementing the
  `Rule` behaviour) — you never edit a registry.

## Procedure
1. **Run `mix test` first**, before judging anything, to see the current state.
2. **Read `check/2` and the existing tests.** Enumerate every code shape `check/2`
   flags — be precise about what it matches.
3. For each flagged shape, find the **canonical replacement** and **prove
   same-answer**. **Mandatory before ACCEPT:** paste a `{before, after, before ==
   after}` comparison (run via `elixir -e '...'`) for the relevant trap classes —
   whichever this rule can hit:
   - **codepoint vs grapheme** (Unicode: ASCII, precomposed vs combining accents,
     multi-codepoint emoji, flags),
   - **negative index** (e.g. `-1` end-vs-before-last differences),
   - **non-list enumerables** (Range / Map / MapSet — many list ops *raise* on these),
   - **float-vs-int** (and number `7` vs char `"7"`),
   - **empty / single-element / nil**,
   - **sort stability** (strict `</>` vs `<=/>=` reorders equal keys),
   - **side effects / double-eval** (a moved or duplicated expression evaluated a
     different number of times),
   - **value-type changes** — if the only fix changes the *kind* of value returned,
     it **cannot be narrowed away**: that is `UNFIXABLE`.
4. **Narrow `check/2`** to fire **only** on the shapes with a safe, same-answer fix.
   Keep the dropped shapes as explicit **"no issue"** check tests so the safety
   choice is locked in. Author `fix_patches/2` for exactly the safe shapes.
   **`check` and `fix` must agree** — never flag a case the fix won't touch.
5. **Tests — the required pattern shape (you own this):** exactly two files:
   - `test/pattern/<base>_check_test.exs` — finding only, **including** the
     deliberately-dropped unsafe cases as "no issue".
   - `test/pattern/<base>_fix_test.exs` — exact-string rewrites.
   If the stub shipped a single `<base>_test.exs` or only one half, split/complete
   it into this pair (the wrapper deletes the superseded single).
   Grab each `expected` string from the rule's **real output** (run it), not by
   hand. **Every fix-test assertion compares the WHOLE output** — `assert fix(code)
   == expected`, or `assert fix(code) == code` for a no-op. **Never** check a
   fragment. That bans `=~`, `String.contains?`, `String.match?`/`Regex.match?`,
   `String.starts_with?`/`String.ends_with?`, and `String.split` + `Enum.at`
   slicing — every one lets an unintended change slip through. Pin the entire string
   with `==`. **Always use triple-quoted heredocs** (`"""…"""`) for `code` and
   `expected`; **never** single-quoted strings with `\n` escapes.
6. **Verify green:** the rule's own tests, then the **whole** `mix test` suite (a
   changed rule can affect the auto-discovered end-to-end suites). If you can't get
   the whole suite green without touching files outside this rule → `FOLLOWUP`.

## Acceptance bar (`pattern`)
Behaviour-preserving: the same output for **every** admitted input; a real
`fix_patches` (never a constant `[]`); split `_check` + `_fix` tests that agree.

## Last action — the verdict (do this exactly once, last)
Write the file `maintainer_tools/_verdict` with **exactly one** of:

- `ACCEPT` — a real, safe fix is authored (for all or a narrower core), the split
  `_check`/`_fix` tests are present and pin whole-string output, the diff is
  confined to this rule's files, and the whole `mix test` suite is green.
- `UNFIXABLE: <one-line reason>` — you proved there is **no** safe,
  behaviour-preserving fix for **any** shape it flags (or the only fix changes a
  value's **type**). This is the genuine correctness verdict — use it only when
  you've shown it, not when you're unsure.
- `FOLLOWUP: <one-line reason>` — anything else: the rule **duplicates** an already
  accepted rule (fold/drop), it needs an **out-of-set shared-file** change, or the
  review is **inconclusive**.

Write nothing else to that file, and **never run git**. The wrapper reads the
verdict, independently re-verifies, and decides what to commit.
