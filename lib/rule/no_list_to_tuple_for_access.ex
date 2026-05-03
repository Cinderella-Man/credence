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

  use Credence.Rule
  alias Credence.Issue

  @impl true
  def fixable?, do: true

  @impl true
  def check(ast, _opts) do
    # Pass 1: collect variables bound to List.to_tuple(...)
    {_ast, tuple_vars} =
      Macro.prewalk(ast, MapSet.new(), fn
        {:=, _, [{var, _, nil}, rhs]} = node, acc when is_atom(var) ->
          if tuple_source?(rhs), do: {node, MapSet.put(acc, var)}, else: {node, acc}

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

  @impl true
  def fix(source, _opts) do
    ast = Sourceror.parse_string!(source)

    # Phase 1: collect bindings  var = List.to_tuple(source_expr)
    # Store the source expression as a string for use in patches.
    {_ast, bindings} =
      Macro.prewalk(ast, %{}, fn
        {:=, _, [{var, _, nil}, rhs]} = node, acc when is_atom(var) ->
          case extract_tuple_source(rhs) do
            {:ok, source_expr} ->
              {node, Map.put(acc, var, Macro.to_string(source_expr))}

            :error ->
              {node, acc}
          end

        node, acc ->
          {node, acc}
      end)

    if map_size(bindings) == 0 do
      source
    else
      # Phase 2: collect patches for elem(var, idx) → Enum.at(source, idx)
      #
      # We use Sourceror.patch_string/2 to do source-level text replacement
      # based on AST range information.  This avoids Macro.to_string/1 which
      # reformats dot-calls inside `def` blocks as multi-line regardless of
      # length.
      {_ast, patches} =
        Macro.prewalk(ast, [], fn
          {:elem, _meta, [{var, _, nil}, idx]} = node, acc when is_atom(var) ->
            case Map.get(bindings, var) do
              nil ->
                {node, acc}

              source_str ->
                range = Sourceror.get_range(node)
                idx_str = Macro.to_string(idx)
                new_code = "Enum.at(#{source_str}, #{idx_str})"
                {node, [%{range: range, change: new_code} | acc]}
            end

          node, acc ->
            {node, acc}
        end)

      source
      |> Sourceror.patch_string(patches)
      |> String.trim_trailing("\n")
    end
  end

  defp tuple_source?({{:., _, [{:__aliases__, _, [:List]}, :to_tuple]}, _, args})
       when is_list(args),
       do: true

  defp tuple_source?({:|>, _, [_, {{:., _, [{:__aliases__, _, [:List]}, :to_tuple]}, _, _}]}),
    do: true

  defp tuple_source?(_), do: false

  defp extract_tuple_source({{:., _, [{:__aliases__, _, [:List]}, :to_tuple]}, _, [source]}),
    do: {:ok, source}

  defp extract_tuple_source(
         {:|>, _, [source, {{:., _, [{:__aliases__, _, [:List]}, :to_tuple]}, _, _}]}
       ),
       do: {:ok, source}

  defp extract_tuple_source(_), do: :error

  defp build_issue(var, meta) do
    %Issue{
      rule: :no_list_to_tuple_for_access,
      message:
        "`#{var}` is created with `List.to_tuple/1` and then accessed with `elem/2`. " <>
          "Avoid copying a dynamic list into a tuple for indexed access. " <>
          "Use pattern matching or `Enum.at/2` on the list directly.",
      meta: %{line: Keyword.get(meta, :line)}
    }
  end
end
