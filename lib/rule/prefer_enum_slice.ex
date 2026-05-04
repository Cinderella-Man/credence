defmodule Credence.Rule.PreferEnumSlice do
  @moduledoc """
  Readability and Intent rule: Flags usage of `Enum.drop/2` followed by `Enum.take/2`.
  Calling `Enum.drop(list, start)` piped into `Enum.take(length)` is a verbose way
  of slicing a collection. It can be confusing to read at a glance. Elixir provides
  `Enum.slice/3`, which explicitly communicates the intent of extracting a sublist
  and handles the operation cleanly.

  ## Bad

      graphemes
      |> Enum.drop(best_window_start)
      |> Enum.take(best_length)

      Enum.take(Enum.drop(list, 5), 10)

      Enum.drop(list, 5) |> Enum.take(10)

  ## Good

      graphemes
      |> Enum.slice(best_window_start, best_length)

      Enum.slice(list, 5, 10)
  """
  use Credence.Rule
  alias Credence.Issue

  @impl true
  def fixable?, do: true

  @impl true
  def check(ast, _opts) do
    {_ast, issues} =
      Macro.prewalk(ast, [], fn
        # Pattern 1: Pipeline matching `... |> Enum.drop(start) |> Enum.take(len)`
        {:|>, _pipe_meta,
         [
           {:|>, _,
            [
              _left_expression,
              {{:., _, [{:__aliases__, _, [:Enum]}, :drop]}, _, [_drop_amount]}
            ]},
           {{:., _, [{:__aliases__, _, [:Enum]}, :take]}, take_meta, [_take_amount]}
         ]} = node,
        issues ->
          {node, [build_issue(take_meta) | issues]}

        # Pattern 2: Nested function matching `Enum.take(Enum.drop(list, start), len)`
        {{:., _, [{:__aliases__, _, [:Enum]}, :take]}, take_meta,
         [
           {{:., _, [{:__aliases__, _, [:Enum]}, :drop]}, _, [_collection, _drop_amount]},
           _take_amount
         ]} = node,
        issues ->
          {node, [build_issue(take_meta) | issues]}

        # Pattern 3: Single pipe matching `Enum.drop(list, start) |> Enum.take(len)`
        {:|>, _pipe_meta,
         [
           {{:., _, [{:__aliases__, _, [:Enum]}, :drop]}, _, [_collection, _drop_amount]},
           {{:., _, [{:__aliases__, _, [:Enum]}, :take]}, take_meta, [_take_amount]}
         ]} = node,
        issues ->
          {node, [build_issue(take_meta) | issues]}

        node, issues ->
          {node, issues}
      end)

    Enum.reverse(issues)
  end

  @impl true
  def fix(source, _opts) do
    source
    |> Sourceror.parse_string!()
    |> Macro.postwalk(fn
      # Pattern 1: Pipeline ... |> Enum.drop(start) |> Enum.take(len) → ... |> Enum.slice(start, len)
      {:|>, pipe_meta,
       [
         {:|>, _inner_meta,
          [
            left,
            {{:., _, [{:__aliases__, _, [:Enum]}, :drop]}, _drop_meta, [drop_amount]}
          ]},
         {{:., _, [{:__aliases__, _, [:Enum]}, :take]}, _take_meta, [take_amount]}
       ]} ->
        {:|>, pipe_meta,
         [
           left,
           {{:., [], [{:__aliases__, [], [:Enum]}, :slice]}, [], [drop_amount, take_amount]}
         ]}

      # Pattern 2: Nested Enum.take(Enum.drop(list, start), len) → Enum.slice(list, start, len)
      {{:., _, [{:__aliases__, _, [:Enum]}, :take]}, _take_meta,
       [
         {{:., _, [{:__aliases__, _, [:Enum]}, :drop]}, _drop_meta, [collection, drop_amount]},
         take_amount
       ]} ->
        {{:., [], [{:__aliases__, [], [:Enum]}, :slice]}, [],
         [collection, drop_amount, take_amount]}

      # Pattern 3: Single pipe Enum.drop(list, start) |> Enum.take(len) → Enum.slice(list, start, len)
      {:|>, _pipe_meta,
       [
         {{:., _, [{:__aliases__, _, [:Enum]}, :drop]}, _drop_meta, [collection, drop_amount]},
         {{:., _, [{:__aliases__, _, [:Enum]}, :take]}, _take_meta, [take_amount]}
       ]} ->
        {{:., [], [{:__aliases__, [], [:Enum]}, :slice]}, [],
         [collection, drop_amount, take_amount]}

      node ->
        node
    end)
    |> Sourceror.to_string()
    |> Code.format_string!()
    |> IO.iodata_to_binary()
  end

  defp build_issue(meta) do
    %Issue{
      rule: :prefer_enum_slice,
      message:
        "Using `Enum.drop/2` followed by `Enum.take/2` is verbose. " <>
          "Use `Enum.slice/3` instead for clearer intent.",
      meta: %{line: Keyword.get(meta, :line)}
    }
  end
end
