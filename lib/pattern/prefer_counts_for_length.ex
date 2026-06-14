defmodule Credence.Pattern.PreferCountsForLength do
  @moduledoc """
  Detects `length(String.codepoints(string))` when a `counts` map from
  `Enum.frequencies/1` on the same codepoints already exists.

  `String.codepoints/1` traverses the string once for `Enum.frequencies/1`
  and a second time for `length/1`. Derive `n` from the existing counts map
  via `Enum.sum(Map.values(counts))` to avoid the redundant traversal.

  ## Bad

      counts = string |> String.codepoints() |> Enum.frequencies()
      n = length(String.codepoints(string))

  ## Good

      counts = string |> String.codepoints() |> Enum.frequencies()
      n = Enum.sum(Map.values(counts))
  """
  use Credence.Pattern.Rule
  alias Credence.Issue
  alias Credence.RuleHelpers

  @impl true
  def check(ast, _opts) do
    # Pass 1: find counts = string |> String.codepoints() |> Enum.frequencies()
    {_ast, counts_vars} =
      Macro.prewalk(ast, MapSet.new(), fn
        {:=, _,
         [
           {counts_var, _, nil},
           {:|>, _,
            [
              {:|>, _, [{string_var, _, nil}, codepoints_call]},
              frequencies_call
            ]}
         ]} = node,
        acc
        when is_atom(counts_var) and is_atom(string_var) ->
          if frequencies_call?(frequencies_call) and codepoints_call?(codepoints_call) do
            {node, MapSet.put(acc, {counts_var, string_var})}
          else
            {node, acc}
          end

        node, acc ->
          {node, acc}
      end)

    if MapSet.size(counts_vars) == 0 do
      []
    else
      # Pass 2: find length(String.codepoints(var)) where var is in counts_vars
      {_ast, issues} =
        Macro.prewalk(ast, [], fn
          {:length, meta,
           [
             {{:., _, [{:__aliases__, _, [:String]}, :codepoints]}, _, [{string_var, _, nil}]}
           ]} = node,
          acc
          when is_atom(string_var) ->
            if Enum.any?(counts_vars, fn {_cv, sv} -> sv == string_var end) do
              issue = %Issue{
                rule: :prefer_counts_for_length,
                message:
                  "Redundant `String.codepoints/1` traversal. " <>
                    "Use `Enum.sum(Map.values(counts))` instead of " <>
                    "`length(String.codepoints(...))` when a frequency map already exists.",
                meta: %{line: Keyword.get(meta, :line)}
              }

              {node, [issue | acc]}
            else
              {node, acc}
            end

          node, acc ->
            {node, acc}
        end)

      Enum.reverse(issues)
    end
  end

  @impl true
  def fix_patches(ast, opts) do
    RuleHelpers.patches_from_ast_transform(ast, Keyword.get(opts, :source, ""), fn ast ->
      transform_ast(ast)
    end)
  end

  defp transform_ast({:__block__, meta, statements}) do
    transformed = Enum.map(statements, &transform_ast/1)
    {:__block__, meta, transform_block(transformed)}
  end

  defp transform_ast([{_, _} | _] = kw) do
    Enum.map(kw, fn {k, v} -> {k, transform_ast(v)} end)
  end

  defp transform_ast(node) when is_tuple(node) do
    node
    |> Tuple.to_list()
    |> Enum.map(&transform_ast/1)
    |> List.to_tuple()
  end

  defp transform_ast(node) when is_list(node) do
    Enum.map(node, &transform_ast/1)
  end

  defp transform_ast(node), do: node

  defp transform_block([]), do: []

  defp transform_block([stmt | rest]) do
    with {:ok, counts_var, string_var} <- extract_counts_assignment(stmt),
         {:ok, length_line, remaining} <- find_length_codepoints(string_var, rest) do
      replacement = build_replacement(length_line, counts_var)
      [stmt, replacement | transform_block(remaining)]
    else
      _ -> [stmt | transform_block(rest)]
    end
  end

  defp extract_counts_assignment(
         {:=, _,
          [
            {counts_var, _, nil},
            {:|>, _,
             [
               {:|>, _, [{string_var, _, nil}, codepoints_call]},
               frequencies_call
             ]}
          ]}
       )
       when is_atom(counts_var) and is_atom(string_var) do
    if frequencies_call?(frequencies_call) and codepoints_call?(codepoints_call) do
      {:ok, counts_var, string_var}
    else
      :error
    end
  end

  defp extract_counts_assignment(_), do: :error

  defp find_length_codepoints(_string_var, []), do: :not_found

  defp find_length_codepoints(string_var, [stmt | rest]) do
    if references_var?(stmt, string_var) do
      case extract_length_codepoints(stmt, string_var) do
        {:ok, _var} ->
          {:ok, stmt, rest}

        :not_found ->
          :not_found
      end
    else
      with {:ok, result, remaining} <- find_length_codepoints(string_var, rest) do
        {:ok, result, [stmt | remaining]}
      end
    end
  end

  defp extract_length_codepoints(
         {:=, _,
          [
            {assign_var, _, nil},
            {:length, _,
             [
               {{:., _, [{:__aliases__, _, [:String]}, :codepoints]}, _, [{string_var, _, nil}]}
             ]}
          ]},
         string_var
       )
       when is_atom(assign_var) and is_atom(string_var) do
    if assign_var != string_var do
      {:ok, assign_var}
    else
      :not_found
    end
  end

  defp extract_length_codepoints(_, _), do: :not_found

  defp build_replacement(original_stmt, counts_var) do
    {:=, meta, [{assign_var, assign_meta, nil}, _length_expr]} = original_stmt

    new_rhs = enum_sum_map_values_call(counts_var)

    {:=, meta, [{assign_var, assign_meta, nil}, new_rhs]}
  end

  defp enum_sum_map_values_call(counts_var) do
    {{:., [], [{:__aliases__, [], [:Enum]}, :sum]}, [],
     [
       {{:., [], [{:__aliases__, [], [:Map]}, :values]}, [], [{counts_var, [], nil}]}
     ]}
  end

  defp references_var?(ast, var_name) do
    {_, found} =
      Macro.prewalk(ast, false, fn
        {^var_name, _, nil} = node, _acc -> {node, true}
        node, acc -> {node, acc}
      end)

    found
  end

  defp codepoints_call?({{:., _, [{:__aliases__, _, [:String]}, :codepoints]}, _, _}), do: true
  defp codepoints_call?(_), do: false

  defp frequencies_call?({{:., _, [{:__aliases__, _, [:Enum]}, :frequencies]}, _, _}), do: true
  defp frequencies_call?(_), do: false
end
