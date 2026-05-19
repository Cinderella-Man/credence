defmodule Credence.Pattern.NoMapKeysOrValuesForRawIteration do
  @moduledoc """
  Detects `Map.values(map)` or `Map.keys(map)` passed directly into `Enum`
  functions that return complex structures and **cannot** be safely auto-fixed.

  These functions yield `{key, value}` tuples when iterating a map directly,
  fundamentally changing the return type:

  - `chunk_every`, `chunk`, `chunk_by`, `chunk_while` — nested lists
  - `zip`, `unzip`, `zip_reduce`, `zip_with` — multi-collection tuples
  - `split`, `split_while`, `split_with` — tuple of two lists
  - `with_index` — `{element, index}` tuples
  - `min_max`, `min_max_by` — tuple of two elements
  - `scan`, `flat_map_reduce`, `map_reduce` — accumulator semantics
  - `map_every`, `intersperse` — mixed result types
  - `tally` — no `tally_by` equivalent
  - `member?`, `find_index` — need element identity
  - `fetch`, `fetch!` — ok/error tuple returns
  - `into` — depends on target collectable
  - `group_by/2` (without value function) — result values are tuples

  ## Bad
      Enum.chunk_every(Map.values(m), 2)
      Enum.zip(Map.keys(m), other_list)
      Enum.with_index(Map.values(m))
  """

  use Credence.Pattern.Rule
  alias Credence.Issue

  @map_funcs [:keys, :values]

  @not_fixable ~w(
    chunk_every chunk chunk_by chunk_while
    zip unzip zip_reduce zip_with
    split split_while split_with
    with_index
    min_max min_max_by
    scan flat_map_reduce map_reduce
    map_every intersperse
    tally
    member? find_index
    fetch fetch!
    reverse_slice slide
    into
  )a

  @impl true
  def fixable?, do: false

  @impl true
  def check(ast, _opts) do
    {_ast, issues} =
      Macro.prewalk(ast, [], fn
        # Nested: Enum.func(Map.keys/values(m), ...)
        {{:., _, [{:__aliases__, _, [:Enum]}, efunc]}, meta,
         [{{:., _, [{:__aliases__, _, [:Map]}, mfunc]}, _, _} | rest]} = node,
        issues
        when mfunc in @map_funcs ->
          if bad?(efunc, rest),
            do: {node, [issue(mfunc, efunc, meta) | issues]},
            else: {node, issues}

        # Piped: Map.keys/values(m) |> Enum.func(...)
        {:|>, meta,
         [
           {{:., _, [{:__aliases__, _, [:Map]}, mfunc]}, _, _},
           {{:., _, [{:__aliases__, _, [:Enum]}, efunc]}, _, rest}
         ]} = node,
        issues
        when mfunc in @map_funcs ->
          if bad?(efunc, rest),
            do: {node, [issue(mfunc, efunc, meta) | issues]},
            else: {node, issues}

        # Triple pipe: map |> Map.keys/values() |> Enum.func(...)
        {:|>, meta,
         [
           {:|>, _, [_, {{:., _, [{:__aliases__, _, [:Map]}, mfunc]}, _, _}]},
           {{:., _, [{:__aliases__, _, [:Enum]}, efunc]}, _, rest}
         ]} = node,
        issues
        when mfunc in @map_funcs ->
          if bad?(efunc, rest),
            do: {node, [issue(mfunc, efunc, meta) | issues]},
            else: {node, issues}

        node, issues ->
          {node, issues}
      end)

    Enum.reverse(issues)
  end

  defp bad?(f, rest) do
    f in @not_fixable or (f == :group_by and length(rest) < 2)
  end

  defp issue(mf, ef, meta) do
    %Issue{
      rule: :no_map_keys_or_values_for_raw_iteration,
      message:
        "`Map.#{mf}/1` creates an intermediate list before passing to `Enum.#{ef}`. " <>
          "Iterate the map directly — `Enum` functions accept maps and yield `{key, value}` pairs.",
      meta: %{line: Keyword.get(meta, :line)}
    }
  end
end
