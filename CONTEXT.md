# Credence — Context

A tool that reads Elixir code written by an AI, finds clumsy patterns, and
either fixes them or doesn't include the rule at all. The project's stance:
**every rule either fixes its problem or it doesn't exist** — a rule that could
only warn is deleted, never shipped.

A note on words used a lot here:

- **AST** — the tree shape a parser turns your code text into. Rules work on the
  tree, not the raw text.
- **codepoint** vs **grapheme** — a grapheme is a whole character as you see it
  (`é`, `👍`). A codepoint is one of the smaller pieces a character can be built
  from. Simple letters are one piece; some characters are several. The two ways
  of counting drift apart whenever a character is more than one piece — which is
  the source of a lot of unsafe rewrites (see the bottom of this file).

## Parser: Sourceror only

Credence parses code with **Sourceror, and nothing else**. Sourceror is a
parsing library; the tree it makes keeps extra notes about spacing and position
that Elixir's built-in parser throws away. `Code.string_to_quoted/1` (Elixir's
built-in parser) does **not** appear anywhere in `lib/` or `test/` — you can
check this with grep, and it should stay that way. Every bit of parsing goes
through `Sourceror.parse_string/1` or `Sourceror.parse_string!/1`, including:

- Both Pattern callbacks (`check/2` and `fix_patches/2`).
- The Syntax round's "did it parse?" check.
- The Pattern runner's re-parse on each pass.
- Tests calling `check/2` (test files parse with `Sourceror.parse_string!/1`).
- Building little bits of code inside a rule (e.g.
  `Sourceror.parse_string!("require Logger")`).

Sourceror's tree is **not** the same shape as the built-in parser's tree. That
shape difference is the main thing to keep in your head when writing or reading
a rule — see "Sourceror tree surprises" below. A pattern match written for the
built-in tree, like `{:==, _, [_, 1]}`, will quietly fail to match Sourceror's
`{:==, _, [_, {:__block__, _, [1]}]}`. This is the number-one cause of "my rule
won't fire" bugs.

## The three rounds

`Credence.fix/2` runs three rounds in order. Each round has its own kind of rule
and finds its rules by itself through `RuleHelpers.discover_rules/1`.

1. **Syntax** (`lib/syntax/`) — text fixes for code that won't parse. No tree
   yet. Rules are `String.t() -> String.t()`.
2. **Semantic** (`lib/semantic/`) — fixes for compiler warnings. Rules match
   against `Code.with_diagnostics/1` output and patch the text.
3. **Pattern** (`lib/pattern/`) — the bulk of Credence: 76 rules that work on
   the tree.

The rounds run one after another; if syntax problems are still there, the
semantic and pattern rounds are skipped. The Pattern round is skipped entirely
if the code doesn't compile — rewriting broken code risks wasting an AI's
retry.

## The Pattern round — what a rule looks like

Every rule in `lib/pattern/` has three callbacks:

```elixir
@callback priority() :: integer()                                  # default 500
@callback check(ast :: Macro.t(), opts :: keyword()) :: [Issue.t()]
@callback fix_patches(ast :: Macro.t(), opts :: keyword()) :: [patch]
```

**Both callbacks get the Sourceror tree** (from `Sourceror.parse_string!/1`),
not the built-in parser's tree. The two differ: simple values (numbers, floats,
strings, atoms, lists, and 2-tuples) are wrapped in a `{:__block__, meta,
[value]}` node that carries position and quoting notes. Strings also carry a
`:delimiter` note in that block's meta (`"\""` for a normal string vs. `~s(""")`
for a heredoc). See "Sourceror tree surprises" for the whole list.

`opts` carries `:source` for rules that need the raw bytes (e.g. to slice a
piece of the original text into a patch's `change`).

A `patch` is `%{range: Sourceror.Range, change: String.t()}` — apply it with
`Sourceror.patch_string/2`. An empty list means no change.

### Three ways rules build their patches

Rules differ in *how* they work out their patches, not in what they hand back:

- **`RuleHelpers.patches_from_postwalk(ast, matcher)`** — one walk over the tree
  with a matcher; the helper compares the original tree to the changed one and
  hands back one patch per outermost change. Used by ~50 rules.
- **`RuleHelpers.patches_from_ast_transform(ast, source, transform_fn)`** — any
  tree-to-tree change; the helper prints the result with `Sourceror.to_string/1`,
  re-parses, and compares. Use this when the change drops or reorders siblings,
  or adds statements into a block (a single walk-matcher can't say that).
- **Building the patches by hand** — the rule walks the tree itself and builds
  `[%{range: ..., change: ...}]`. Use this when the *original bytes* of the kept
  part must stay exactly as written — usually because Sourceror's printer would
  drop them (see the surprises below).

There is no text-level helper. `patches_from_fix_source` existed during the
move-over and was deleted once the last rule switched off it.

## Words we use

- **Rule** — a module that implements one of the three kinds of rule (Syntax,
  Semantic, or Pattern).
- **Issue** — `%Credence.Issue{rule, message, meta: %{line: ...}}`. The same
  struct in every round.
- **Check** — the part that finds problems (`check/2` for Pattern; `analyze/1`
  for Syntax; `match?/1` + `to_issue/1` for Semantic).
- **Fix** — the part that makes patches (`fix_patches/2` for Pattern; `fix/1`
  for Syntax/Semantic).
- **Patch** — `%{range, change}`. Sourceror's "edit these bytes" format.
- **Applied trace** — `[{rule_module, count_or_:reverted}]`. Handed back by
  `fix_with_trace/2` for each round. `:reverted` means a rule produced code that
  wouldn't compile and the runner undid its change.
- **After-the-fix check** — after a rule's patches go on, the Pattern runner
  runs `Code.compile_string/2`. If the result won't compile, the rule's change
  is undone and a warning is logged. This catches rules that make code that
  parses but is broken, before the AI sees it.
- **Find-only rule** — a rule that could find a problem but never fix it.
  Credence doesn't ship these: by policy such a rule is deleted, not kept as a
  warning.

## Sourceror tree surprises

Sourceror's tree mostly mirrors the built-in parser's tree, but with a few
important differences. Rules that don't account for them quietly fail to match.

- **Simple values are wrapped.** Sourceror wraps simple values (atoms, numbers,
  floats, strings, 2-tuples, lists) in `{:__block__, meta, [value]}` to carry
  position notes. The built-in tree has them bare. So a pattern like
  `{:==, _, [_, 1]}` won't match Sourceror's `{:==, _, [_, {:__block__, _, [1]}]}`.
  Rules pattern-match the wrapped form directly — use `unwrap_literal/1`,
  `unwrap_list/1`, or `extract_do_body/1` in `RuleHelpers` for the common cases
  (value-or-`__block__`, list-or-wrapped-list, do-keyword). Don't reshape the
  tree inside a rule — every Pattern rule walks the Sourceror shape from start to
  finish.

- **Some atoms stay bare.** Sourceror wraps atom *values* (e.g. `:asc` in
  `Enum.sort(list, :asc)`) but leaves atoms bare in *function-name* spots
  (`:get` in `Map.get(...)`) and *module* spots (`:Enum` in
  `{:__aliases__, _, [:Enum]}`). The `unwrap_atom` helpers accept both — the
  bare branch is for these genuinely-bare spots, not a patch to match the
  built-in tree.

- **Building Sourceror-shaped output.** When a rule makes a fresh simple value
  for its replacement, wrap it too — `Sourceror.to_string/1` crashes on a bare
  number in an argument spot, and prints a bare 2-tuple as map-update syntax
  (`{_k, v}` → `_k => v`). Wrap numbers as `{:__block__, [token: "N"], [n]}`,
  strings as `{:__block__, [delimiter: ~s(")], [s]}`, tuples as
  `{:__block__, [], [{a, b}]}`. See `no_map_keys_or_values_for_iteration`'s
  `wrap_int/1`, `wrap_str/1`, `wrap_tuple/1` for the go-to builders.

- **The string `:delimiter` note.** Heredocs (`"""`) and normal strings (`"`)
  produce the *same* value in the built-in tree — both become a plain binary.
  Sourceror keeps them apart with a `:delimiter` note in the string's
  `:__block__` meta (`~s(""")` for a heredoc, `"\""` for a normal string). Rules
  that need to skip heredocs (e.g. `NoTrailingNewlineInDoc`,
  `PreferHeredocForMultiLineDoc`) read that note — no need to look at the
  `:source` text.

- **The `:parens` note only works one way.** `(a - b)` parses to
  `{:-, [parens: ...], [a, b]}`, but `Sourceror.to_string/1` *drops* the parens
  when printing that node on its own. There's no way to force them back. If a
  rule needs the parens kept exactly (e.g. stripping `* 1.0` from
  `(a + b) * 1.0`), it must slice the original bytes for the kept part instead of
  re-printing it — `Sourceror.get_range/1` *does* include the parens from the
  original text.

- **Position notes decide line-wrapping.** Sourceror chooses one line vs. several
  based on each node's `:line`/`:column`/`:closing` notes. When a rule builds a
  replacement out of fresh nodes (no notes) that reuse some original sub-nodes
  (with notes pointing far away), Sourceror sees a wide span and wraps lines it
  didn't need to. Two ways to handle it:
  - `RuleHelpers.render_replacement/3` strips
    `:line`/`:column`/`:closing`/`:last`/`:end` before printing, so wrapping goes
    back to being based on length. Both `patches_from_postwalk` and
    `patches_from_ast_transform` do this.
  - When building a new call that should sit on a known line (e.g. rewriting
    `Enum.member?` → `MapSet.member?`), copy the original call's
    `dot_meta`/`call_meta` onto the replacement so the span is kept.

## Walking block by block

Many Pattern rules need to act on a group of statements inside a function body,
an `if/else` branch, or a `case` clause. Each of those is a
`{:__block__, meta, stmts}` in the Sourceror tree (when it has 2 or more
statements). The natural way to handle it:

- Walk the tree. When you hit a `:__block__` with statements, rewrite them in
  place.
- Inner blocks are their own scope. A helper that gathers call sites within one
  statement should *stop* at a nested `:__block__`/`def`/`defp`/`fn` — those get
  their own block walk.

You can see this in `no_enum_at_negative_index` (groups bare negative-index
assignments per block) and `no_redundant_list_traversal` (merges several walks
over the same list).

## Where things live

- `lib/credence.ex` — the top-level `analyze/2` and `fix/2`. Runs the rounds in
  order.
- `lib/issue.ex` — the `%Issue{}` struct.
- `lib/rule_helpers.ex` — shared tools: the three patch-building helpers, the
  tree-comparing machinery, the Sourceror unwrappers, the after-the-fix check,
  and diff logging.
- `lib/syntax/`, `lib/semantic/`, `lib/pattern/` — one file per rule.
  `<round>.ex` runs that round; `<round>/rule.ex` is the kind-of-rule module.
- `test/<round>/<rule>_test.exs` — paired one-to-one with the rule files. Some
  rules split into `<rule>_check_test.exs` + `<rule>_fix_test.exs`.
- `test/support/rule_case.ex` — `Credence.RuleCase`, the one case template every
  per-rule test uses. `use Credence.RuleCase` (add `async: true`) pulls in
  `ExUnit.Case`, the rule verbs, and the equivalence harness. The verbs take the
  rule as their first argument: `check(rule, code)`, `flagged?(rule, code)`,
  `clean?(rule, code)`, `fix(rule, code)` (and `fix(rule, code, opts)` for the few
  rules whose fix takes a strategy). `fix/2` is **byte-exact** — it returns
  `apply_rule_fix`'s output verbatim, exactly what the pipeline ships, with no
  re-formatting. So `expected` is the real shipped bytes, and a rule that mangles
  the layout of lines it didn't touch is caught by the plain `== expected` (there
  is no formatter to launder it). This replaces the per-file `defp check`/`defp
  fix` helpers, which had drifted into several incompatible shapes — including
  ones that re-formatted the output and so tested bytes production never emits.
  It also exposes `valid_syntax?(code)` ("does this parse?") and `compiles?(code)`
  ("does this compile?"), so a test never reaches for `Sourceror`/`Code` itself.
  Rule tests must not: `test/no_parser_calls_in_rule_tests_test.exs` fails the
  build on any `Code.*`/`Sourceror.*` reference under `test/pattern|semantic|syntax`
  (heredoc fixtures are exempt — the gate is AST-based). Only `test/support` may
  touch the parser. Syntax/semantic tests (`use ExUnit.Case`, not `RuleCase`) reach
  `valid_syntax?` via `import Credence.RuleCase, only: [valid_syntax?: 1]`.
  Multi-line code fixtures use **heredocs**, never escaped `"...\n...\n..."` strings.
  `test/heredoc_fixtures_test.exs` enforces it (Sourceror delimiter-aware) and
  exempts what a heredoc can't carry — the `test`/`describe` name, a fixture whose
  code contains `"""` or `\#{`, a string ending in a blank line (`mix format` trims
  a heredoc's trailing blank), a pure-`"\n"` separator — plus a tiny reasoned
  allow-list (a line-number-sensitive diagnostic fixture). Heredocs add a trailing
  `\n`; since `fix/2` mirrors it, fix-test `input`/`expected` convert as a pair.
- `test/credence_pipeline_test.exs` — end-to-end tests, including the
  after-the-fix check (with on-purpose `BrokenFixRule` / `UnparseableFixRule`
  test rules).
- `test/fix_showcase_test.exs` — one realistic AI-written module run through
  `Credence.fix/2`; checks that every change lands.

## Adding a Pattern rule — checklist

1. Pick how you'll build patches: one walk-rewritable shape →
   `patches_from_postwalk`. Drops or adds siblings → `patches_from_ast_transform`.
   Needs the exact original bytes → walk and build the patches by hand.
2. Write `check/2` to find the problem. Pattern-match Sourceror's wrapped shape
   directly. Hand back `[Issue.t()]`.
3. Write `fix_patches/2`. Pattern-match Sourceror's wrapped shape when reading
   the tree; wrap any fresh simple values (numbers, strings, tuples) you make so
   `Sourceror.to_string/1` prints them right.
4. Write tests in `test/pattern/<rule>_test.exs`. Parse the source with
   `Sourceror.parse_string!/1` before calling `check/2`. Use
   `RuleHelpers.apply_rule_fix/3` to run the fix from a test.
5. Run the whole suite. The after-the-fix check will undo any rule that makes
   code that won't compile (with a debug log) — fix the rule or the helpers,
   don't cover up the symptom.

## Project policy

- **Fix or drop it.** Every rule fixes. If a rule can only find a problem, it is
  deleted, not kept as a warning.
- **Don't change the layout.** A rule's output must be byte-for-byte the same as
  the original everywhere it didn't change. Trailing newlines kept, blank lines
  between top-level forms kept, comments kept.
- **Don't go around the after-the-fix check.** If a rule makes code that won't
  compile, fix the rule. Don't turn the check off, don't `--no-verify`.
- **Sourceror only, no `Code.string_to_quoted`.** Every parse goes through
  Sourceror. `Code.string_to_quoted` (the built-in parser) does not appear in
  `lib/` or `test/` — it makes a different tree shape than Sourceror, and mixing
  the two quietly breaks rules. Both `check/2` and `fix_patches/2` get the
  Sourceror tree; rules pattern-match its wrapped shape directly. Building little
  bits of code inside a rule uses `Sourceror.parse_string!/1`, not
  `Code.string_to_quoted!/1`.
- **No `normalize_sourceror_ast/1` anywhere — rules or tests.** Every Pattern rule
  walks Sourceror's wrapped tree from start to finish. The helper still exists in
  `RuleHelpers` but is now unused: it used to be a shortcut inside three rules
  (removed because it smuggled the built-in tree shape into a Sourceror-only
  project), and a `norm`/`assert_fix` round-trip inside two fix tests (removed when
  those went byte-exact). Fix tests compare the rule's exact bytes with `==`; a
  normalized round-trip would launder a real layout regression. `FixMetaTest`
  forbids it (and `=~`/substring matching) so it can't creep back.
- **Rules don't re-parse the source to dodge a shape.** If a matcher doesn't fit,
  fix the matcher. Don't re-parse the text with a different parser to get a shape
  that does.
- **The answer must never change on any input your promises admit.** A rule must
  never trade a correct answer for a tidier or faster one. By default this is
  absolute: if the only rewrite available changes the answer on *some* input, the
  rule does not fix that case — and if it can't safely fix *any* case, it does not
  exist (don't even ship it as a find-only check). "Right for the usual input" is
  not good enough.

  The **one** escape hatch is a *safety switch* (`Credence.Assumptions`): a
  checkable promise about the program's running data. A rule may declare a switch
  via `assumptions/0` and then be correct only while that promise holds — but only
  after it has been **shrunk** so the promise covers *only* the rare-text gap
  (never a plain bug), and only with a **property test** proving old == new across
  promise-satisfying inputs. The reframed invariant: *Credence never changes
  behaviour on any input your stated promises admit.* `:strict` makes zero
  promises, so it stays bit-identical for **every** input — the old guarantee,
  reachable by one word. See `docs/03-safety-switches.md`.
- **Swapping codepoint work for grapheme work: banned by default, allowed only
  behind a switch.** Do **not** rewrite a charlist/codepoint operation into a
  grapheme one (or the other way round) unless it is gated on
  `single_codepoint_graphemes` (shrunk first, property-tested — see the bullet
  above). `String.to_charlist/1` and `?c`/`String.codepoints/1` work on the small
  pieces (codepoints); `String.at`/`String.reverse`/`String.length`/
  `String.graphemes`/`String.count` work on whole characters (graphemes). The two
  ways of counting drift apart whenever a character is made of more than one piece
  — accent-mark letters (`"b́"` = `b` + U+0301, with no ready-made single-piece
  form, so even normalizing can't merge it), joined emoji (`"👨‍👩‍👧"` = 1 character
  / 5 pieces), flags (`"🇵🇱"` = 1 / 2).

  Behind `single_codepoint_graphemes`, that drift can't happen, so a piece↔whole
  swap whose *only* remaining difference is multi-piece data becomes a valid fix
  (e.g. `String.graphemes(s) |> Enum.count(&(&1 == c))` → `String.count(s, c)`,
  and the codepoint half of `no_codepoint_string_reverse`).

  But a **type** change can never be promised away — a switch is a promise about
  *data*, and no promise makes a number equal a string. These stay banned in
  every mode:

  - `Enum.at(String.to_charlist(s), i)` → `String.at(s, i)`
    (a piece-number integer vs. a whole-character string — a type change)
  - `length(String.to_charlist(s))` → `String.length(s)` is only valid behind the
    switch (piece count vs. whole-character count — same type, data-only drift)

  **Same-kind** rewrites are always fine, no switch needed — e.g.
  `String.graphemes(s) == Enum.reverse(String.graphemes(s))` →
  `s == String.reverse(s)` is whole-character to whole-character and keeps the
  same answer for every input.
