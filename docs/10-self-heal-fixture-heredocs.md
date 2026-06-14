# 10 — Fixture-form convention + deterministic self-heal

## Context

Review of `logs/escalated/` showed **every** escalated case was a *genuine, useful* Credence rule
rejected **solely** because its test fixtures didn't satisfy `test/fixture_string_escaping_test.exs`, which
today demands **every** code fixture be a `"""` heredoc — even a one-line one. That meta-test runs in the
default `mix test`; Tunex's Gate runs the suite, so a non-heredoc fixture → meta-test RED → suite RED →
genuine rule discarded → `escalated/`. The agentic rule-writer also runs `mix test` mid-loop and burns turns
fighting it.

Two fixes, together:
1. **Relax the convention** so the natural single-line form an AI writes is *allowed*, not rejected.
2. **Deterministically self-heal** the remaining wrong forms on every `mix test`, before the suite compiles —
   so the agent loop, the implementer's focused test, and the Gate's full suite all normalize fixtures
   themselves. Only genuinely un-representable fixtures (the rare residue) still escalate.

Covers Credence only; the Tunex prompt nudge (§B) is a separate repo (see *Out of scope*).

## The convention (3 canonical forms, escape-free, one way each)

Driven by a fixture's **value** (not how it's typed):

| Value | Canonical form | Why |
|---|---|---|
| no newline, no `"` | `"foo"` (plain) | compact, clean |
| no newline, has `"` | `~S'foo "bar"'` | escape-free, compact, **preserves the no-`\n` value** |
| has a newline | `"""…"""` heredoc | escape-free multi-line |

- **Sigil delimiter is fixed at `'`** (`~S'…'`). `'` (charlist quote) is the rarest character in Elixir code,
  so it's effectively conflict-free — crucially, *syntax*-rule fixtures (malformed code) routinely have
  unbalanced `()`/`[]`/`<>`/`|` (which break those delimiters) but essentially never a `'`. There is **one**
  sigil form; a heredoc is the fallback only for the never-observed "value has both `"` and `'`" case.
- A heredoc's value *always* ends in `\n`, so the 2088 existing single-content-line heredocs (value `"foo\n"`)
  **stay heredocs** — their value contains a newline. No churn, no value changes. Single-line *plain* is for
  genuinely-no-`\n` values (e.g. `analyze(...)` inputs — exactly the escalated cases).

## Meta-test (`fixture_ok?`) — relaxed, tested both ways

A plain `"..."` fixture is **flagged** iff its value has a newline (→ heredoc) **or** a `"` (→ `~S'…'`);
otherwise allowed. `~S'…'` sigils and heredocs are allowed. Concretely (raw node form, mirroring the existing
`multiline_interp?` substring style): flag a `{:__block__, m, [s]}` (non-heredoc) when
`s =~ ~r/\\?n/`-style newline **or** `s` contains `\"`. **Both directions get test cases**: a clean
single-line `"foo"` passes; `"abc\ndef"` and `"a \"b\""` fail.

## Decisions (resolved via design review + empirical PoC)

- **Trigger** — heal always, in `test/test_helper.exs` (before `*_test.exs` are required). Idempotent;
  no-op once forms are canonical.
- **Healer scope** — exactly 3 deterministic conversions (no prettify/verbatim ambiguity — that's gone):
  plain-with-`\n` → heredoc (real newlines); plain-with-`"`(no `'`) → `~S'…'`; plain-with-`"`-and-`'` → heredoc.
  Clean single-line plain and existing heredocs/sigils are left alone.
- **Write safety** — verify before write: the healed file parses, has strictly fewer flagged fixtures
  (monotonic), and each converted fixture's *compiled value* is unchanged (±trailing `\n` for the heredoc
  case). Per-file `rescue`. A healer bug becomes a no-op, never a suite-bricking compile error.
- **Placement** — all new code in `/test`: `Credence.FixtureHealer` in `test/support/`; `@allow` moves into
  `Credence.MetaTestSupport` (shared with the meta-test). **Zero lib code.** (The lib mix tasks
  `credence.fix_tests`/`gen.rule`/`normalize_tests` + `RuleScaffold`/`RuleName` are irreducible — mix-task
  discovery + `:dev`.)

### Verified empirically (`MIX_ENV=test` PoC)

- `~S'…'` preserves values exactly (quotes, backslashes, literal `#{}`), is **format-stable**
  (`Code.format_string!` keeps the `'` delimiter), and clashes with **0** of the 20 existing single-line
  quote-containing fixtures (none also contain a `'`).
- Heredoc rendering: copying the value as real newlines, `patch_string` re-indents (incl. blank lines), dedent
  cancels → values preserved.
- `elixirc_paths(:test) = ["lib","test/support"]` (`mix.exs:23`) ⇒ `test/support` compiles before
  `test_helper.exs` runs ⇒ `MetaTestSupport.fixtures/1`/`fixture_ok?/1` callable from the hook.

## Implementation

1. **`test/support/meta_test_support.ex`** — relax `fixture_ok?` per the rule above (allow clean single-line
   plain + `~S'…'`; flag `\n`/`\"` plain). Add `def allow, do: %{…}` (the 2 current `@allow` entries) so both
   the meta-test and the healer share it.
2. **`test/support/fixture_healer.ex`** (`Credence.FixtureHealer`):
   - `heal_source(src) :: {healed, residue_count}` — `Sourceror.parse_string!` → `MetaTestSupport.fixtures`
     → for each flagged node, pick the canonical form (heredoc / `~S'…'`) and emit a
     `%{range: Sourceror.get_range(node), change: …}` patch → `Sourceror.patch_string`.
     - `~S'…'` builder: `"~S'" <> value <> "'"`; if the value contains `'` (or `\n`), use a heredoc instead.
     - heredoc builder: the value as real newlines, wrapped `"""\n…\n"""` (column-0; `patch_string` re-indents).
   - `heal_file(path)` — read; `heal_source`; write only if the verify-before-write guards pass; skip `@allow`;
     `rescue -> :ok`. (Mirror `Credence.FixTests.fix_file/1`, `lib/mix/tasks/credence.fix_tests.ex`.)
   - `heal_dirs()` — `Path.wildcard("test/{pattern,semantic,syntax}/**/*_test.exs")`, `heal_file` each.
3. **`test/test_helper.exs`** — `Credence.FixtureHealer.heal_dirs()` before `ExUnit.start(...)`.
4. **`test/fixture_string_escaping_test.exs`** — source `@allow` from `MetaTestSupport`; otherwise unchanged
   (still the residue arbiter).
5. **Existing-fixture migration** (one-time, by the healer itself on first `mix test`): non-`'` single-line
   string sigils heal to `~S'…'` where value-safe; anything that can't (multi-line sigils, `'`+`"` values) →
   `@allow` or heredoc. Audit the diff before committing.

## Reuse

- `MetaTestSupport.fixtures/1` (`test/support/meta_test_support.ex:295`) + `fixture_ok?/1` (`:347`).
- `Credence.FixTests.fix_file/1` (`lib/mix/tasks/credence.fix_tests.ex`) — read/patch/write/`rescue` shape.
- `Sourceror.{parse_string!,get_range,patch_string}`; `Code.{string_to_quoted,eval_string,format_string!}`.

## Tests — `test/fixture_healer_test.exs` (at test *root*, outside the gated dirs)

- Meta-test convention (both ways): clean single-line `"foo"` ok; `"a\nb"` flagged; `"a \"b\""` flagged;
  `~S'a "b"'` ok; heredoc ok.
- `heal_source/1`: `"a\nb"` → heredoc; `"a \"b\""` → `~S'a "b"'`; `"foo"` unchanged; value containing `'`+`"`
  → heredoc; idempotency; value-eval equality across backslash / `#{` / quotes.
- `heal_file/1`: temp file with a `\n`/escaped fixture → healed + `fixture_ok?` passes; `@allow` untouched;
  a non-monotonic/unparseable heal is skipped.

## Verification

- `mix test` green (meta-tests + new healer tests). Confirm heal is a **no-op on the canonical tree**.
- Manual: plant `code = "a \"b\""` in a real `test/pattern/<x>_fix_test.exs` → `mix test` → it's now
  `~S'a "b"'` and the meta-test passes; plant `"x\ny"` → becomes a heredoc; a clean `"foo"` is untouched.
- Clone-smoke: a checkout whose new rule uses plain/escaped fixtures → one `mix test` self-heals + passes.

## Risks / notes

- **`mix test` mutates tracked test files** (the heal + the one-time sigil migration) — accepted; idempotent;
  the Gate's `git add -A` commits them. Audit the first migration diff.
- **Verify-before-write is load-bearing** (heal runs every `mix test`) — keep the parse + value-eval +
  monotonic guards.
- **Residue still escalates** — a single-line value containing both `"` and `'`, or a value that can't be a
  heredoc, is left for the meta-test. Vanishingly rare.

## Out of scope (separate repo)

§B — prompt-only nudge in Tunex (`lib/tunex/implement/seed.ex`): teach the 3-form convention (plain / `~S'…'`
/ heredoc) in `conventions_block`, and add a phase-conditional `syntax_fix_block` pointing syntax rules at the
parser's error structure (`Code.string_to_quoted/2` `{:error, {meta, msg, token}}`) instead of line/text
heuristics. Independent of this change.
