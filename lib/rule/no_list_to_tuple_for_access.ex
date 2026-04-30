defmodule Credence.Rule.NoListToTupleForAccess do
  @moduledoc """
  Performance & style rule: Detects converting a list to a tuple via
  `List.to_tuple/1` and then accessing elements with `elem/2`.

  Tuples are meant for small, fixed-size collections. Copying a
  dynamically-sized list into a tuple just for indexed access defeats the
  purpose and allocates a full copy of the data. Use pattern matching
  (`[a, b | _] = list`) or `Enum.at/2` on the list directly instead.
  For string processing, use `binary_part/3` or binary pattern matching.

  ## Bad

      t = List.to_tuple(graphemes)
      first = elem(t, 0)
      last = elem(t, tuple_size(t) - 1)

  ## Good

      [first | _] = graphemes
      last = List.last(graphemes)

      # Or for indexed access on strings:
      <<first::utf8, _rest::binary>> = string
  """
  @behaviour Credence.Rule
  alias Credence.Issue

  @impl true
  def check(ast, _opts) do
    # Pass 1: collect variables bound to List.to_tuple(...)
    {_ast, tuple_vars} =
      Macro.prewalk(ast, MapSet.new(), fn
        {:=, _, [{var, _, nil}, {{:., _, [{:__aliases__, _, [:List]}, :to_tuple]}, _, _}]} = node,
        acc
        when is_atom(var) ->
          {node, MapSet.put(acc, var)}

        # Piped: list |> List.to_tuple()
        {:=, _,
         [{var, _, nil}, {:|>, _, [_, {{:., _, [{:__aliases__, _, [:List]}, :to_tuple]}, _, _}]}]} =
            node,
        acc
        when is_atom(var) ->
          {node, MapSet.put(acc, var)}

        node, acc ->
          {node, acc}
      end)

    if MapSet.size(tuple_vars) == 0 do
      []
    else
      # Pass 2: find elem(var, ...) where var is in tuple_vars
      {_ast, issues} =
        Macro.prewalk(ast, [], fn
          {:elem, meta, [{var, _, nil}, _idx]} = node, acc when is_atom(var) ->
            if MapSet.member?(tuple_vars, var) do
              {node, [build_issue(var, meta) | acc]}
            else
              {node, acc}
            end

          node, acc ->
            {node, acc}
        end)

      # Report once per variable, not once per elem call
      issues
      |> Enum.reverse()
      |> Enum.uniq_by(fn issue -> issue.message end)
    end
  end

  defp build_issue(var, meta) do
    %Issue{
      rule: :no_list_to_tuple_for_access,
      severity: :warning,
      message:
        "`#{var}` is created with `List.to_tuple/1` and then accessed with `elem/2`. " <>
          "Avoid copying a dynamic list into a tuple for indexed access. " <>
          "Use pattern matching or `Enum.at/2` on the list directly.",
      meta: %{line: Keyword.get(meta, :line)}
    }
  end
end
