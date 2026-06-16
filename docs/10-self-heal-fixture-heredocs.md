# 10 — Fixture convention (single-line ⇒ plain/sigil) + `confirm_fix` + self-heal

## Context

The escalated-rules review found that genuine rules were rejected only because their fixtures didn't match
`test/fixture_string_escaping_test.exs`. The first iteration of this plan *relaxed* the convention to allow a
single-line plain `"…"` alongside heredocs. That left ~2088 existing single-**content**-line heredocs
(`"""\nfoo\n"""`, value `"foo\n"`) untouched, which is inconsistent and verbose.

**New directive (decisive): single-line triple-quoted strings are NOT allowed — convert all of them.** Every
fixture is exactly one canonical form, enforced and produced by the healer. The only thing that made this
unsafe was the trailing `\n` a heredoc adds: in a fix test, `fix(R, input) == expected` compared the fix's
output byte-for-byte, so dropping the `\n` broke ~46 rules whose fix isn't newline-transparent. The fix is a
**global comparison helper** — `confirm_fix(fix(R, input), expected)` — that compares with trailing newlines
trimmed. With it, trailing newlines never matter, so every single-content-line heredoc can become a plain
string with **no per-rule guard**.

Credence only; the Tunex prompt nudge stays out of scope (separate repo).

## The convention (exactly one canonical form per value)

| Fixture value | Canonical form |
|---|---|
| no newline, no `"` | `"foo"` (plain) |
| no newline, has `"` | `~S'foo "bar"'` (single-quote-delimited sigil) |
| has a newline (multi-line) | `"""…"""` heredoc |

- **No single-content-line heredocs.** A heredoc is allowed only when its value has an *internal* newline
  (≥2 content lines). `"""\nfoo\n"""` (value `"foo\n"`) is flagged → must become `"foo"` / `~S'…'`.
- Sigil delimiter is fixed at `'` (rarest in Elixir code; survives malformed-code fixtures). Verified
  value-safe + `mix format`-stable in the prior iteration.

## `confirm_fix/2` — the global, newline-insensitive fix comparison

New helper in `test/support/rule_case.ex` (available unqualified via `use Credence.RuleCase`, like `fix/2`):

```elixir
def confirm_fix(actual, expected) do
  assert String.trim_trailing(actual, "\n") == String.trim_trailing(expected, "\n")
end
```

Every fix test uses it instead of `assert fix(...) == expected`:

```elixir
confirm_fix(fix(NoFoo, input), expected)      # was: assert fix(NoFoo, input) == expected
```

This trims the trailing `\n` on **both** sides, so input/expected may be compact plain strings (no `\n`) or
heredocs (which add one) interchangeably — and it also subsumes the two current `@allow` reasons
("fix drops/forces a trailing newline"), shrinking `@allow`.

## What the healer does (deterministic, every `mix test`, idempotent)

`Credence.FixtureHealer` (test/support) gains two passes on top of the existing plain→heredoc/sigil pass; all
applied in one `Sourceror.patch_string` write per file, guarded by parse + value-eval before writing:

1. **Convert single-content-line heredocs → plain/`~S'…'`.** Value with no newline → `"foo"` (or `~S'foo "x"'`
   if it has a `"`). (Existing pass already handles plain-with-`\n` → heredoc and plain-with-`"` → `~S'…'`.)
2. **Rewrite the fix assertion** `assert fix(…) == expected` → `confirm_fix(fix(…), expected)` (both operand
   orders; multi-line operands preserved by patching the `assert`/`==` node range; also the var-bound shape
   `result = fix(…)` then `assert result == expected`, by resolving the same-block binding). Idempotent (skip
   if already `confirm_fix`). Leaves the 32 non-`==` fix assertions (`valid_syntax?(fix(…))`,
   `analyze(fix(…)) == []`, `refute …`) untouched — they don't compare the fix's string output, so newlines
   don't matter there.

**Safety principle (order matters):** within a fix test, a single-content-line heredoc is converted to a
plain string **only after** its enclosing comparison is newline-insensitive — i.e. it is a `confirm_fix`
operand (pass 2 already applied) or a non-`==` assertion. A heredoc whose comparison the healer can't
normalize to `confirm_fix` is left as a heredoc (conservative — never breaks a `==`). Combined with
verify-before-write and the suite that runs immediately after, no conversion can silently break a test.

On the current tree this is a one-time bulk change (~2042 assertion rewrites + ~2088 heredoc conversions
across 214 files); afterward it's a no-op. The Gate's `git add -A` commits the canonical files.

## Files to change

- **`test/support/rule_case.ex`** — add `confirm_fix/2`. Revert the experimental `fix/2` trailing-newline
  strip from this session (superseded by `confirm_fix`; `fix/2` returns raw bytes again).
- **`test/support/meta_test_support.ex`** —
  - `fixture_ok?` for `{:__block__, m, [s]}`: a `"""` heredoc is OK **only** if multi-line
    (`String.contains?(String.trim_trailing(s, "\n"), "\n")`) or it carries `"""`; otherwise it's a
    single-content-line heredoc → flagged. Keep the plain-`"…"` clause (no newline, no `"`) and the `~S'…'`
    clause from the prior iteration.
  - `transform?/1` and `fix_source_transform?/1`: also accept `{:confirm_fix, _, [fix_call, expected]}`
    (currently only `{:==, _, [fix_call, expected]}`). `partial_match?`, `fix_call?`, `fix_call1?`,
    `calls_any?([:fix])` are unchanged (the inner `fix(…)` call still matches).
- **`test/support/fixture_healer.ex`** — add passes 1 & 2 above; keep verify-before-write (parse + value-eval
  ±trailing `\n`, monotonic).
- **`test/test_helper.exs`** — unchanged (already calls `heal_dirs/0` before the suite compiles).
- **`test/fixture_string_escaping_test.exs`** — unchanged (still the residue arbiter; sources `@allow` from
  `MetaTestSupport`).
- **`lib/rule_scaffold.ex`** — the 3 fix-test templates (pattern ~line 120, syntax ~233, semantic ~347):
  emit `confirm_fix(fix(…), expected)` and plain `"…"` single-line fixtures instead of heredocs.
- **`test/generator_meta_test.exs`** — the pin: accept `:confirm_fix` (e.g. `calls_any?([:fix, :confirm_fix])`)
  and the updated `transform?/1`. Fixture validation already accepts plain `"…"`.
- **`lib/mix/tasks/credence.fix_tests.ex`** — `fix_assertion/1` (~line 205): also match
  `{:confirm_fix, _, [{:fix, _, [alias, arg]}, rhs]}` → `{input_ref, expected_ref}`. (`credence.normalize_tests`
  is assertion-agnostic — no change.)

## Verification

- `mix test` green after the healer's bulk run. Re-run → **no-op** (hash-identical tree).
- The four meta-tests that gate fix shape stay green: `fix_meta_test` (real transform via updated
  `transform?/1`, whole-string via `partial_match?`), `generator_meta_test` pin, `fixture_string_escaping_test`
  (now flags single-content-line heredocs, all healed), `syntax_meta`/`semantic_meta`.
- Spot-check: `avoid_graphemes_enum_count_fix_test.exs` becomes
  `confirm_fix(fix(AvoidGraphemesEnumCount, "Enum.count(String.graphemes(str))"), "String.length(str)")`.
- Plant a fresh single-content-line heredoc fixture + an `assert fix(R, …) == …` in a real test → one
  `mix test` rewrites both to canonical form, suite stays green.
- `mix format` + `mix credo --strict` clean on changed support/lib files.

## Risks / notes

- **Large one-time diff** (~214 files) on the first heal — expected; idempotent thereafter; the Gate commits it.
- **`confirm_fix` failure messages** show the trimmed values; keep the message readable (it's the new default
  for every fix test).
- **Verify-before-write stays load-bearing** — heal runs on every `mix test`; the parse + value-eval guards
  keep a healer/rewrite bug from bricking the suite (a file that wouldn't parse or whose values changed beyond
  a trailing `\n` is left untouched).
- **Residue still escalates**: a single-line value containing both `"` and `'`, or one carrying `"""`, can't be
  plain/`~S'…'` → left for the meta-test. Vanishingly rare.

## Out of scope (separate repo)

Tunex `seed.ex`: teach the 3-form convention + `confirm_fix(fix(…), expected)` as the fix-test shape, and the
parser-error-structure guidance for syntax rules. Independent of this change.
