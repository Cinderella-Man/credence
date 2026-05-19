# Credence

A semantic linter for LLM-generated Elixir code.

Elixir's compiler checks syntax. Credo checks style. Credence checks *semantics* — it mainly catches patterns that compile and pass tests but are non-idiomatic, inefficient, or ported from Python/JavaScript conventions that don't belong in Elixir.

## Three-phase pipeline

Credence runs code through three escalating phases:

```
Credence.Syntax    → can the parser read it?     (string-level fixes)
Credence.Semantic  → does the compiler accept it? (compiler warning fixes)
Credence.Pattern   → is it idiomatic Elixir?      (~76 AST-level rules)
```

**Syntax** repairs code that won't parse — e.g. `n * (n + 1) div 2` (Python's `//` translated as infix) becomes `div(n * (n + 1), 2)`.

**Semantic** captures compiler warnings via `Code.with_diagnostics/1` and fixes them — unused variables get `_` prefixed, undefined function calls get corrected(if possible).

**Pattern** detects and auto-fixes ~76 anti-patterns using AST analysis — `Enum.sort |> Enum.reverse` becomes `Enum.sort(:desc)`, manual frequency counting becomes `Enum.frequencies/1`, `acc ++ [x]` becomes `[x | acc]`.

Each phase has its own `Rule` behaviour. Rules are discovered automatically and run in priority order.

**Project stance: every Pattern rule auto-fixes the issue it detects.** There is no "warn-only" mode. Anti-patterns whose fix needs non-local restructuring, ambiguous remedies, or return-shape changes were archived to `docs/unfixable_rules/` and removed from the compiled rule set — see that folder's `README.md` for the full list and reasoning.

## Installation

```elixir
def deps do
[
  {:credence, "~> 0.4.3", only: [:dev, :test], runtime: false}
]
end
```

## Usage

**Analyze** — detect issues without modifying code:

```elixir
%{valid: true, issues: []} = Credence.analyze(code)
```

**Fix** — auto-fix what's fixable, report the rest:

```elixir
%{code: fixed, issues: remaining} = Credence.fix(code)
```

### Example

```elixir
code = ~S"""
defmodule StudentAnalyzer do
  @doc "Analyzes scores.\nReturns statistics.\n"

  def analyze(scores) do
    if length(scores) == 0 do
      %{error: "no scores"}
    else
      total = Enum.map(scores, fn s -> s end) |> Enum.sum()
      avg = total / Enum.count(scores) * 1.0
      freq = Enum.reduce(scores, %{}, fn s, acc ->
        Map.update(acc, s, 1, &(&1 + 1))
      end)
      ranked = Enum.sort(scores) |> Enum.reverse()
      top_3 = Enum.sort(scores) |> Enum.take(-3)
      unique = scores |> Enum.uniq_by(fn s -> s end)
      csv = Enum.map(unique, fn s -> Integer.to_string(s) end) |> Enum.join(",")

      %{average: avg, frequencies: freq, top_3: top_3,
        csv: csv, passing: is_passing(avg)}
    end
  end

  def is_passing(avg), do: avg |> Kernel.>=(60.0)
end
"""

%{code: fixed, issues: remaining} = Credence.fix(code)
```

You can run a subset of rules:

```elixir
Credence.analyze(code, rules: [
  Credence.Pattern.NoListAppendInRecursion,
  Credence.Pattern.NoSortForTopK,
  Credence.Pattern.NoListFold
])
```

## Writing custom rules

Each phase has its own `Rule` behaviour:

### Pattern rules (AST-level)

A Pattern rule has two parts: `check/2` returns issues for the analyze phase, and the fix is expressed as **either** of two shapes — pick whichever is cleaner for your transformation.

**Shape A — patches (preferred).** Walk the AST, locate target nodes via `Sourceror.get_range/1`, emit `%{range, change}` patches. Only the changed bytes move; layout outside the change site is preserved by construction.

```elixir
defmodule Credence.Pattern.MyRule do
  use Credence.Pattern.Rule

  @impl true
  def priority, do: 500  # default; lower runs first

  @impl true
  def check(ast, _opts) do
    {_ast, issues} =
      Macro.prewalk(ast, [], fn node, issues ->
        # pattern match on node, push %Credence.Issue{} when matched
        {node, issues}
      end)
    Enum.reverse(issues)
  end

  @impl true
  def fix_patches(ast, _opts) do
    {_ast, patches} =
      Macro.prewalk(ast, [], fn node, acc ->
        # for each matched node, emit:
        #   %{range: Sourceror.get_range(node), change: replacement_source}
        {node, acc}
      end)
    Enum.reverse(patches)
  end
end
```

**Shape B — whole-source adapter.** When the transformation is naturally source-level (regex replacement, line surgery, etc.), implement `fix/2` instead. The default `fix_patches/2` from `use Credence.Pattern.Rule` wraps it as a single whole-source patch.

```elixir
defmodule Credence.Pattern.MyRule do
  use Credence.Pattern.Rule

  @impl true
  def check(ast, _opts), do: [...]

  @impl true
  def fix(source, _opts) do
    # return modified source string; layout is your responsibility
    source
  end
end
```

Shape A delivers better layout preservation when multiple rules fire on the same file. Shape B is fine for self-contained one-shot rewrites.

### Syntax rules (string-level, for unparseable code)

```elixir
defmodule Credence.Syntax.MyFix do
  use Credence.Syntax.Rule

  @impl true
  def analyze(source), do: []  # return [%Issue{}] for detected problems

  @impl true
  def fix(source), do: source  # return repaired source string
end
```

### Semantic rules (compiler warning fixes)

```elixir
defmodule Credence.Semantic.MyFix do
  use Credence.Semantic.Rule

  @impl true
  def match?(%{severity: :warning, message: msg}), do: false

  @impl true
  def to_issue(diagnostic), do: %Credence.Issue{rule: :my_fix, message: diagnostic.message, meta: %{}}

  @impl true
  def fix(source, diagnostic), do: source
end
```

## How the fix pipeline works

When you call `Credence.fix(code)`, your source string passes through three phases in sequence. Each phase targets a different class of problem, and they're ordered so that earlier phases clean up issues that would confuse later ones.

Here's the full picture:

```
                  ┌──────────┐
  source string → │  Syntax  │ → can it be parsed?
                  └────┬─────┘
                       │
                  ┌────▼─────┐
                  │ Semantic │ → does it compile? fix warnings
                  └────┬─────┘
                       │
                  ┌────▼─────┐
                  │ Pattern  │ → is it idiomatic? (only if it compiles)
                  └────┬─────┘
                       │
                  fixed source + remaining issues
```

### Phase 1: Syntax — string-level repair

Syntax rules work on the raw source string, before Elixir's parser ever sees it. They only run when `Code.string_to_quoted/1` fails — if the code already parses, this phase is skipped entirely.

This is where we fix things like Python-style `//` integer division that the LLM translated literally.
The rules use string operations and regex — no AST involved.

If syntax rules manage to fix the code so it parses, the pipeline moves on. If it still doesn't parse after all syntax rules have run, the remaining phases do their best with what they have.

### Phase 2: Semantic — compiler warning fixes

This phase compiles the source using `Code.compile_string/2` wrapped in `Code.with_diagnostics/1`. That gives us the same warnings and errors you'd see in your terminal — unused variables, undefined functions, and so on.

Each diagnostic gets matched against semantic rules. If a rule knows how to fix it, it modifies the source. For example, the `UnusedVariable` rule turns `count` into `_count` when it's never used.

If the code has compile **errors** (not just warnings), semantic rules try to fix those first, then re-compile to catch any warnings that were hidden behind the errors. This retry loop runs up to three passes.

### Phase 3: Pattern — AST-level anti-pattern detection

These rules look at the parsed AST for patterns that compile fine and pass tests but aren't idiomatic Elixir. Think of it as an opinionated code reviewer that knows what LLMs tend to get wrong.

**The compile gate.** Before running any pattern rules, Credence compiles the source one more time to check if it actually succeeds. If the code doesn't compile — say it has an undefined variable that no semantic rule could fix — pattern rules are skipped entirely. This is deliberate. Pattern rules rewrite code based on AST structure, and rewriting code that has semantic holes (variables that don't exist, functions that aren't defined) tends to make things worse, not better. Skipping is the safe choice.

When the gate passes, each rule gets the AST and walks it looking for specific shapes. For example, `NoExplicitSumReduce` looks for:

```elixir
Enum.reduce(list, 0, fn x, acc -> acc + x end)
```

and replaces it with:

```elixir
Enum.sum(list)
```

Rules run in priority order (lower number = runs first), and each rule gets the source as modified by all previous rules.

**Compile-output gate.** After each rule's fix runs, the pipeline compiles the result. If the new source doesn't compile (a buggy rule, or a rule whose transformation was correct in isolation but interacts badly with prior fixes), the pipeline **reverts** to the pre-fix source for that rule and continues. The offending rule shows up as `{Rule, :reverted}` in `applied_rules` and a `[warning]` log line names it. This keeps one broken rule from poisoning the rest of the pipeline.

### What you see in the logs

Every step of the fix pipeline is logged at `:debug` level with a `[credence_fix]` prefix. Set your Logger to `:debug` and you'll see exactly what happened:

```
[debug] [credence_fix] syntax fix pipeline: source already parses, skipping
[debug] [credence_fix] starting semantic fix pipeline (max 3 passes, 6 rules)
[debug] [credence_fix] semantic pass 1: compilation OK, 1 warning(s)
[debug] [credence_fix] UnusedVariable: matched diagnostic, running fix...
[debug] [credence_fix] UnusedVariable: source CHANGED:
  L4 - unused = 1
  L4 + _unused = 1
[debug] [credence_fix] semantic done. Applied: [UnusedVariable(1)]
[debug] [credence_fix] starting pattern fix pipeline (76 rules)
[debug] [credence_fix] NoExplicitSumReduce: check found 1 issue(s), running fix...
[debug] [credence_fix] NoExplicitSumReduce: source CHANGED:
  L5 - Enum.reduce(list, 0, fn x, acc -> acc + x end)
  L5 + Enum.sum(list)
[debug] [credence_fix] done. Applied: [NoExplicitSumReduce(1)]
```

Every line-level change is shown in full diff. When something goes wrong, the log tells you which rule fired, what it changed, and where the pipeline stopped.

### The return value

`Credence.fix/2` returns a map with three keys:

```elixir
%{
  code: "...",           # the fixed source string
  issues: [...],         # issues still detected after the fix pipeline ran
  applied_rules: [...]   # {rule_module, issue_count | :reverted} for every rule that fired
}
```

The `issues` list captures whatever `check/2` still flags after the fix pipeline has finished. Now that every Pattern rule auto-fixes the issue it detects, this list is usually empty — but a rule whose fix produced non-compiling output gets reverted by the compile-output gate, leaving the original issue intact for review.

The `applied_rules` list tells you exactly what each phase did. Each entry is `{rule_module, issue_count}` for a successful fix, or `{rule_module, :reverted}` when the compile-output gate reverted a buggy rule. Rules span all three phases — syntax, semantic, and pattern — so you can see the full history of what the pipeline did to your code.

## License

MIT