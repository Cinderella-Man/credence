# Changelog

All notable changes to Credence are documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.8.1] - Unreleased

### Fixed

- **Auto-fixes no longer rewrite the inside of string literals.** Four line-based
  syntax rules matched their patterns against raw source bytes, with no notion of
  where code stops and a string begins, so prose that merely *mentioned* an
  operator was rewritten: `IO.puts("100% done")` became
  `IO.puts("rem(100, done)")`, `IO.puts("path//to//file")` became
  `IO.puts("div(path, to)//file")`, and so on for `div`/`rem` and scientific
  notation. Those outputs parse *and* compile, so nothing downstream caught them
  — the program simply printed something its author never wrote. All four now
  match against a `Credence.SourceMask` shadow in which literals, charlists,
  sigils, heredocs, character literals and comments are blanked out while every
  code byte keeps its position. Interpolation is still treated as code, because
  it is.
- **`%` and `&` repairs no longer regroup the expression.** Python's `%` shares
  precedence with `*` and `/`, and its `&` binds looser than every arithmetic
  operator — so `a * b % 2` means `(a * b) % 2` and `h * 31 + c & 0xFFFFFFFF`
  means `(h * 31 + c) & 0xFFFFFFFF`. Rewriting only the immediate operands
  produced code that compiled and returned a different number. Both rules now
  decline those shapes and leave the compile error in place, which at least names
  the file and line.
- **`&` bitwise repairs accept every integer literal form.** The right operand
  was captured as `\d+`, which stops at the `0` of `0xFF` — so
  `flags & 0xFF` became `Bitwise.band(flags, 0)xFF`, which does not parse. Hex,
  binary, octal and underscore-separated decimals all work now; bitmask code is
  overwhelmingly written with the forms that were broken.
- **`div`/`rem` repairs no longer swallow a function head.** In
  `def f(n), do: n * (n + 1) div 2` the left operand ran back over the whole
  `def`. The result was worse than a parse failure: a later rule in the same pass
  reshaped it into something that *did* parse, so the phase reported success and
  emitted a different program.
- **Early `return` is restructured, not deleted.** `unless n >= 0 do return(...)
  end` followed by more code had the `return` stripped in place, turning a guard
  into a discarded expression and letting execution fall through to the branch it
  was written to skip — `check(-5)` answered `{:ok, -5}` where the author wrote
  `{:error, :neg}`. It now becomes a real `if/else`.
- **`elif` is recognised.** The `elsif`→`cond` rule documented Python support
  from the beginning but both of its patterns matched `elsif` only, so the Python
  spelling was reported by nothing and repaired by nothing.
- **Hallucinated-function repairs respect module boundaries.** A diagnostic names
  only the last segment of an alias, so a project's own
  `MyApp.Input.List.reverse/1` was rewritten as if it were stdlib
  `List.reverse/1` — inventing `MyApp.Input.Enum`. Repairs now apply only when
  the call actually starts at a module boundary. Erlang module atoms also keep
  their leading colon, which fixes `:math.round/1` and friends.

### Added

- **A per-rule budget on accepted corpus findings, and `mix credence.corpus
  --budget` to read it.** The over-firing test already pinned the corpus findings
  exactly, so no rule could start firing without a red test — but nothing gated
  the *accept*. Its own failure message pointed at `--update-snapshot`, the re-pin
  was one command, and what landed in review was N raw `<path>:<line>  <rule>`
  lines with no per-rule aggregate anywhere. That is how the whitelist reached
  6,366 accepted findings across 87 rules — 74% of them in fifteen rules and 20%
  in one — without anyone deciding to. `test/corpus/accepted_findings_budget.txt`
  now publishes the per-rule counts, so an accept shows up as
  `+400  prefer_map_new` instead of 400 opaque path lines, and its own order is
  the paydown ranking. A rule not on the frozen grandfather ledger may not exceed
  100 accepted findings; a grandfathered rule may not exceed its adoption-day
  ceiling and must leave the ledger once it falls to the cap. Both the file and
  its gate are derived from the committed snapshot, so neither needs the corpus
  fetched and both run under `mix test --exclude corpus`.

- **`Credence.SourceMask`.** Produces a same-length shadow of a source file with
  everything that is not code blanked out, so a line-based rule can tell an
  operator from prose. Deliberately a hand-rolled scanner rather than
  `:elixir_tokenizer`: these rules only ever run on source that does not parse,
  which is exactly when a tokenizer gives up, and this one degrades to a missed
  fix instead of a corrupted string.

- **Auto-fixes no longer silently break Ash / Ecto / Nx macro code.** Some macros
  re-read ordinary Elixir AST with *different meaning*: inside `Ash.Expr.expr/1`,
  `!x` is not `not x` (it builds a query node the data layer can't translate);
  inside an `Ecto.Query`, `!`/`&&`/`x == nil` are errors; inside an `Nx` `defn`,
  arithmetic and `if` are element-wise tensor ops. A Pattern rewrite that is
  correct in plain Elixir could therefore be silently wrong inside one of these
  blocks — and it still compiled, so `mix compile` passed and the breakage only
  surfaced at runtime. Credence now finds those blocks (by call **shape**, so it
  survives `use MyAppWeb`-style wrappers that hide the import) and stands down
  inside them for exactly the rules whose fix changes a construct the DSL
  reinterprets, in exactly the families where it diverges. Findings there are
  suppressed too, so the "every Pattern rule fixes what it finds" promise still
  holds. See the `Credence.DslGuard` moduledoc.

### Added

- **`unsafe_in_dsl/0` rule callback.** A Pattern rule declares the macro-DSL
  families its fix is not behaviour-preserving inside — any of `:ash_expr`,
  `:ecto_query`, `:nx_defn` (or `:all`). Defaults to `[]`, i.e. safe everywhere,
  so existing rules are unaffected.
- **`config :credence, dsl_macros: [...]`.** Names additional macros whose bodies
  Credence should treat as opaque reinterpreting DSLs, for libraries it doesn't
  recognise out of the box.

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
