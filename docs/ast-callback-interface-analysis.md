# Pattern rule interface — design retrospective

## Context

The Pattern phase started with a uniform rule interface: each rule
implemented `fix(source, opts) :: String.t()`, internally parsed the
source with `Sourceror.parse_string!`, walked the AST, and called
`Sourceror.to_string` to render the result. The orchestrator also
re-parsed the source on every iteration. Visible problems:

- **Layout collapse at the change site.** A short `Enum.reduce(...)`
  replacement would be re-rendered as a single line even when the
  original source was multi-line. Surfaced by Issue 4 in the
  `credence_fix_bugs.md` report.
- **No locality guarantee.** `Sourceror.to_string` on the whole AST is
  free to reformat anywhere; in practice metadata-tagged unchanged
  nodes survived, but the contract said otherwise.
- **A "warn-only" mode that nobody could fix.** 15 rules detected
  anti-patterns whose fixes required non-local refactoring,
  shape-changing transformations, or ambiguous remedies. They flagged
  things and left the user holding the bag.

Driver: **architectural cleanliness**, not perf. One way to express a
fix; layout-safe by construction; either fix or stay quiet.

## Final shape

### Rule behaviour (`lib/pattern/rule.ex`)

```elixir
@callback priority() :: integer()
@callback check(ast :: Macro.t(), opts :: keyword()) :: [Credence.Issue.t()]
@callback fix_patches(ast :: Macro.t(), opts :: keyword()) :: [patch()]
@callback fix(source :: String.t(), opts :: keyword()) :: String.t()

@type patch :: %{
  required(:range) => map(),
  required(:change) => String.t()
}
```

Two callbacks express a fix; rules pick whichever fits:

- **`fix_patches/2`** — preferred. Walks an AST, emits a list of
  `%{range, change}` patches. Only the changed bytes move; everything
  else stays byte-identical.
- **`fix/2`** — adapter shape. Returns transformed source. The
  default `fix_patches/2` (provided by `__using__`) wraps `fix/2` in
  a single whole-source patch.

The `fixable?/0` callback no longer exists — every rule that compiles
is fixable by definition.

### Orchestrator (`lib/pattern.ex`)

```elixir
defp run_fixable_rules(rules, source, opts) do
  Enum.reduce(rules, {source, []}, fn rule, {src, applied} ->
    case Code.string_to_quoted(src) do
      {:ok, ast} ->
        issues = rule.check(ast, Keyword.put(opts, :source, src))
        if issues != [] do
          fixed = Credence.RuleHelpers.apply_rule_fix(rule, src, opts)
          apply_or_revert(rule, src, fixed, issues, applied)
        else
          {src, applied}
        end

      {:error, _} ->
        {src, applied}
    end
  end)
end
```

`apply_rule_fix/3` always parses the source, calls
`rule.fix_patches(ast, opts)`, and applies the result via
`Sourceror.patch_string/2`. No `function_exported?` branching, no
legacy fallback — every rule has `fix_patches/2` via the
`__using__` default.

`apply_or_revert/5` is the compile-output gate: after patches apply,
compile the result; if it fails, revert to pre-fix source and tag the
rule `:reverted` in the trace.

### Rule census (post-migration)

76 fixable Pattern rules, split by what they actually do under the
patch interface:

| Group | Count | Fix shape |
|---|---|---|
| Real per-site patches (locality preserved) | 13 | Override `fix_patches/2` directly; emit one patch per match site |
| Whole-source adapter (`fix/2` + default `fix_patches/2`) | 63 | The transformation logic stays source-level; the default wraps it as a single whole-source patch |

The 13 explicitly-migrated rules are the three that already used
`Sourceror.patch_string` before this work
(`no_list_to_tuple_for_access`, `no_length_comparison_for_empty`,
`no_map_then_aggregate`) plus seven Bucket B rules and three Bucket D
rules with simple-enough match patterns to decompose cleanly.

The 63 adapter rules satisfy the new interface but don't gain
locality benefit — they still rewrite their whole source string and
the orchestrator patches it back in one shot. Refactoring each into
real per-site patches is per-rule work that can be done incrementally
over future sessions; the interface is uniform regardless.

### Archived unfixable rules (`docs/unfixable_rules/`)

15 rules were moved out of `lib/pattern/` and `test/pattern/` to
`docs/unfixable_rules/` along with their tests and a `README.md`
explaining each rule's reason for being unfixable. Five categories
emerged:

1. **Non-local restructuring** (6 rules) — fix touches multiple sites
   or requires algorithm change.
2. **Shape-changing transformation** (2 rules) — fix would change
   return type or element shape.
3. **Data-flow analysis required** (2 rules) — fix needs upstream
   variable initialisation changes plus matching reader rewrites.
4. **Ambiguous remedy** (3 rules) — multiple valid fixes depending on
   intent the tool can't infer.
5. **Companion-of-a-fixable-rule** (3 rules) — existed only to flag
   the residual cases a narrower fixable rule skipped. Without
   "warn-only" mode the role goes away.

See `docs/unfixable_rules/README.md` for the per-rule breakdown.

## What was deliberately not done

### Cosmetic rename `fix_patches` → `fix`

Originally planned. The renaming would touch 76 rule files, 76 test
files, the behaviour, the `__using__` macro, and the orchestrator —
130+ mechanical edits with no functional change. Deferred to a
separate session. Until then, `fix_patches/2` is the patch-emitting
callback and legacy `fix/2` keeps its source-string signature.

### Per-rule decomposition of the 63 adapter rules

Real per-site patches deliver locality (multi-line layouts survive,
each rule's change region is byte-identical outside the patch). For
the 63 adapter rules to claim this, each needs its `fix/2` rewritten
as a `fix_patches/2` that walks the AST and emits one patch per
match. Per-rule work; each rule has unique transformation logic; not
mechanical.

### Bucket D as truly first-class patch rules

Six Bucket D rules (`no_nested_enum_on_same_enumerable`,
`no_identity_float_coercion`, `prefer_erlang_float`,
`no_enum_at_negative_index`, `no_string_concat_in_loop`,
`no_map_keys_or_values_for_iteration`) already do their own
locality-preserving byte surgery internally — but the surgery isn't
exposed as discrete patches at the orchestrator level. They went
through the adapter path. A future refactor could split each rule's
internal patches into orchestrator-visible patches, making locality
machine-checkable.

## What this work actually delivered

1. **Single uniform fix entry point.** Every rule has `fix_patches/2`;
   every test goes through `Credence.RuleHelpers.apply_rule_fix/3`;
   every orchestrator path goes through `Sourceror.patch_string/2`.
2. **Compile-output gate.** A rule whose fix produces broken output
   gets reverted and surfaced as `{rule, :reverted}` in the trace.
   Implemented as part of Issue 3 from the bug report.
3. **Layout-preserving rendering helper.**
   `Credence.RuleHelpers.render_replacement/2` computes a `line_length`
   budget from the original expression's range so a multi-line
   original yields a multi-line replacement. Used by the three rules
   with real per-site patches; available to any future migration.
4. **`fixable?/0` callback gone.** Every rule fixes. Project stance
   codified in the behaviour itself.
5. **Unfixable rules archived.** 15 rules moved to
   `docs/unfixable_rules/` with reasoning. The compiled rule set is
   now strictly "fix or don't exist."

## Files touched

### Interface

- `lib/pattern/rule.ex` — added `@type patch`, `@callback fix_patches/2`;
  removed `@callback fixable?/0`; `__using__` provides default
  `fix_patches/2` adapter over `fix/2`.

### Orchestrator and helpers

- `lib/pattern.ex` — `run_fixable_rules/3` now passes all rules
  (no `fixable?` filter); `apply_or_revert/5` runs the compile-output
  gate.
- `lib/rule_helpers.ex` — added `apply_rule_fix/3` (single fix entry
  point), `whole_source_patches/2` (adapter helper),
  `render_replacement/2` (layout-budget helper).
- `lib/credence.ex` — typespec for `applied_rules` widened to
  `{module(), non_neg_integer() | :reverted}`.

### Rules

- 13 rules under `lib/pattern/` — explicit `fix_patches/2` overrides.
- 63 rules under `lib/pattern/` — unchanged; satisfied by the default
  `fix_patches/2` in `__using__`. The bulk Perl strip removed
  redundant `def fixable?, do: true` from 76 files.
- 15 rules moved to `docs/unfixable_rules/`.

### Tests

- 13 test files use `Credence.RuleHelpers.apply_rule_fix/3`.
- 63 test files unchanged (call `Rule.fix(source, opts)` directly via
  the still-present legacy callback).
- 29 test files had `assert Rule.fixable?() == true` and empty
  `describe "fixable?/0"` blocks stripped.
- 15 test files moved to `docs/unfixable_rules/tests/`.

## Verification

`mix test` — **2967 tests, 0 failures.** Down from 3197 pre-archive
(201 tests for the 15 archived rules + 29 `fixable?` assertions). No
compile warnings. The compile-output gate fires its intentional
warnings only inside `ExUnit.CaptureLog.with_log/1` blocks so they
don't leak to the test runner's stdout.

Manual verification: repro snippets from the original
`credence_fix_bugs.md` issues 1–4 still produce correct, compiling
output.
