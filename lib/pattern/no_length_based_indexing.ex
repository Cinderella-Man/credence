defmodule Credence.Pattern.NoLengthBasedIndexing do
  @moduledoc """
  Detects `n = length(list)` followed by `Enum.at(list, n - K)` — a Python
  `list[len(list) - 1]` idiom. Elixir's `Enum.at/2` natively supports
  negative indices, so `Enum.at(list, -1)` is the idiomatic equivalent.

  ## Detection constraints

  Only flags when ALL of:
  - `var = length(list)` or `var = Enum.count(list)` exists
  - `Enum.at(list, var - K)` appears in the same block (K is a positive integer literal)
  - Same list variable in both calls
  - No rebinding of either variable between the two calls

  ## Bad

      n = length(sorted)
      largest = Enum.at(sorted, n - 1)
      second_largest = Enum.at(sorted, n - 2)

  ## Good

      largest = Enum.at(sorted, -1)
      second_largest = Enum.at(sorted, -2)

  ## Auto-fix

  Replaces `Enum.at(list, n - K)` with `Enum.at(list, -K)`. If the length
  variable is only used for indexing, the `n = length(list)` line is removed.
  """

  use Credence.Pattern.Rule
  alias Credence.Issue

  @impl true
  def fixable?, do: true

  # ── Check ─────────────────────────────────────────────────────────

  @impl true
  def check(ast, _opts) do
    {_ast, issues} =
      Macro.prewalk(ast, [], fn
        {:__block__, _meta, statements} = node, acc when is_list(statements) ->
          {node, find_issues(statements) ++ acc}

        node, acc ->
          {node, acc}
      end)

    Enum.reverse(issues)
  end

  # ── Fix ───────────────────────────────────────────────────────────

  @impl true
  def fix(source, _opts) do
    case Sourceror.parse_string(source) do
      {:ok, ast} ->
        if has_fixable_pattern?(ast) do
          ast
          |> Macro.postwalk(&maybe_rewrite_block/1)
          |> Sourceror.to_string()
        else
          source
        end

      {:error, _} ->
        source
    end
  end

  # ── Shared: scanning ──────────────────────────────────────────────

  # Finds length assignments with matching computed Enum.at indices
  # in the same block.
  defp find_length_patterns(statements) do
    statements
    |> Enum.with_index()
    |> Enum.flat_map(fn {stmt, idx} ->
      case scan_length_assignment(stmt) do
        {:ok, length_var, list_var} ->
          safe_end = find_safe_end(statements, length_var, list_var, idx)

          has_computed_at =
            safe_end > idx and
              statements
              |> Enum.slice((idx + 1)..safe_end)
              |> Enum.any?(&has_length_based_enum_at?(&1, list_var, length_var))

          if has_computed_at do
            [%{length_var: length_var, list_var: list_var, index: idx, safe_end: safe_end}]
          else
            []
          end

        :skip ->
          []
      end
    end)
  end

  # Matches: var = length(list_var) or var = Enum.count(list_var)
  defp scan_length_assignment({:=, _, [lhs, rhs]}) do
    with {:ok, var_name} <- plain_variable_name(lhs),
         {:ok, list_var} <- extract_length_call(rhs) do
      {:ok, var_name, list_var}
    else
      _ -> :skip
    end
  end

  defp scan_length_assignment(_), do: :skip

  # length(var)
  defp extract_length_call({:length, _, [arg]}) do
    plain_variable_name(arg)
  end

  # Enum.count(var) — arity 1 only
  defp extract_length_call({{:., _, [mod, func_ref]}, _, [arg]}) do
    if enum_module?(mod) and unwrap_atom(func_ref) == :count do
      plain_variable_name(arg)
    else
      :skip
    end
  end

  defp extract_length_call(_), do: :skip

  # Recursively checks if an AST subtree contains Enum.at(list_var, length_var - K)
  defp has_length_based_enum_at?(ast, list_var, length_var) do
    {_, found} =
      Macro.prewalk(ast, false, fn
        _node, true ->
          {nil, true}

        {{:., _, [mod, func_ref]}, _, [list_arg, idx_arg]} = node, false ->
          found =
            enum_module?(mod) and unwrap_atom(func_ref) == :at and
              match_var?(list_arg, list_var) and
              match?({:ok, _}, extract_length_minus_k(idx_arg, length_var))

          {node, found}

        node, acc ->
          {node, acc}
      end)

    found
  end

  # Matches: length_var - K where K is a positive integer literal
  defp extract_length_minus_k({:-, _, [left, right]}, length_var) do
    k = unwrap_integer(right)

    if match_var?(left, length_var) and is_integer(k) and k > 0 do
      {:ok, k}
    else
      :skip
    end
  end

  defp extract_length_minus_k(_, _), do: :skip

  # Returns the last safe statement index (before any rebinding of
  # either the length variable or the list variable).
  defp find_safe_end(statements, length_var, list_var, after_idx) do
    rebind_idx =
      statements
      |> Enum.with_index()
      |> Enum.find_value(fn {stmt, idx} ->
        if idx > after_idx and
             (rebinds_variable?(stmt, length_var) or rebinds_variable?(stmt, list_var)) do
          idx
        end
      end)

    if rebind_idx, do: rebind_idx - 1, else: length(statements) - 1
  end

  # ── Variable and value helpers ────────────────────────────────────

  defp plain_variable_name({name, _, context})
       when is_atom(name) and is_atom(context) and name != :_,
       do: {:ok, name}

  defp plain_variable_name(_), do: :skip

  defp match_var?({name, _, context}, target)
       when is_atom(name) and is_atom(context),
       do: name == target

  defp match_var?(_, _), do: false

  defp unwrap_integer(n) when is_integer(n), do: n
  defp unwrap_integer({:__block__, _, [n]}) when is_integer(n), do: n
  defp unwrap_integer(_), do: nil

  defp unwrap_atom({:__block__, _, [atom]}) when is_atom(atom), do: atom
  defp unwrap_atom(atom) when is_atom(atom), do: atom
  defp unwrap_atom(_), do: nil

  defp enum_module?({:__aliases__, _, [:Enum]}), do: true
  defp enum_module?({:__aliases__, _, [{:__block__, _, [:Enum]}]}), do: true
  defp enum_module?(_), do: false

  # ── Rebinding detection ──────────────────────────────────────────

  defp rebinds_variable?({:=, _, [lhs, _rhs]}, var_name) do
    ast_binds_name?(lhs, var_name)
  end

  defp rebinds_variable?(_, _), do: false

  defp ast_binds_name?({name, _, context}, target)
       when is_atom(name) and is_atom(context),
       do: name == target

  defp ast_binds_name?({_, _, args}, target) when is_list(args),
    do: Enum.any?(args, &ast_binds_name?(&1, target))

  defp ast_binds_name?(list, target) when is_list(list),
    do: Enum.any?(list, &ast_binds_name?(&1, target))

  defp ast_binds_name?(_, _), do: false

  # Checks if a variable name appears anywhere in an AST subtree.
  defp ast_contains_variable?({name, _, context}, target)
       when is_atom(name) and is_atom(context),
       do: name == target

  defp ast_contains_variable?({_, _, args}, target) when is_list(args),
    do: Enum.any?(args, &ast_contains_variable?(&1, target))

  defp ast_contains_variable?(list, target) when is_list(list),
    do: Enum.any?(list, &ast_contains_variable?(&1, target))

  defp ast_contains_variable?(_, _), do: false

  # ── Check: issue generation ──────────────────────────────────────

  defp find_issues(statements) do
    find_length_patterns(statements)
    |> Enum.map(fn %{length_var: length_var, list_var: list_var, index: idx} ->
      line =
        case Enum.at(statements, idx) do
          {:=, meta, _} -> Keyword.get(meta, :line)
          _ -> nil
        end

      %Issue{
        rule: :no_length_based_indexing,
        message:
          "`#{length_var} = length(#{list_var})` is used to compute indices " <>
            "for `Enum.at/2`. Use negative indices instead: " <>
            "`Enum.at(#{list_var}, -1)` returns the last element.",
        meta: %{line: line}
      }
    end)
  end

  # ── Fix: block rewriting ─────────────────────────────────────────

  defp has_fixable_pattern?(ast) do
    {_, found} =
      Macro.prewalk(ast, false, fn
        _node, true ->
          {nil, true}

        {:__block__, _, statements} = node, false when is_list(statements) ->
          {node, find_length_patterns(statements) != []}

        node, acc ->
          {node, acc}
      end)

    found
  end

  defp maybe_rewrite_block({:__block__, meta, statements} = node)
       when is_list(statements) do
    patterns = find_length_patterns(statements)

    if patterns == [] do
      node
    else
      new_statements = apply_fixes(statements, patterns)
      {:__block__, meta, new_statements}
    end
  end

  defp maybe_rewrite_block(node), do: node

  # Three-phase fix:
  # 1. Replace all n - K → -K in Enum.at calls (no structural changes)
  # 2. Determine which length lines are now unused
  # 3. Remove unused length lines
  defp apply_fixes(statements, patterns) do
    # Phase 1: replace indices
    replaced =
      Enum.reduce(patterns, statements, fn pattern, stmts ->
        replace_indices_in_range(stmts, pattern)
      end)

    # Phase 2: find removable length lines
    removable =
      patterns
      |> Enum.filter(fn %{length_var: length_var, index: idx} ->
        not variable_still_used?(replaced, length_var, idx)
      end)
      |> Enum.map(& &1.index)
      |> MapSet.new()

    # Phase 3: remove dead length lines
    replaced
    |> Enum.with_index()
    |> Enum.flat_map(fn {stmt, i} ->
      if i in removable, do: [], else: [stmt]
    end)
  end

  defp replace_indices_in_range(
         statements,
         %{list_var: list_var, length_var: length_var, index: idx, safe_end: safe_end}
       ) do
    statements
    |> Enum.with_index()
    |> Enum.map(fn {stmt, i} ->
      if i > idx and i <= safe_end do
        replace_length_indices(stmt, list_var, length_var)
      else
        stmt
      end
    end)
  end

  # Walks an AST subtree replacing Enum.at(list, n - K) with Enum.at(list, -K)
  defp replace_length_indices(ast, list_var, length_var) do
    Macro.postwalk(ast, fn
      {{:., _, [mod, func_ref]} = dot, call_meta, [list_arg, idx_arg]} = node ->
        if enum_module?(mod) and unwrap_atom(func_ref) == :at and
             match_var?(list_arg, list_var) do
          case extract_length_minus_k(idx_arg, length_var) do
            {:ok, k} ->
              {dot, call_meta, [list_arg, -k]}

            :skip ->
              node
          end
        else
          node
        end

      node ->
        node
    end)
  end

  # After replacement, checks if the length variable still appears
  # in any statement other than the length assignment itself.
  defp variable_still_used?(statements, var_name, exclude_idx) do
    statements
    |> Enum.with_index()
    |> Enum.any?(fn {stmt, idx} ->
      idx != exclude_idx and ast_contains_variable?(stmt, var_name)
    end)
  end
end
