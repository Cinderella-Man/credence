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

  ## Good

      graphemes
      |> Enum.slice(best_window_start, best_length)

      Enum.slice(list, 5, 10)
  """
  @behaviour Credence.Rule
  alias Credence.Issue

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

        # Continue traversing
        node, issues ->
          {node, issues}
      end)

    Enum.reverse(issues)
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
