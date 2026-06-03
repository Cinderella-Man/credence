# Credence

A tool that reads Elixir code written by an AI and fixes the clumsy bits.

Three kinds of checker look at Elixir code. The compiler checks that the code is
spelled right. Credo checks that it *looks* tidy. Credence checks what the code
actually *does* — it finds code that runs fine and passes its tests but is
written in a roundabout way, is slower than it needs to be, or was copied over
from Python or JavaScript habits that don't fit Elixir. Then it rewrites it the
normal Elixir way.

## How it works: three rounds

Credence runs your code through three rounds, one after another. Each round
fixes a different kind of problem:

```
Credence.Syntax    → can the parser even read it?   (fixes the raw text)
Credence.Semantic  → does the compiler accept it?   (fixes compiler warnings)
Credence.Pattern   → is it written the Elixir way?  (~76 deeper rules)
```

**Round 1 — Syntax** fixes code that won't even parse — for example
`n * (n + 1) div 2` (someone translated Python's `//` straight across) becomes
`div(n * (n + 1), 2)`.

**Round 2 — Semantic** collects the warnings the compiler would print and fixes
them: an unused variable gets an `_` in front of it, a call to a function that
doesn't exist gets corrected when we can tell what was meant.

**Round 3 — Pattern** is the big one: ~76 rules that spot clumsy-but-working
code and rewrite it. `Enum.sort |> Enum.reverse` becomes `Enum.sort(:desc)`,
counting things by hand becomes `Enum.frequencies/1`, `acc ++ [x]` becomes
`[x | acc]`.

Each round has its own kind of rule. Credence finds all the rules by itself and
runs them in a set order.

**One firm promise: every Pattern rule fixes what it finds.** There is no
"just warn me" mode. If a problem can only be pointed at but not safely fixed —
because the fix would have to rearrange code in several places, because there's
more than one reasonable fix, or because the fix would change the *type* of
value the code returns — we took that rule out of the program and parked it in
`docs/unfixable_rules/`. That folder's `README.md` lists every parked rule and
why.

## Installation

```elixir
def deps do
[
  {:credence, "~> 0.4.3", only: [:dev, :test], runtime: false}
]
end
```

## Usage

**Analyze** — point out problems without touching the code:

```elixir
%{valid: true, issues: []} = Credence.analyze(code)
```

**Fix** — repair what can be repaired, and report the rest:

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

You can also run just some of the rules:

```elixir
Credence.analyze(code, rules: [
  Credence.Pattern.NoListAppendInRecursion,
  Credence.Pattern.NoSortForTopK,
  Credence.Pattern.NoListFold
])
```

## Writing your own rules

Each round has its own kind of rule.

### Pattern rules

A Pattern rule works on the **AST** — the tree shape a parser turns your code
into, instead of plain text. A Pattern rule has two parts: `check/2` finds the
problems, and the fix is written in **one of two ways** — pick whichever is
simpler for your change.

**Way A — patches (preferred).** Walk the tree, find the spots you want to
change with `Sourceror.get_range/1`, and hand back `%{range, change}` patches.
Only the bytes you point at move; everything around them stays exactly as the
person wrote it.

```elixir
defmodule Credence.Pattern.MyRule do
  use Credence.Pattern.Rule

  @impl true
  def priority, do: 500  # default; lower numbers run first

  @impl true
  def check(ast, _opts) do
    {_ast, issues} =
      Macro.prewalk(ast, [], fn node, issues ->
        # match the node you care about; add a %Credence.Issue{} when it matches
        {node, issues}
      end)
    Enum.reverse(issues)
  end

  @impl true
  def fix_patches(ast, _opts) do
    {_ast, patches} =
      Macro.prewalk(ast, [], fn node, acc ->
        # for each matched node, hand back:
        #   %{range: Sourceror.get_range(node), change: replacement_source}
        {node, acc}
      end)
    Enum.reverse(patches)
  end
end
```

**Way B — rewrite the whole text.** When your change is really about the text
(a search-and-replace, an edit by line), write `fix/2` instead. The built-in
`fix_patches/2` you get from `use Credence.Pattern.Rule` wraps your text change
as one big patch.

```elixir
defmodule Credence.Pattern.MyRule do
  use Credence.Pattern.Rule

  @impl true
  def check(ast, _opts), do: [...]

  @impl true
  def fix(source, _opts) do
    # hand back the changed source string; keeping the layout tidy is on you
    source
  end
end
```

Way A keeps the surrounding layout intact when several rules change the same
file, so it's the better default. Way B is fine for a small, self-contained
rewrite.

### Syntax rules (for code that won't parse)

```elixir
defmodule Credence.Syntax.MyFix do
  use Credence.Syntax.Rule

  @impl true
  def analyze(source), do: []  # hand back [%Issue{}] for problems you spot

  @impl true
  def fix(source), do: source  # hand back the repaired source string
end
```

### Semantic rules (for compiler warnings)

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

## What happens when you call `fix`

When you call `Credence.fix(code)`, your code goes through the three rounds in
order. Each round handles a different kind of problem, and they run in this
order on purpose: the earlier rounds tidy up things that would otherwise confuse
the later ones.

The whole journey:

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
                  │ Pattern  │ → is it the Elixir way? (only if it compiles)
                  └────┬─────┘
                       │
                  fixed source + leftover issues
```

### Round 1: Syntax — fix the raw text

Syntax rules work on the plain text of your code, before Elixir's parser ever
sees it. They only run when `Code.string_to_quoted/1` fails to read the code —
if it already parses, this round is skipped.

This is where we fix things like Python-style `//` division that the AI
translated word-for-word. These rules use text and pattern matching on the
string — no tree involved.

If the syntax rules get the code parsing again, we move on. If it still won't
parse after every syntax rule has tried, the later rounds do the best they can
with what's there.

### Round 2: Semantic — fix compiler warnings

This round compiles the code with `Code.compile_string/2`, wrapped in
`Code.with_diagnostics/1`. That hands us the same warnings and errors you'd see
in your terminal — unused variables, functions that don't exist, and so on.

Each warning is checked against the semantic rules. When a rule knows how to fix
one, it changes the code. For example, the `UnusedVariable` rule turns `count`
into `_count` when nothing ever uses it.

If the code has real compile **errors** (not just warnings), the semantic rules
try to fix those first, then compile again to catch any warnings the errors were
hiding. This try-again loop runs up to three times.

### Round 3: Pattern — fix clumsy-but-working code

These rules look at the parsed tree for code that compiles fine and passes its
tests but isn't written the Elixir way. Think of it as a picky code reviewer who
knows the mistakes AIs tend to make.

**The compile check first.** Before any Pattern rule runs, Credence compiles the
code one more time to make sure it actually works. If it doesn't — say there's a
variable that was never set and no semantic rule could fix it — the Pattern
rules are skipped. This is on purpose. Pattern rules rewrite code based on its
tree shape, and rewriting code that's already broken tends to make things worse,
not better. Skipping is the safe choice.

When that check passes, each rule gets the tree and walks it looking for a
particular shape. For example, `NoExplicitSumReduce` looks for:

```elixir
Enum.reduce(list, 0, fn x, acc -> acc + x end)
```

and replaces it with:

```elixir
Enum.sum(list)
```

Rules run in order (lower priority number runs first), and each rule sees the
code as the rules before it left it.

**The after-the-fix check.** After each rule makes its change, Credence compiles
the result. If the new code doesn't compile — a buggy rule, or a rule whose
change was fine on its own but clashed with an earlier one — Credence **undoes**
that rule's change and keeps going. The undone rule shows up as `{Rule,
:reverted}` in `applied_rules`, and a `[warning]` line in the log names it. This
keeps one broken rule from wrecking everything after it.

### What you see in the logs

Every step of the fix is written to the log at `:debug` level with a
`[credence_fix]` tag. Turn your Logger up to `:debug` and you'll see exactly
what happened:

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

Every line that changed is shown as a before/after. When something goes wrong,
the log tells you which rule ran, what it changed, and where Credence stopped.

### What you get back

`Credence.fix/2` hands back a map with three keys:

```elixir
%{
  code: "...",           # the fixed source string
  issues: [...],         # problems still found after all the fixing
  applied_rules: [...]   # {rule_module, issue_count | :reverted} for every rule that ran
}
```

`issues` is whatever `check/2` still flags after all the fixing is done. Since
every Pattern rule fixes what it finds, this list is usually empty — but if a
rule's fix produced code that wouldn't compile, the after-the-fix check undoes
it, and that original problem stays on the list for you to look at.

`applied_rules` tells you exactly what each round did. Each entry is
`{rule_module, issue_count}` when a fix worked, or `{rule_module, :reverted}`
when the after-the-fix check had to undo a buggy rule. The list covers all three
rounds — syntax, semantic, and pattern — so you can see the full story of what
happened to your code.

## License

MIT
