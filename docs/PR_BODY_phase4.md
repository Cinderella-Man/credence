# Phase 4 — accept the evolution cycle

Closes the acceptance cycle planned in `docs/16`. 286 commits: 116 rule
acceptances from the stage-1 drain, then the disposition of all 143 rejected
rules, then the repairs that disposition uncovered.

Open at: https://github.com/Cinderella-Man/credence/compare/main...evolution_accepted

## The part that matters most: nine live shipped defects, in seven rules

These were in `lib/` and corrupting user source. Every one is verified by an
executed probe through the real pipeline, before and after.

| rule | defect |
|---|---|
| `Semantic.NoCaptureAsBitwiseAnd` | `flags & 0xFF` → `Bitwise.band(flags, 0)xFF` — same for `0b`, `0o`, `1_000` |
| `Syntax.FixDivRem` | a whole `def` head swallowed into the left operand |
| `Syntax.FixDivRem` | rewrote inside string literals |
| `Semantic.NoBareReturnInUnless` | early exit deleted rather than restructured — **silent wrong answer** |
| `Syntax.FixPythonModulo` | rewrote inside string literals |
| `Syntax.FixPythonModulo` | read `%Name{}` struct literals as modulo |
| `Syntax.FixPythonModulo` | `a * b % 2` regrouped — **silent wrong answer** |
| `Syntax.FixPythonFloorDiv`, `Syntax.FixScientificNotation` | rewrote inside string literals — ⚠️ **still open**, see below |
| `Semantic.UndefinedFunction` | rewrote a project's own nested-alias call |

`docs/16` scoped this as three bugs. Probing the three surfaced the other six.

The two marked **silent wrong answer** are the dangerous ones: the output
parses, compiles, and runs, and simply computes something else.
`unless n >= 0 do return({:error, :neg}) end` followed by `{:ok, n}` had the
`return` stripped in place, so `check(-5)` answered `{:ok, -5}`. The validation
stopped happening and nothing anywhere reported it.

## One root cause under four of them — two converted, two still open

Four line-based syntax rules matched their patterns against raw source bytes
with no notion of where code stops and a string begins:

```
FixPythonModulo        IO.puts("100% done")          -> IO.puts("rem(100, done)")
FixDivRem              IO.puts("use a div b")        -> IO.puts("use Kernel.div(a, b")
FixPythonFloorDiv      IO.puts("path//to//file")     -> IO.puts("div(path, to)//file")
FixScientificNotation  IO.puts("version 1e5 build")  -> IO.puts("version 1.0e5 build")
```

New `lib/source_mask.ex` produces a same-length shadow with literals, sigils,
heredocs, character literals and comments blanked; rules match the shadow and
splice into the real line at the matched offsets.

> **Correction (2026-07-28).** An earlier draft of this section said all four
> rules were converted. Only `FixPythonModulo` and `FixDivRem` were.
> `FixPythonFloorDiv` and `FixScientificNotation` never adopted `SourceMask` —
> `grep -l SourceMask lib/` does not list them — and both still corrupt string
> literals today, confirmed by running them:
>
>     IO.puts("version 1e5 build")  ->  IO.puts("version 1.0e5 build")
>     IO.puts("ratio 7 // 2 here")  ->  IO.puts("ratio div(7, 2) here")
>
> The mechanism and the two converted rules are as described; the scope was
> overstated. Tracked as T3.7 in `docs/22-remaining-work.md`, with the same
> repair pattern to apply. It is a hand-rolled scanner
rather than `:elixir_tokenizer` on purpose — these rules only ever run on source
that does not parse, which is precisely when a tokenizer gives up, and this one
degrades to a *missed* fix instead of a *corrupted* string.

Two adversarial reviews failed to break it: 8,911 differential inputs and 1,571
real files with zero new rewrites, 300,000 random byte strings with zero
crashes, 8,000 structured fuzz cases across 34 literal shapes, and an
independent oracle (every `%` the scanner calls code in a parseable file must be
a map/struct opener — 4,478 classified, 1 flagged, and that one was genuine
code in `deps/jason`).

## Two widenings deliberately not made

Both were designed, built, then rejected on review for converting a **loud**
failure into a **silent** one. Python's `&` and `%` bind more loosely than
Elixir's, so a repair that wraps only the immediate operands regroups the
expression:

```
h * 31 + c & 0xFFFFFFFF  ->  h * 31 + Bitwise.band(c, 0xFFFFFFFF)
                             compiles; returns 4294967306356, not 10356
```

Before the patch that input failed loudly. Both rules now decline those shapes
and leave the compile error, which at least names the file and line.

## The 143 rejected rules

Reconciled to 116 delete / 17 rebuild-later / 9 salvage / 1 already-live. The
112 dead modules and 227 tests are deleted in the sister repo
(`credence_evolution`, commit `b83d623`, pushed) — recoverable from
`origin/evolution`, and every verdict records the failure mode the rule encoded
before it went.

**135/143 encode a real failure mode, and 56 are caught by nothing** — not the
compiler, not Credo, not Dialyzer. Those 56 are the actual product of the
evolution run and they feed Phase 6.

## Two process findings worth keeping

**Green tests are not evidence.** Two tests asserted the `NoBareReturnInUnless`
discarded-branch output as *correct*, and passed for as long as the defect
shipped, because the expectations were written from the implementation rather
than from what the program means. `Credence.RuleCase.call_fixed/4` now exists so
a test can assert behaviour instead of text.

**Never put load-bearing prose in a Markdown table cell.** `docs/18`'s first
revision truncated all 143 action cells at ~200 characters and dropped the
per-rule failure-mode field entirely — ~162k characters, silently, while still
rendering as a valid table. Recovered from the generating session's scratchpad
before it was cleaned; `docs/18-per-rule-verdicts.json` is now committed as the
source of truth and the prose is generated from it.

## Verification

- `mix test` (including the 20,076-file corpus scan): **9,615 tests, 0 failures**
- non-corpus suite: 8,058 → **8,114**, all green
- sister repo after the deletion: **6,842 tests, 0 failures**
