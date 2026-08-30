# Accept the 3rd evolution cycle

**PR [#22](https://github.com/Cinderella-Man/credence/pull/22)** —
`evolution_accepted` → `main`, **477 commits**.

Closes the acceptance cycle planned in `docs/16`: 116 rule acceptances from the
stage-1 drain, the disposition of all 143 rejected rules, the repairs that
disposition uncovered — and, since the body below was first written, the
reality-gate program the disposition argued for (`docs/22`) plus the release
map now in `STATUS.md`.

> **Merge with a method that PRESERVES COMMIT SHAs — fast-forward or a merge
> commit, never squash or rebase.** Commit ids are cited throughout `docs/16`,
> `docs/22` Part III, `maintainer_tools/escalation_ledger.md`, the harness's
> `IMPROVEMENTS.md` and the in-flight record. A squash orphans every one of them
> and makes the sister-clone reset — delete `evolution`, recreate it from the new
> `main` — produce a tree unrelated to the documented history. Re-check at merge
> time rather than trusting this line:
> `git fetch && git merge-base --is-ancestor origin/main evolution_accepted`.

## What landed after the original Phase-4 body

The sections below are the Phase-4 record and remain accurate. Since then the
branch also carries the gate program that the 143-reject analysis called for:
the **pipeline-witness gate** (every rule must fire through the real pipeline —
it found 2 live rules that could not), **dispatch-contention**, the
**self-corruption oracle** and its Syntax paydown, the **idempotency ratchet**,
the **C18 mutant sweep**, a **compile bound** that ended seven OOM kills, and —
most recently — the **byte-scope oracle for the Semantic phase**, which found
`UndefinedFunction` rewriting inside string literals and comments. Full detail
per item in `docs/22`; what is still open is in `STATUS.md`.

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
splice into the real line at the matched offsets. It is a hand-rolled scanner
rather than `:elixir_tokenizer` on purpose — these rules only ever run on source
that does not parse, which is precisely when a tokenizer gives up, and this one
degrades to a *missed* fix instead of a *corrupted* string.

> **Correction (2026-07-28), resolved the same day.** An earlier draft of this
> section said all four rules were converted. At the time only `FixPythonModulo`
> and `FixDivRem` were, and `FixDivRem` only halfway (see below);
> `FixPythonFloorDiv` and `FixScientificNotation` had never adopted `SourceMask`,
> and both still corrupted string literals, confirmed by running them.
>
> `e81985e` (T3.7) converted the remaining two, so **all four is now true** —
> and it found four more shapes of the same defect while doing it, all live:
> sigils, charlists, heredoc bodies and *trailing* comments. The whole-line `#`
> guard those two rules carried skipped a line that began with a comment and
> rewrote one that ended with it, so `x = a // b  # was a // b` came back as
> `x = div(a, b)  # was div(a, b)`. 22 positive controls, all seen red against
> the pre-fix rules.
>
> `8169601` then repaired `FixDivRem`, which this section had counted as
> converted since Phase 4. It was — in `analyze/1`. Its `fix/1` masked each line
> *alone*, which a line cannot be, so it kept rewriting heredoc bodies that
> `analyze/1` correctly ignored. Found by an oracle, not by reading: `b41af7b`
> runs every Syntax rule's `fix/1` over its own source file, and 11 of 45 rewrite
> their own documentation. That paydown is docs/22 T3.10.

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

- `mix test` — **10,496 tests + 6 properties, 0 failures**, with **nothing
  excluded**: the 20,076-file corpus scan and the `:idempotency` sweep both run in
  the default suite now (~19 min; `--exclude idempotency` is the fast local loop)
- `mix format --check-formatted`: clean tree-wide
- `mix compile --force --warnings-as-errors`: clean
- sister repo after the deletion: **6,842 tests, 0 failures**
- **CI exists but has never executed.** `.github/workflows/ci.yml` was added with
  three jobs on a pinned Elixir 1.20.2 / OTP 29. Every command in it has run
  locally and green, and everything checkable without a runner has been checked —
  the pinned pair matches, all five mix tasks exist, and there are no absolute
  local paths or env dependencies anywhere in `lib/` or `test/`. But no job has run
  on a runner, because that needs this push. Treat the first run as a hypothesis;
  the corpus job fetches ~1 GB on a cold cache.
