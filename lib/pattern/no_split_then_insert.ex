defmodule Credence.Pattern.NoSplitThenInsert do
  @moduledoc """
  Detects `Enum.split/2` used to manually insert an element at a position.

  The pattern:

      {left, right} = Enum.split(list, i)
      left ++ [element] ++ right

  or equivalently:

      {left, right} = Enum.split(list, i)
      left ++ [element | right]

  is a verbose reimplementation of `List.insert_at(list, i, element)`.

  ## When NOT flagged

  Legitimate uses of `Enum.split/2` are untouched:

  - The result variables are used for purposes other than reinsertion.
  - More than one element is spliced in (`left ++ [a, b] ++ right`).
  - The two halves are consumed independently (e.g. processed separately
    and the results combined in a different shape).

  ## Auto-fix

  Both statements are collapsed into:

      List.insert_at(list, i, element)

  Only fires when `left` and `right` appear solely in the concatenation
  expression and nowhere else in the surrounding block.
  """

  use Credence.Pattern.Rule
  alias Credence.Issue

  @impl true
  def check(ast, _opts) do
    {_ast, issues} =
      Macro.prewalk(ast, [], fn
        {:__block__, _meta, statements} = node, acc when is_list(statements) ->
          {node, find_issues_in_block(statements) ++ acc}

        node, acc ->
          {node, acc}
      end)

    Enum.reverse(issues)
  end

  @impl true
  def fix_patches(ast, _opts) do
    Credence.RuleHelpers.patches_from_postwalk(ast, fn
      {:__block__, meta, statements} = node when is_list(statements) ->
        case try_fix_block(statements) do
          {:ok, new_statements} ->
            case new_statements do
              [single] -> single
              _ -> {:__block__, meta, new_statements}
            end

          :skip ->
            node
        end

      node ->
        node
    end)
  end

  # ── Issue detection ───────────────────────────────────────────────

  defp find_issues_in_block(statements) do
    statements
    |> Enum.chunk_every(2, 1, :discard)
    |> Enum.flat_map(fn
      [split_stmt, concat_stmt] ->
        case match_split_pattern(split_stmt) do
          {:ok, _list_var, _idx_expr, left_name, right_name} ->
            case match_concat_pattern(concat_stmt, left_name, right_name) do
              {:ok, _element_expr} ->
                line = stmt_line(split_stmt)
                [build_issue(line)]

              :error ->
                []
            end

          :error ->
            []
        end
    end)
  end

  # ── Fix logic ─────────────────────────────────────────────────────

  defp try_fix_block(statements) do
    case statements do
      [split_stmt, concat_stmt | rest] ->
        with {:ok, list_var, idx_expr, left_name, right_name} <-
               match_split_pattern(split_stmt),
             {:ok, element_expr} <-
               match_concat_pattern(concat_stmt, left_name, right_name),
             true <- vars_only_in_concat?(statements, left_name, right_name, split_stmt, concat_stmt) do
          insert_call = build_insert_at_call(list_var, idx_expr, element_expr)
          {:ok, [insert_call | rest]}
        else
          _ -> :skip
        end

      _ ->
        :skip
    end
  end

  # Verifies left/right variables only appear in the concat statement,
  # not in the split statement's RHS or any other statement.
  defp vars_only_in_concat?(statements, left_name, right_name, split_stmt, concat_stmt) do
    Enum.all?(statements, fn stmt ->
      cond do
        stmt == split_stmt ->
          # Only the LHS of the split binds the vars; the RHS must not use them
          not var_in_ast?(split_rhs(split_stmt), left_name) and
            not var_in_ast?(split_rhs(split_stmt), right_name)

        stmt == concat_stmt ->
          true

        true ->
          not var_in_ast?(stmt, left_name) and not var_in_ast?(stmt, right_name)
      end
    end)
  end

  defp split_rhs({:=, _, [_lhs, rhs]}), do: rhs
  defp split_rhs(_), do: nil

  defp var_in_ast?(nil, _name), do: false

  defp var_in_ast?(ast, name) do
    {_, found} =
      Macro.prewalk(ast, false, fn
        _node, true ->
          {nil, true}

        {^name, _, ctx} = node, false when is_atom(ctx) ->
          {node, true}

        node, acc ->
          {node, acc}
      end)

    found
  end

  # ── AST pattern matching ──────────────────────────────────────────

  # Matches: {left, right} = Enum.split(list, i)
  # AST: {:=, _, [{:{}, _, [left_var, right_var]}, enum_split_call]}
  defp match_split_pattern({:=, _meta, [lhs, rhs]}) do
    with {:ok, left_name, right_name} <- extract_tuple_vars(lhs),
         {:ok, list_var, idx_expr} <- extract_enum_split(rhs) do
      {:ok, list_var, idx_expr, left_name, right_name}
    else
      _ -> :error
    end
  end

  defp match_split_pattern(_), do: :error

  # Extracts variable names from a 2-tuple pattern {a, b}.
  # Sourceror wraps as {:__block__, _, [{{:a, _, nil}, {:b, _, nil}}]}
  defp extract_tuple_vars({:__block__, _, [inner]}), do: extract_tuple_vars(inner)

  defp extract_tuple_vars({{left, _, nil}, {right, _, nil}})
       when is_atom(left) and is_atom(right),
       do: {:ok, left, right}

  # Standard AST: {:{}, _, [a, b]}
  defp extract_tuple_vars({:{}, _, [{left, _, nil}, {right, _, nil}]})
       when is_atom(left) and is_atom(right),
       do: {:ok, left, right}

  defp extract_tuple_vars(_), do: :error

  # Matches Enum.split(list, idx) — direct or piped
  defp extract_enum_split(
         {{:., _, [{:__aliases__, _, [:Enum]}, :split]}, _, [list_arg, idx_arg]}
       ) do
    {:ok, list_arg, idx_arg}
  end

  # Piped form: list |> Enum.split(i)
  defp extract_enum_split(
         {:|>, _, [list_arg, {{:., _, [{:__aliases__, _, [:Enum]}, :split]}, _, [idx_arg]}]}
       ) do
    {:ok, list_arg, idx_arg}
  end

  defp extract_enum_split(_), do: :error

  # Matches: left ++ [element] ++ right  or  left ++ [element | right]
  # where left/right are the variable names from the destructuring.
  defp match_concat_pattern(stmt, left_name, right_name) do
    case last_expr(stmt) do
      # left ++ [element] ++ right  (right-associative: a ++ (b ++ c))
      {:++, _, [lhs, {:++, _, [elem_list, rhs]}]} ->
        with {:ok, element} <- extract_single_elem_list(elem_list),
             true <- var_name_is?(lhs, left_name),
             true <- var_name_is?(rhs, right_name) do
          {:ok, element}
        else
          _ -> :error
        end

      # left ++ [element] ++ right  (left-associative: (a ++ b) ++ c)
      {:++, _, [{:++, _, [lhs, elem_list]}, rhs]} ->
        with {:ok, element} <- extract_single_elem_list(elem_list),
             true <- var_name_is?(lhs, left_name),
             true <- var_name_is?(rhs, right_name) do
          {:ok, element}
        else
          _ -> :error
        end

      # left ++ [element | right]
      {:++, _, [lhs, cons_list]} ->
        with {:ok, element, tail_name} <- extract_cons_cell(cons_list),
             true <- var_name_is?(lhs, left_name),
             true <- tail_name == right_name do
          {:ok, element}
        else
          _ -> :error
        end

      _ ->
        :error
    end
  end

  # Extracts the expression from a single-element list: [element]
  # Sourceror wraps as {:__block__, _, [[element]]}
  defp extract_single_elem_list({:__block__, _, [[single]]}), do: {:ok, single}
  # Plain list form
  defp extract_single_elem_list([single]), do: {:ok, single}
  defp extract_single_elem_list(_), do: :error

  # Extracts from [element | var] pattern
  defp extract_cons_list({:__block__, _, [[{:|, _, [element, {tail, _, nil}]}]]})
       when is_atom(tail),
       do: {:ok, element, tail}

  defp extract_cons_list([{:|, _, [element, {tail, _, nil}]}])
       when is_atom(tail),
       do: {:ok, element, tail}

  defp extract_cons_list(_), do: :error

  defp extract_cons_cell(list) when is_list(list), do: extract_cons_list(list)
  defp extract_cons_cell({:__block__, _, [inner]}), do: extract_cons_list(inner)
  defp extract_cons_cell(_), do: :error

  # Gets the last expression from a block or returns the expression itself
  defp last_expr({:__block__, _, exprs}) when is_list(exprs), do: List.last(exprs)
  defp last_expr(expr), do: expr

  # Checks if a variable node has the given name
  defp var_name_is?({name, _, ctx}, target) when is_atom(name) and is_atom(ctx),
    do: name == target

  defp var_name_is?(_, _), do: false

  # ── AST construction ──────────────────────────────────────────────

  defp build_insert_at_call(list_ast, idx_expr, element_expr) do
    {{:., [], [{:__aliases__, [], [:List]}, :insert_at]}, [], [list_ast, idx_expr, element_expr]}
  end

  # ── Helpers ───────────────────────────────────────────────────────

  defp stmt_line({:=, meta, _}), do: Keyword.get(meta, :line)
  defp stmt_line({{:., _, _}, meta, _}), do: Keyword.get(meta, :line)
  defp stmt_line(_), do: nil

  defp build_issue(line) do
    %Issue{
      rule: :no_split_then_insert,
      message:
        "`{left, right} = Enum.split(list, i)` followed by `left ++ [elem] ++ right` " <>
          "is a manual reimplementation of `List.insert_at(list, i, elem)`.",
      meta: %{line: line}
    }
  end
end
