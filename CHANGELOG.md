# Changelog

All notable changes to Credence are documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.8.1] - Unreleased

### Added
- **Ten new rules.** Each was built from a recorded failure mode rather than from
  taste, and each ships with its own check/fix tests and — for Pattern — a behaviour
  equivalence test.

  *Syntax* (these run on source that does not parse, so nothing downstream sees the
  file at all until they repair it):
  `no_atom_as_function_name` (`:helper(x)` → `helper(x)`; an atom in call position
  stops the tokenizer, so the whole file is dark),
  `fix_misplaced_when_guard` (`def f(x), when x > 0` → `def f(x) when x > 0`, and
  `for a <- l, when p` → `for a <- l, p` — one rule, because the two shapes emit the
  byte-identical parse error and the round is a single pass),
  `fix_mixed_required_optional_map_keys` (`%{state: atom(), optional(k) => v}` →
  `%{:state => atom(), …}`; keyword entries must come last in a map).

  *Semantic* (keyed on a compiler diagnostic):
  `no_deprecated_not_in` and `no_pipe_into_unary_arithmetic` — both were already
  being reported by the compiler and nothing was listening;
  `fix_struct_test_in_guard` (`when Map.get(v, :__struct__) == Regex` →
  `%Regex{} = v`), which is the one repair for a remote call in a guard that is
  sound: it moves the test into the pattern rather than hoisting it into the body.

  *Pattern*: `no_enum_sort_then_map_values`, `fix_ets_new_string_name` and
  `fix_ets_options_bare_keypos` (both runtime crashes the compiler accepts), and
  `no_negative_step_in_string_slice` (`String.slice(s, n..-1)` → `n..-1//1`; the
  implicit step has been deprecated since 1.12 and is headed for a hard error).

- **`Credence.Semantic.FixCyclicStructReference` now reorders NESTED modules too.**
  A struct defined in a nested module and used earlier in the same body raises the
  same diagnostic as the top-level case, and the rule reported it and then declined
  to fix it. It hoists the definition above its first use, keeping the existing
  compile-verifying gate and the guard that refuses to reorder when a comment sits
  between the statements.

- **`analyze_after: false` on `Credence.fix/2`.** The call used to end by
  re-analysing its own output — a compile for the Semantic round plus a parse and
  every Pattern check — which roughly doubles the cost for a caller that only wants
  `:code` and `:applied_rules`. Opt-**out** rather than opt-in, because `:issues` is
  a documented field of the returned map.

- **`Credence.SourceMask` gains three public functions**, all for rules that scan
  source that does not parse: `byte_offset/3` converts the parser's 1-indexed
  `{line, column}` to a byte offset (and it must be bytes — the shadow is
  byte-aligned with the source, not grapheme-aligned, so a grapheme offset drifts on
  the first non-ASCII character); `blank?/1` recognises the fill byte, for a scan
  that would otherwise stop dead at the first blanked comment; and
  `enclosing_opener/2` finds the nearest enclosing bracket, skipping pairs that close
  before the position.

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

- **Scaffolded rules now declare their DSL safety.** `mix credence.gen.rule`
  emits a deliberate `unsafe_in_dsl/0` for Pattern rules, because at runtime a
  considered `[]` and the inherited default `[]` are the same value — only the
  source records that anyone decided. A companion source-level gate flags any rule
  whose *fix* builds or destructures a construct Ash.Expr / Ecto.Query / Nx.Defn
  reinterpret without either that declaration or an allowlist entry. This
  complements the existing fixture-driven check, which is exact for the inputs it
  sees and blind to everything else: a rule whose fixtures never exhibit the
  construct passed silently before.

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

- **`unsafe_in_dsl/0` rule callback.** A Pattern rule declares the macro-DSL
  families its fix is not behaviour-preserving inside — any of `:ash_expr`,
  `:ecto_query`, `:nx_defn` (or `:all`). Defaults to `[]`, i.e. safe everywhere,
  so existing rules are unaffected.
- **`config :credence, dsl_macros: [...]`.** Names additional macros whose bodies
  Credence should treat as opaque reinterpreting DSLs, for libraries it doesn't
  recognise out of the box.

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

- **A self-corruption gate: every Syntax rule's auto-fix is now run over its own
  source file.** A rule that rewrites the inside of a string literal produces
  output that parses, compiles and satisfies every assertion in its own fix
  tests, so no existing check could see it — and four such defects shipped. A
  rule's own file is the adversarial input nobody has to write: its moduledoc is
  required to contain `## Bad` and `## Good` examples, which are exactly the byte
  sequences the rule rewrites, sitting in a heredoc next to prose that names the
  operator in English. A rule that rewrites its own documentation cannot tell
  code from prose. 11 of 45 Syntax rules do; they are frozen in a ledger that
  only shrinks, so a *new* rule cannot join them and an existing one cannot get
  worse. This is how the `FixDivRem` defect above was found — after that rule had
  been reviewed, converted, tested and released as fixed.

- **A `LICENSE` file.** `mix.exs` has declared `licenses: ["MIT"]` since the package
  metadata was written, with no grant text anywhere in the repo — so the assertion
  had nothing behind it and `mix hex.publish` refuses the package. The file carries
  the standard MIT text, `Copyright (c) 2026 Kamil Skowron` (the sole author; first
  commit 2026-04-24). Hex's default `files` list already includes `LICENSE*`, so it
  ships with the package without a `files:` key.

### Removed
- **The `no_else_if` Syntax rule is retired; `fix_elsif_in_if_chain` now handles
  all three spellings.** Its failure mode — a model translating Python's `elif`
  writes `else if <expr> do` at branch indent — is unchanged and still repaired.
  Nothing is lost: the surviving rule was widened to match `else if` alongside
  `elsif`/`elif`, and every one of the retired rule's scenarios is now pinned in
  `fix_elsif_in_if_chain`'s tests.

  The retired rule was doing real damage. Unlike `elsif` and `elif`, `else if` is
  *legal Elixir* — `else` plus a nested `if` that opens its own block — so a chain
  of N such headers needs N+1 terminators, and only a chain carrying **one** is
  the Python transplant. `no_else_if` never checked, so given valid, parsing
  source it emitted a `cond` plus a stray `end` that did not parse. Three more
  shapes (a missing terminator, `else # note`, an empty branch body) did the same.
  Its replacement checks the terminator count, and does so only for the `else if`
  spelling: `elsif`/`elif` output is byte-identical to before, verified by running
  an 18-case corpus through the rule with and without the change.

  With this, the self-corruption ledger — the 11 of 45 Syntax rules that rewrote
  their own source when that gate was adopted — is **empty**.

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

### Fixed
- **`prefer_map_intersect_over_mapset_intersection` produced a silently wrong answer
  when an operand was rebound.** It matched its two operands by name and accepted the
  consuming statement at any later index, passing everything in between through
  untouched — so `freq1 = Map.put(freq1, :x, 9)` between the two halves left the
  emitted `Map.intersect/3` reading the new value where the original took its key set
  from the old one. Executed: `[b: 2]` became `[b: 2, x: 7]`, and in the
  key-removing direction a raised `KeyError` became `[]`. A second defect in the same
  rule emitted `fn _key, _key, count2 -> …` whenever a captured count was itself
  named `_key`, which compiles and then raises `FunctionClauseError`. Both outputs
  compiled, so the accept/revert gate could not see either.

- **`no_keyword_get_integer_key` reported four shapes it would never fix**, because
  the fix required the list argument to be a bare identifier — a limit inherited from
  a regex predecessor, not a safety property. `Keyword.get(@acc, -1)`,
  `Keyword.get(state.items, -1)`, `Keyword.get(build_list(), 0)` and
  `Keyword.get([a: 1], -1)` are now repaired. In the same pass it stopped claiming
  `Keyword.get(:timeout, 5000)`, which is the swapped-arguments defect
  `no_keyword_get_with_atom_first_arg` owns and repairs correctly.

- **Nine rules reported a finding their own fix declined to make.** Each turned out
  to be one decision kept in two copies — a check that had drifted from the fix it
  was supposed to mirror. Two of them were hiding worse: `no_trailing_newline_in_doc`
  was emitting source that did not parse (the patch was rejected, and the rejection
  read as a no-op), and `no_guard_equality_for_pattern_match` was dropping a
  repeated-variable constraint, which compiles and changes which calls match.

- **`Credence.analyze/1` returned NO issues for a file analysed concurrently with
  another defining the same module name.** A false negative, which is the worst
  direction for a linter — it does not fail, it quietly approves. Compiling is now
  serialised per module name, so files defining different modules still compile in
  parallel.

- **`@spec` repairs no longer stop at the top level.** `NoBareNamesInSpec` fixes a
  compiler-rejected bare name in a spec by annotating it `name :: any()`, but it
  only ever looked at names sitting as *direct* arguments of the spec's call. A
  bare name inside a `|` union, a list / tuple / map type, or in the return
  position was left untouched — and so was every position in a spec carrying a
  `when` guard, including top-level ones. The rule still claimed the diagnostic in
  all those cases, and because the Semantic phase gives one diagnostic to one rule,
  claiming-without-fixing meant nothing else could repair it and the compile error
  survived every pass. It now annotates the name wherever it occurs in the target
  spec, and declines a name the `when` clause binds as a type variable (annotating
  one of those does not compile).

- **`mix credence.fix_tests` no longer corrupts fixtures containing escapes.** It
  recorded a rule's output by splicing it into a `"""` heredoc verbatim, so output
  holding a backslash came back different when the test ran — `~c"say \"hi\""`
  became `~c"say "hi""` — and output holding `#{` parsed as an interpolation
  instead of a string. It also read existing fixtures as raw source bytes rather
  than their values, so the rule under test was handed a different input than the
  running test passes it. Both directions are fixed and are exact inverses, so the
  task stays idempotent. The same emitter gap in the test-fixture healer is fixed
  too; there it never corrupted anything, because its value-preserving guard
  rejected the write — it just silently left those fixtures un-canonicalized.

- **Auto-fixes no longer rewrite the inside of string literals.** Four line-based
  syntax rules matched their patterns against raw source bytes, with no notion of
  where code stops and a string begins, so prose that merely *mentioned* an
  operator was rewritten: `IO.puts("100% done")` became
  `IO.puts("rem(100, done)")`, `IO.puts("path//to//file")` became
  `IO.puts("div(path, to)//file")`, and so on for `div`/`rem` and scientific
  notation. Those outputs parse *and* compile, so nothing downstream caught them
  — the program simply printed something its author never wrote.
  All four — `FixPythonModulo`, `FixDivRem`, `FixPythonFloorDiv` and
  `FixScientificNotation` — now match against a `Credence.SourceMask` shadow in
  which literals, charlists, sigils, heredocs, character literals and comments
  are blanked out while every code byte keeps its position. Interpolation is
  still treated as code, because it is.
- **Auto-fixes no longer rewrite trailing comments.** The two rules converted
  last, `FixPythonFloorDiv` and `FixScientificNotation`, guarded themselves with
  a whole-line `#` test, which skips a line that *begins* with a comment and does
  nothing for one that ends with it: `x = a // b  # was a // b` came back as
  `x = div(a, b)  # was div(a, b)`, and `x = 1e5  # bump to 1e9 later` as
  `x = 1.0e5  # bump to 1.0e9 later`. The comment is now blanked wherever it
  starts. Sigils, charlists and heredoc bodies were rewritten by the same two
  rules and are covered by the same change.
- **`FixDivRem` no longer rewrites heredoc bodies.** It was masking, and had been
  changelogged as fixed — but only in `analyze/1`. `fix/1` split the source into
  lines and masked each line *alone*, which a line cannot be: heredoc and
  multi-line-string state crosses lines, so a heredoc body read as pure code. The
  rule rewrote documentation that `analyze/1` had correctly said nothing about,
  which is worse than either half alone — the finding a reviewer reads and the
  edit that ships were computed from different pictures of the file. The rewrite
  now runs only where masking a line in isolation agrees with the whole-file
  mask; elsewhere the line is left alone, costing a missed fix rather than a
  corrupted string.
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
