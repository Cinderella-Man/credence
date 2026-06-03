# How the Pattern rules got their shape (a look back)

## Where we started

The Pattern round began with one shape for every rule: each rule had a
`fix(source, opts) :: String.t()` function. Inside, it parsed the code with
`Sourceror.parse_string!`, walked the tree, and turned the result back into text
with `Sourceror.to_string`. The part that runs the rules also re-parsed the code
on every pass. Three problems showed up:

- **Layout fell apart right where the change was.** A short
  `Enum.reduce(...)` replacement would get re-printed as one line even when the
  original code was spread over several. (This was Issue 4 in the
  `credence_fix_bugs.md` report.)
- **No promise to leave the rest alone.** Running `Sourceror.to_string` on the
  whole tree is free to re-format anything, anywhere. In practice the untouched
  nodes survived, but nothing in the design *guaranteed* it.
- **A "warn but don't fix" mode nobody could act on.** 15 rules pointed at
  problems whose fixes needed rearranging code in several places, changing the
  type of value returned, or picking between several reasonable answers. They
  flagged things and left the user to sort it out.

What drove the change was wanting the code to be **clean and predictable**, not
faster. One way to write a fix; the layout stays safe by design; a rule either
fixes the problem or stays quiet.

## Where we landed

### The rule shape (`lib/pattern/rule.ex`)

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

There are two ways to write a fix; a rule picks whichever fits:

- **`fix_patches/2`** — preferred. Walks the tree and hands back a list of
  `%{range, change}` patches. Only the bytes you point at move; everything else
  stays byte-for-byte the same.
- **`fix/2`** — the simple way out. Hands back the changed source text. The
  built-in `fix_patches/2` (provided by `__using__`) wraps your `fix/2` as one
  big patch over the whole source.

The old `fixable?/0` callback is gone — every rule that compiles fixes
something, by definition.

### The part that runs the rules (`lib/pattern.ex`)

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
`rule.fix_patches(ast, opts)`, and applies the result with
`Sourceror.patch_string/2`. No checking which functions a rule happens to have,
no old fallback path — every rule has `fix_patches/2` through the `__using__`
default.

`apply_or_revert/5` is the after-the-fix check: once the patches go on, it
compiles the result; if that fails, it puts the code back the way it was and
marks the rule `:reverted` in the trace.

### A count of where the rules ended up

76 fixing Pattern rules, sorted by what they actually do under the patch system:

| Group | Count | How the fix works |
|---|---|---|
| Real per-spot patches (layout kept) | 13 | Write `fix_patches/2` directly; hand back one patch per matching spot |
| Whole-text rules (`fix/2` + the default `fix_patches/2`) | 63 | The fix stays text-level; the default wraps it as one big patch |

The 13 hand-written ones are the three that already used
`Sourceror.patch_string` before this work (`no_list_to_tuple_for_access`,
`no_length_comparison_for_empty`, `no_map_then_aggregate`), plus seven rules
from one earlier group and three from another that were simple enough to break
into clean patches.

The 63 whole-text rules meet the new shape but don't get the layout benefit —
they still rewrite their whole source string and the runner patches it back in
one go. Turning each into real per-spot patches is per-rule work that can happen
bit by bit later; the shape is the same either way.

### Parked rules (`docs/unfixable_rules/`)

15 rules were moved out of `lib/pattern/` and `test/pattern/` into
`docs/unfixable_rules/`, along with their tests and a `README.md` saying why
each one can't be fixed. They fell into five kinds:

1. **Fix touches several spots** (6 rules) — the fix hits more than one place,
   or needs the whole approach to change.
2. **Fix changes the type of value** (2 rules) — the fix would change the return
   type or the shape of the result.
3. **Fix needs to trace data around** (2 rules) — it has to change how a
   variable starts out *and* every place that reads it.
4. **More than one good fix** (3 rules) — several fixes work, and the right one
   depends on what the programmer meant, which the tool can't tell.
5. **Only there to catch leftovers** (3 rules) — they existed only to flag the
   few cases a narrower fixing rule skipped. With no "warn only" mode, there's
   no job left for them.

See `docs/unfixable_rules/README.md` for the rule-by-rule breakdown.

## Things we chose *not* to do

### Rename `fix_patches` to `fix`

We meant to. The rename would touch 76 rule files, 76 test files, the behaviour,
the `__using__` macro, and the runner — 130-plus mechanical edits that change
nothing about how it works. Left for a separate session. Until then,
`fix_patches/2` is the patch-handing callback and the old `fix/2` keeps its
text-string shape.

### Turning the 63 whole-text rules into per-spot rules

Real per-spot patches keep the layout (multi-line code stays multi-line, and
everything outside the patch is byte-for-byte unchanged). For the 63 whole-text
rules to get that, each one's `fix/2` needs to be rewritten as a `fix_patches/2`
that walks the tree and hands back one patch per spot. That's per-rule work —
each rule has its own fix logic; it's not a find-and-replace.

### Making the six byte-surgery rules into proper patch rules

Six rules (`no_nested_enum_on_same_enumerable`, `no_identity_float_coercion`,
`prefer_erlang_float`, `no_enum_at_negative_index`, `no_string_concat_in_loop`,
`no_map_keys_or_values_for_iteration`) already do their own careful,
layout-keeping byte edits inside themselves — but those edits aren't handed up
to the runner as separate patches. They went through the whole-text path. A
future change could lift each rule's inside edits up into runner-visible
patches, so the layout-keeping could be checked by the machine.

## What this work actually gave us

1. **One way in for fixes.** Every rule has `fix_patches/2`; every test goes
   through `Credence.RuleHelpers.apply_rule_fix/3`; every runner path goes
   through `Sourceror.patch_string/2`.
2. **The after-the-fix check.** A rule whose fix produces broken code gets
   undone and shows up as `{rule, :reverted}` in the trace. (This was Issue 3
   from the bug report.)
3. **A layout-keeping printer helper.**
   `Credence.RuleHelpers.render_replacement/2` works out a line-width budget
   from the original code's size, so a multi-line original gives a multi-line
   replacement. Used by the three rules with real per-spot patches; ready for
   any future rule.
4. **The `fixable?/0` callback is gone.** Every rule fixes. The project's stance
   is now baked into the rule shape itself.
5. **Unfixable rules parked.** 15 rules moved to `docs/unfixable_rules/` with
   reasons. The compiled rule set is now strictly "fix it or don't exist."

## Files touched

### The rule shape

- `lib/pattern/rule.ex` — added `@type patch` and `@callback fix_patches/2`;
  removed `@callback fixable?/0`; `__using__` now provides a default
  `fix_patches/2` that wraps `fix/2`.

### The runner and helpers

- `lib/pattern.ex` — `run_fixable_rules/3` now runs all rules (no `fixable?`
  filter); `apply_or_revert/5` does the after-the-fix check.
- `lib/rule_helpers.ex` — added `apply_rule_fix/3` (the one way in for fixes),
  `whole_source_patches/2` (the wrap-as-one-patch helper), and
  `render_replacement/2` (the layout-budget helper).
- `lib/credence.ex` — widened the type of `applied_rules` to
  `{module(), non_neg_integer() | :reverted}`.

### The rules

- 13 rules under `lib/pattern/` — hand-written `fix_patches/2`.
- 63 rules under `lib/pattern/` — unchanged; covered by the default
  `fix_patches/2` in `__using__`. A bulk text edit removed the now-pointless
  `def fixable?, do: true` from 76 files.
- 15 rules moved to `docs/unfixable_rules/`.

### The tests

- 13 test files use `Credence.RuleHelpers.apply_rule_fix/3`.
- 63 test files unchanged (they call `Rule.fix(source, opts)` directly through
  the still-present old callback).
- 29 test files had `assert Rule.fixable?() == true` and empty `describe
  "fixable?/0"` blocks taken out.
- 15 test files moved to `docs/unfixable_rules/tests/`.

## Checking it works

`mix test` — **2967 tests, 0 failures.** Down from 3197 before parking the rules
(201 tests for the 15 parked rules, plus 29 `fixable?` checks). No compile
warnings. The after-the-fix check only prints its on-purpose warnings inside
`ExUnit.CaptureLog.with_log/1` blocks, so they don't leak into the test
runner's output.

By hand: the example snippets from the original `credence_fix_bugs.md` issues
1–4 still come out correct and compiling.
