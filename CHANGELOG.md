# Changelog

All notable changes to Credence are documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.7.0] - Unreleased

### Added

- **Rule scaffolding generator.** `mix credence.gen.rule <Name> [--type
  pattern|syntax|semantic]` writes a correctly-shaped rule plus its test files
  (heredoc fixtures, conventional names, passing every structural meta gate). The
  generated tests start intentionally red so `mix test` shows exactly what to
  fill in. Syntax and Semantic rules now carry their own completeness + substance
  gates — both directions of `analyze`/`match?`, a real `fix` transform, a
  `valid_syntax?(fix(x))` check that the repaired source parses, a Syntax fixpoint,
  and Semantic attribution — and a pin (`test/generator_meta_test.exs`) keeps the
  generator's output in lock-step with those gates.

- **Safety switches (`assumptions`).** Rules may now declare an assumption —
  a checkable promise about the *data the program handles at runtime* — that
  their fix relies on to be behaviour-preserving. A rule runs only when all of
  its assumptions are on. See the `Credence.Assumptions` moduledoc.
- **`single_codepoint_graphemes`** — the first switch, **on by default**. It
  promises every character in your running data is a single codepoint (no
  decomposed accents, ZWJ emoji, or flag sequences). With it on, Credence can
  apply fixes that are identical to the original for all such text.
- **`:strict` mode** — `assumptions: :strict` turns every promise off, so only
  rules that are correct for *every possible input* run. This is the old
  iron-clad, behaviour-identical guarantee, reachable by one word.
- **`:default`** — resets every switch to its built-in default (the mirror of
  `:strict`).
- `Credence.Pattern.rule_status/1` and `enabled_rules/1` for inspecting which
  rules are on and which promises they are missing.

### Changed

- **Behaviour change on upgrade (default-on switch).** With
  `single_codepoint_graphemes` on by default, two rules now apply fixes they
  previously skipped, behind the switch:
  - `avoid_graphemes_enum_count_with_predicate` now rewrites
    `String.graphemes(s) |> Enum.count(&(&1 == c))` to `String.count(s, c)`
    (for a single-codepoint literal `c`).
  - `no_manual_string_reverse` was split: the `String.codepoints` shapes moved
    to the new `no_codepoint_string_reverse` rule, which rewrites to
    `String.reverse/1` behind the switch. The `String.graphemes` shapes stay in
    `no_manual_string_reverse` and remain always-safe.

  Pass `assumptions: :strict` to restore the previous behaviour for arbitrary
  Unicode data.
