defmodule Credence.Pattern.NoEnumSortThenMapValues do
  @moduledoc """
  Replaces `Map.values/1` applied to the result of `Enum.sort/1,2` or
  `Enum.sort_by/2,3` with `Enum.map(fn {_key, value} -> value end)`.

  Every `Enum.*` function returns a **list**, including when its input was a
  map. `Enum.sort/1` over `%{a: 3, b: 1}` gives `[a: 3, b: 1]` — a list of
  `{key, value}` tuples — and `Map.values/1` on a list raises `BadMapError`.
  Executed, not read off the docs:

      Map.values(Enum.sort(%{a: 3, b: 1}))   # ** (BadMapError)
      Map.values(Enum.sort(%{}))             # ** (BadMapError) — every input

  Nothing catches it before runtime: the module compiles with zero diagnostics,
  no error and no warning, and dies the first time the function is called. That
  is why this is a Pattern rule and not a Semantic one — there is no compiler
  message to key on. The failure mode is recorded in
  `docs/17-failure-mode-catalogue.md` with the shape that produced it:
  `payments |> Enum.sort_by(...) |> Map.values()`, written on the belief that
  sorting a map yields a map.

  ## The repair, and why it is this one and not the swap

  There are two readings of `Map.values(Enum.sort(m))` and they are different
  programs:

      m |> Map.values() |> Enum.sort()                    # values sorted BY VALUE
      m |> Enum.sort() |> Enum.map(fn {_k, v} -> v end)   # values in KEY order

  On `%{a: 3, b: 1, c: 2}` the first gives `[1, 2, 3]` and the second `[3, 1, 2]`,
  so the choice is not cosmetic. This rule takes the second, on three grounds:

  1. **It is the minimal repair.** Only the call that cannot typecheck is
     replaced. The author's ordering stage is left exactly as written, so the
     rule never has to decide what they wanted to sort by.
  2. **The swap breaks `sort_by`.** `payments |> Enum.sort_by(&elem(&1, 1).date)`
     hands the mapper a `{key, value}` tuple. Move `Map.values/1` in front of it
     and the same mapper receives a bare value — silently a different function,
     or a crash. There is no rewrite of the sorter that this rule could justify.
  3. **It matches the outside-in reading.** `Enum.sort` came first and
     `Map.values` last, so "the values of the thing I just ordered" is what the
     source says.

  ## Scope

  The `Enum.sort*` call must be the **immediate** argument (`Map.values(sort)`)
  or the **immediate** pipe predecessor (`|> Enum.sort() |> Map.values()`). The
  rejected implementation this rule replaces searched the whole left subtree for
  a `sort_by` and produced a verified false positive on a struct that merely
  contained one (docs/18). An immediate-neighbour match cannot do that.

  Deliberately not covered:

  * **`Map.keys/1`, `Map.get/2`, `Map.fetch/2`, `Map.put/3`** on the same
    result. They raise identically, but only `Map.values/1` has field evidence
    behind it, and `Map.get(Enum.sort(m), :k)` has no repair anyone can defend —
    dropping the sort is a guess.
  * **Every other list-returning `Enum`/`Stream` function.** `Enum.sort*` is
    element-preserving: if the subject was a map, the list elements are exactly
    its `{key, value}` pairs, which is what makes the replacement mapper
    correct. `Enum.map/2` and friends change the element type, so the same
    mapper would be unjustified.
  * **`Enum.into/2`, `Enum.group_by/2,3`, `Enum.frequencies/1`** and the other
    map-returning functions, along with `Enum.at/2`, `Enum.find/2` and
    `Enum.max_by/2`, which return an *element* that is very often a map.
    `foo |> Enum.at(0) |> Map.get(:k)` is ordinary, correct Elixir and appears
    throughout the corpus; matching on `Enum.*` generically would have flagged
    all of it.

  ## Ordering

  No `priority/0` is declared, and that is a decision rather than an omission.
  `NoMapKeysOrValuesForIteration` claims the same node on exactly one input —
  `m |> Enum.sort() |> Map.values() |> Enum.count()` — where it would emit
  `m |> Enum.sort() |> Enum.count()`. Executed on `%{a: 3, b: 1, c: 2}`: both
  outputs return `3`, because counting the pairs and counting the values of a
  map is the same number. For every other consumer its `@fixable_funcs` declines
  (`sum`, `max`, `min`, `sort`, `reverse` all measured), leaving the
  `BadMapError` in place, so this rule is the one that repairs them.

  Under the live rule set both sit at the default 500 and order alphabetically
  by module, which puts this rule first; the cascade then runs
  `NoEnumCountForLength` over the result. docs/20 §1 asks that a non-default
  priority assert something, and "either order is correct" asserts nothing.

  ## Equivalence

  A repair, not a behaviour change: the before-code raises `BadMapError` for
  every input, including `%{}`, so there is no input on which it returns a value
  the rewrite could disagree with.

  ## Bad

      defmodule SortValuesNESTMV do
        def f(m), do: Map.values(Enum.sort(m))
      end

  ## Good

      defmodule SortValuesNESTMV do
        def f(m), do: Enum.map(Enum.sort(m), fn {_key, value} -> value end)
      end
  """
  use Credence.Pattern.Rule

  alias Credence.Issue
  alias Credence.RuleHelpers

  @impl true
  def check(ast, _opts) do
    {_ast, issues} =
      Macro.prewalk(ast, [], fn node, issues ->
        case offending_meta(node) do
          {:ok, meta} -> {node, [build_issue(meta) | issues]}
          :error -> {node, issues}
        end
      end)

    Enum.reverse(issues)
  end

  @impl true
  def fix_patches(ast, _opts) do
    RuleHelpers.patches_from_postwalk(ast, &fix_node/1)
  end

  # ── Matching ───────────────────────────────────────────────────────────────

  # Piped: `... |> Enum.sort() |> Map.values()`. Sourceror does NOT expand
  # pipes, so this is a `:|>` node with `Map.values/0` on the right and the sort
  # as the rightmost stage of the left.
  defp offending_meta({:|>, meta, [lhs, {{:., _, [{:__aliases__, _, [:Map]}, :values]}, _, []}]}) do
    if sort_call?(rightmost(lhs)), do: {:ok, meta}, else: :error
  end

  # Nested: `Map.values(Enum.sort(m))`, and `Map.values(m |> Enum.sort())`.
  defp offending_meta({{:., _, [{:__aliases__, _, [:Map]}, :values]}, meta, [arg]}) do
    if sort_call?(rightmost(arg)), do: {:ok, meta}, else: :error
  end

  defp offending_meta(_node), do: :error

  # Only the LAST stage of a pipeline is the value that actually reaches
  # `Map.values/1`. Anything deeper is a different value entirely — which is the
  # false positive the rejected implementation shipped, by searching the whole
  # left subtree for a `sort_by`. Unwrapping exactly one pipe level is what
  # keeps `%{sorted: Enum.sort_by(s, & &1)} |> Map.values()` clean.
  defp rightmost({:|>, _, [_lhs, rhs]}), do: rhs
  defp rightmost(node), do: node

  # Arities cover both spellings: written out, `Enum.sort/1,2` and
  # `Enum.sort_by/2,3`; as a pipe stage the subject is implicit, so one less.
  defp sort_call?({{:., _, [{:__aliases__, _, [:Enum]}, :sort]}, _, args})
       when length(args) in 0..2,
       do: true

  defp sort_call?({{:., _, [{:__aliases__, _, [:Enum]}, :sort_by]}, _, args})
       when length(args) in 1..3,
       do: true

  defp sort_call?(_node), do: false

  # ── The rewrite ────────────────────────────────────────────────────────────

  defp fix_node(
         {:|>, pipe_meta,
          [lhs, {{:., dot_meta, [{:__aliases__, alias_meta, [:Map]}, :values]}, call_meta, []}]} =
           node
       ) do
    if sort_call?(rightmost(lhs)) do
      {:|>, pipe_meta, [lhs, enum_map(dot_meta, alias_meta, call_meta, [])]}
    else
      node
    end
  end

  defp fix_node(
         {{:., dot_meta, [{:__aliases__, alias_meta, [:Map]}, :values]}, call_meta, [arg]} = node
       ) do
    if sort_call?(rightmost(arg)),
      do: enum_map(dot_meta, alias_meta, call_meta, [arg]),
      else: node
  end

  defp fix_node(node), do: node

  defp enum_map(dot_meta, alias_meta, call_meta, leading_args) do
    {{:., dot_meta, [{:__aliases__, alias_meta, [:Enum]}, :map]}, call_meta,
     leading_args ++ [value_fn()]}
  end

  # Parsed rather than hand-assembled. A hand-built `:fn` node carries no
  # renderer metadata, and docs/17 entry 11 records a rule that emitted output
  # which did not parse for exactly that reason.
  defp value_fn, do: Sourceror.parse_string!("fn {_key, value} -> value end")

  defp build_issue(meta) do
    %Issue{
      rule: :no_enum_sort_then_map_values,
      message:
        "`Enum.sort/1,2` and `Enum.sort_by/2,3` return a list, so `Map.values/1` on the " <>
          "result raises BadMapError on every input. Use " <>
          "`Enum.map(fn {_key, value} -> value end)` to take the values of the sorted pairs.",
      meta: %{line: Keyword.get(meta, :line)}
    }
  end

  # Replaces one plain-Elixir call with another. No DSL family reinterprets
  # `Map.values/1`, `Enum.sort/1` or `Enum.map/2` — none is a comparison,
  # boolean, control-flow or nil form.
  @impl true
  def unsafe_in_dsl, do: []
end
