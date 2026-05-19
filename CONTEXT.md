# Credence — Context

Semantic linter for Elixir. Detects anti-patterns in LLM-generated code and
either auto-fixes them or removes them from the codebase. Project stance:
**every rule either fixes its anti-pattern or it doesn't exist** — warn-only
rules have been archived to `docs/unfixable_rules/`.

## Parser: Sourceror only

Credence uses **Sourceror's AST exclusively**. `Code.string_to_quoted/1`
(Elixir's standard parser) does **not** appear anywhere in `lib/` or `test/`
— greppable invariant. All parsing goes through `Sourceror.parse_string/1`
or `Sourceror.parse_string!/1`, including:

- Both Pattern callbacks (`check/2` and `fix_patches/2`).
- The Syntax phase's parse-success guard.
- The Pattern orchestrator's per-iteration re-parse.
- Test invocations of `check/2` (test files parse with `Sourceror.parse_string!/1`).
- Template construction inside rules (e.g. `Sourceror.parse_string!("require Logger")`).

Sourceror's AST is **not** the same as Elixir's standard `Code.string_to_quoted`
AST. The shape differences are the main thing to internalize when writing
or reading a rule — see "Sourceror AST gotchas" below. Standard-AST
pattern matches like `{:==, _, [_, 1]}` will silently fail to match against
Sourceror's `{:==, _, [_, {:__block__, _, [1]}]}`, which is the most common
source of "my rule doesn't fire" bugs.

## Pipeline

`Credence.fix/2` runs three phases in order. Each phase has its own `Rule`
behaviour and discovers rules automatically via `RuleHelpers.discover_rules/1`.

1. **Syntax** (`lib/syntax/`) — string-level fixes for code that won't parse.
   No AST available. Rules take `String.t() -> String.t()`.
2. **Semantic** (`lib/semantic/`) — fixes for compiler warnings. Rules match
   against `Code.with_diagnostics/1` output and patch the source.
3. **Pattern** (`lib/pattern/`) — the bulk of Credence: 76 AST-level
   anti-pattern rules.

Phases run sequentially; if syntax issues remain, semantic/pattern are
skipped. Pattern phase skips entirely if the source doesn't compile —
applying AST transforms to broken code risks wasting an LLM retry.

## Pattern phase — the rule interface

Every rule in `lib/pattern/` implements three callbacks:

```elixir
@callback priority() :: integer()                                  # default 500
@callback check(ast :: Macro.t(), opts :: keyword()) :: [Issue.t()]
@callback fix_patches(ast :: Macro.t(), opts :: keyword()) :: [patch]
```

**Both callbacks receive Sourceror AST** (`Sourceror.parse_string!/1`),
not the standard `Code.string_to_quoted` AST. The two shapes differ:
literals, atoms, lists, and 2-tuples are wrapped in `{:__block__, meta, [value]}`
nodes to carry position and delimiter metadata. Strings carry a
`:delimiter` key in the block meta (`"\""` vs `~s(""")`). See "Sourceror
AST gotchas" below for the full surface area.

`opts` carries `:source` for rules that need raw bytes (e.g. for slicing
into a patch's `change`).

A `patch` is `%{range: Sourceror.Range, change: String.t()}` — apply via
`Sourceror.patch_string/2`. Empty list = no change.

### Three patch-emission patterns

Rules differ in *how* they compute their patches, not in their return shape:

- **`RuleHelpers.patches_from_postwalk(ast, matcher)`** — single
  `Macro.postwalk/2` matcher, helper diffs original vs. transformed AST and
  emits one patch per outermost change. Used by ~50 rules.
- **`RuleHelpers.patches_from_ast_transform(ast, source, transform_fn)`** —
  arbitrary AST → AST transform; the helper renders the result via
  `Sourceror.to_string/1`, re-parses, and diffs. Use when the transform
  prunes/reorders siblings or inserts statements into a block (single
  `postwalk` matcher can't express it).
- **Direct patch emission** — the rule walks the AST itself and builds
  `[%{range: ..., change: ...}]`. Use when the kept subtree's *source bytes*
  must be preserved verbatim — typically because Sourceror's renderer
  would drop them (see Sourceror gotchas).

There is no source-level helper. `patches_from_fix_source` existed during the
migration and was deleted once the last rule converted.

## Domain vocabulary

- **Rule** — a module implementing one of the three `Rule` behaviours
  (Syntax / Semantic / Pattern).
- **Issue** — `%Credence.Issue{rule, message, meta: %{line: ...}}`. Same
  struct across all phases.
- **Check** — the issue-detection function (`check/2` for Pattern;
  `analyze/1` for Syntax; `match?/1` + `to_issue/1` for Semantic).
- **Fix** — the patch-producing function (`fix_patches/2` for Pattern;
  `fix/1` for Syntax/Semantic).
- **Patch** — `%{range, change}`. Sourceror's byte-range edit format.
- **Applied trace** — `[{rule_module, count_or_:reverted}]`. Returned by
  `fix_with_trace/2` for each phase. `:reverted` means a rule produced
  non-compiling output and the orchestrator backed out its changes.
- **Compile-output gate** — after each rule's patches apply, the Pattern
  orchestrator runs `Code.compile_string/2`. If the result fails to
  compile, the rule's changes are reverted and a warning is logged. This
  catches rules that emit syntactically valid but semantically broken
  output before the LLM sees it.
- **Unfixable rule** — a rule that could only detect, never fix. Archived
  to `docs/unfixable_rules/` (with its tests) and excluded from
  compilation. The README explains why.

## Sourceror AST gotchas

Sourceror's parser produces an AST that mostly mirrors Elixir's standard
AST (the one `Code.string_to_quoted/1` produces) but with critical
differences. Rules that don't account for these silently fail to match.

- **Literal wrappers**: Sourceror wraps literals (atoms, integers, floats,
  strings, 2-tuples, lists) in `{:__block__, meta, [value]}` to carry
  position metadata. Standard Elixir AST has bare literals. A pattern like
  `{:==, _, [_, 1]}` won't match Sourceror's `{:==, _, [_, {:__block__, _, [1]}]}`.
  Two ways to handle it:
  - `RuleHelpers.normalize_sourceror_ast/1` — strips all wrappers, giving
    you bare-literal shape. Loses position info, but matchers become
    simpler. Best used inside `check/2` where you only need line numbers
    (which live on outer 3-tuple nodes, not on literals).
  - Match Sourceror's wrapped shape directly. Use `unwrap_literal/1` /
    `unwrap_list/1` / `extract_do_body/1` in `RuleHelpers` for the common
    patterns (literal-or-bare, list-or-wrapped-list, do-keyword).
- **String `:delimiter` metadata**: heredocs (`"""`) and regular strings
  (`"`) produce the *same* string value in standard Elixir AST — both
  collapse to a bare binary. Sourceror keeps them apart via a `:delimiter`
  key in the string's `:__block__` meta (`~s(""")` for heredocs, `"\""`
  for regular). Rules that need to skip heredocs (e.g. `NoTrailingNewlineInDoc`,
  `PreferHeredocForMultiLineDoc`) read that key — no `:source`-string
  inspection needed.
- **`:parens` metadata is one-way**: `(a - b)` parses to `{:-, [parens: ...], [a, b]}`
  but `Sourceror.to_string/1` *drops* the parens when rendering the node
  standalone. There's no API to force their preservation. If a rule needs
  parens kept verbatim (e.g. stripping `* 1.0` from `(a + b) * 1.0`), it
  must slice the original source bytes for the kept subtree instead of
  re-rendering — `Sourceror.get_range/1` *does* include source-level parens.
- **Layout meta drives line-wrap decisions**: Sourceror picks single-line vs.
  multi-line layout based on each node's `:line`/`:column`/`:closing` meta.
  When a rule builds a replacement subtree from fresh nodes (empty meta)
  containing reused original subnodes (with line meta from far away),
  Sourceror sees a wide line span and wraps unnecessarily. Mitigations:
  - `RuleHelpers.render_replacement/3` strips `:line`/`:column`/`:closing`/`:last`/`:end`
    before rendering, restoring length-based layout. Both
    `patches_from_postwalk` and `patches_from_ast_transform` apply this.
  - When building a new call that should sit on a known source line (e.g.
    rewriting `Enum.member?` → `MapSet.member?`), copy the original call's
    `dot_meta`/`call_meta` onto the replacement to preserve line span.

## Block-scope walking

Many Pattern rules need to act on statement groups within a function body,
`if/else` branch, or `case` clause. Each is a `{:__block__, meta, stmts}`
in Sourceror AST (when it has 2+ statements). The natural unit:

- Walk the AST. When we hit a `:__block__` with statements, rewrite them
  in place.
- Inner blocks are separate scopes. Helpers that collect call sites within
  a single statement should *stop* at nested `:__block__`/`def`/`defp`/`fn`
  — those scopes get their own block-walk pass.

This pattern shows up in `no_enum_at_negative_index` (groups bare negative-
index assignments per block) and `no_redundant_list_traversal` (merges
multiple traversals of the same list).

## Where things live

- `lib/credence.ex` — top-level `analyze/2` and `fix/2`. Sequences phases.
- `lib/issue.ex` — the `%Issue{}` struct.
- `lib/rule_helpers.ex` — shared utilities. The three patch-emission
  helpers, AST-diff machinery, Sourceror-shape unwrappers, compile gate,
  diff logging.
- `lib/syntax/`, `lib/semantic/`, `lib/pattern/` — one file per rule.
  `<phase>.ex` is the phase orchestrator; `<phase>/rule.ex` is the
  behaviour module.
- `test/<phase>/<rule>_test.exs` — paired one-to-one with rule files.
  Some rules split into `<rule>_check_test.exs` + `<rule>_fix_test.exs`.
- `docs/unfixable_rules/` — archived check-only rules with their tests
  and a README explaining the policy.
- `test/credence_pipeline_test.exs` — end-to-end pipeline tests including
  the compile-output gate (with intentional `BrokenFixRule` /
  `UnparseableFixRule` fixtures).
- `test/fix_showcase_test.exs` — a single realistic LLM-generated module
  put through `Credence.fix/2`; verifies every transformation lands.

## Adding a Pattern rule — checklist

1. Pick the matcher form: a single postwalk-rewritable shape →
   `patches_from_postwalk`. Restructures or inserts siblings →
   `patches_from_ast_transform`. Needs verbatim source bytes → walk + emit
   patches directly.
2. Write `check/2` to detect the issue. Return `[Issue.t()]`.
3. Write `fix_patches/2`. Handle Sourceror's `:__block__` wrappers — either
   normalize first or match both shapes.
4. Write tests in `test/pattern/<rule>_test.exs`. Use
   `RuleHelpers.apply_rule_fix/3` to invoke the fix from a test.
5. Run the full suite. The compile-output gate will revert any rule that
   produces non-compiling output (with a debug log) — fix the rule or the
   helpers, don't paper over the symptom.

## Project policy

- **Fix or archive**: every rule auto-fixes. If a rule can only detect,
  move it to `docs/unfixable_rules/` rather than leaving it as a warning.
- **No layout regressions**: rule output must be byte-identical to the
  original for unchanged regions. Trailing newlines preserved, blank lines
  between top-level forms preserved, comments preserved.
- **No bypassing the compile gate**: if a rule produces non-compiling
  output, fix the rule. Don't disable the gate, don't `--no-verify`.
- **Sourceror only, no `Code.string_to_quoted`**: every parser invocation
  goes through Sourceror. `Code.string_to_quoted` (Elixir's standard
  parser) does not appear in `lib/` or `test/` — it produces a different
  AST shape than Sourceror, and mixing the two silently corrupts rule
  behaviour. Both `check/2` and `fix_patches/2` receive Sourceror AST;
  rules pattern-match against its wrapped-literal shape (or use
  `normalize_sourceror_ast/1` when the matchers are simpler in bare form).
  Template construction inside a rule uses `Sourceror.parse_string!/1`,
  not `Code.string_to_quoted!/1`.
- **Rules don't re-parse the source as a shape workaround**: if a matcher
  doesn't fit, fix the matcher or normalize the AST — don't re-parse the
  source string with a different parser to get a shape that matches.
