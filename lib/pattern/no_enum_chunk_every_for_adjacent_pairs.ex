defmodule Credence.Pattern.NoEnumChunkEveryForAdjacentPairs do
  @moduledoc """
  Check-only rule: Detects `Enum.chunk_every(2, 1, :discard)` used to create
  overlapping pairs for processing in a subsequent `Enum.reduce/2,3` or
  `Enum.reduce_while/2,3`.

  Creating a list of 2-element sublists just to destructure `[a, b]` inside
  the reduce callback allocates O(n) intermediate lists. Track the previous
  element in the accumulator instead.

  ## Bad

      list
      |> Enum.chunk_every(2, 1, :discard)
      |> Enum.reduce_while(:init, fn [a, b], acc -> ... end)

  ## Good

      # Track previous element in the accumulator:
      Enum.reduce_while(tl(list), {hd(list), :init}, fn curr, {prev, acc} ->
        ...
        {prev, new_acc}
      end)

      # Or use a helper:
      list
      |> Enum.chunk_every(2, 1, :discard)
      |> Enum.map(fn [a, b] -> a + b end)
  """

  use Credence.Pattern.Rule
  alias Credence.Issue

  @impl true
  def check(ast, _opts) do
    {_ast, issues} =
      Macro.prewalk(ast, [], fn
        # Piped: ... |> chunk_every(2,1,:discard) |> Enum.reduce/reduce_while(...)
        # The outer |> has left=inner_pipe, right=reduce_call
        {:|>, _, [left, reduce_node]} = node, issues ->
          chunk_node = extract_pipe_rightmost(left)

          if chunk_every_adjacent?(chunk_node) and reduce_call?(reduce_node) do
            line = extract_line(chunk_node)
            {node, [issue(line) | issues]}
          else
            {node, issues}
          end

        # Direct: Enum.reduce/reduce_while(chunk_every(...), ...)
        {{:., _, [{:__aliases__, _, [:Enum]}, fun]}, meta, [chunk_node | rest]} = node, issues
        when fun in [:reduce, :reduce_while] and is_list(rest) ->
          if chunk_every_adjacent?(chunk_node) do
            line = Keyword.get(meta, :line) || extract_line(chunk_node)
            {node, [issue(line) | issues]}
          else
            {node, issues}
          end

        node, issues ->
          {node, issues}
      end)

    Enum.reverse(issues)
  end

  @impl true
  def fix_patches(_ast, _opts), do: []

  # --- private ---

  defp chunk_every_adjacent?(
         {{:., _, [{:__aliases__, _, [:Enum]}, :chunk_every]}, _meta, args}
       ) do
    match_chunk_every_args(args)
  end

  defp chunk_every_adjacent?(_), do: false

  # Direct call: Enum.chunk_every(enum, 2, 1, :discard) — 4 args
  defp match_chunk_every_args([_enum, cs, st, discard]) do
    literal_value(cs) == 2 and literal_value(st) == 1 and literal_value(discard) == :discard
  end

  # Piped: list |> Enum.chunk_every(2, 1, :discard) — 3 args (piped value is left of |>)
  defp match_chunk_every_args([cs, st, discard]) do
    literal_value(cs) == 2 and literal_value(st) == 1 and literal_value(discard) == :discard
  end

  defp match_chunk_every_args(_), do: false

  # Sourceror wraps literals in __block__ nodes
  defp literal_value({:__block__, _, [val]}), do: val
  defp literal_value(val) when is_atom(val), do: val
  defp literal_value(val) when is_integer(val), do: val
  defp literal_value(_), do: nil

  defp reduce_call?(
         {{:., _, [{:__aliases__, _, [:Enum]}, fun]}, _meta, _args}
       )
       when fun in [:reduce, :reduce_while],
       do: true

  defp reduce_call?(_), do: false

  # Extract the rightmost call from a pipe chain: a |> b |> c → c
  defp extract_pipe_rightmost({:|>, _, [_left, right]}), do: extract_pipe_rightmost(right)
  defp extract_pipe_rightmost(node), do: node

  defp extract_line({_, meta, _}) when is_list(meta), do: Keyword.get(meta, :line)
  defp extract_line(_), do: nil

  defp issue(line) do
    %Issue{
      rule: :no_enum_chunk_every_for_adjacent_pairs,
      message:
        "`Enum.chunk_every(2, 1, :discard)` creates O(n) intermediate " <>
          "2-element lists just to destructure adjacent pairs in a reduce. " <>
          "Track the previous element in the accumulator instead.",
      meta: %{line: line}
    }
  end
end
