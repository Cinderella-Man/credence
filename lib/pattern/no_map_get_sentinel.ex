defmodule Credence.Pattern.NoMapGetSentinel do
  @moduledoc """
  Detects `Map.get(map, key, -1)` followed by `var != -1` — a Python
  `dict.get(key, -1)` idiom that leaks into LLM-generated Elixir.

  Idiomatic Elixir uses `nil` as the absence marker (the default for
  `Map.get/2`) and checks with `!= nil` or pattern-matches with
  `Map.fetch/2`.

  ## Detection constraints

  Only flags when ALL of:
  - The default is a **negative integer** literal (-1, -2, -999, etc.)
  - The result variable is compared to that exact sentinel via `==`/`!=`/`===`/`!==`
  - Both are in the same block with no rebinding of the variable between them

  ## Bad

      last_seen = Map.get(char_map, grapheme, -1)
      if last_seen != -1 and last_seen >= start_index do
        last_seen + 1
      else
        start_index
      end

  ## Good

      last_seen = Map.get(char_map, grapheme)
      if last_seen != nil and last_seen >= start_index do
        last_seen + 1
      else
        start_index
      end

  ## Auto-fix

  Drops the sentinel default from `Map.get` and replaces sentinel
  comparisons with `nil`. Does not restructure control flow.
  """

  use Credence.Pattern.Rule
  alias Credence.Issue

  @comparison_ops [:==, :!=, :===, :!==]

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

  # Scans a block's statements for Map.get sentinel assignments
  # that have a matching comparison in scope.
  defp find_sentinel_patterns(statements) do
    statements
    |> Enum.with_index()
    |> Enum.flat_map(fn {stmt, idx} ->
      case scan_map_get_sentinel(stmt) do
        {:ok, var_name, sentinel} ->
          safe_end = find_safe_end(statements, var_name, idx)

          has_comparison =
            safe_end > idx and
              statements
              |> Enum.slice((idx + 1)..safe_end)
              |> Enum.any?(&contains_sentinel_comparison?(&1, var_name, sentinel))

          if has_comparison do
            [%{var_name: var_name, sentinel: sentinel, index: idx, safe_end: safe_end}]
          else
            []
          end

        :skip ->
          []
      end
    end)
  end

  # Matches: var = Map.get(map, key, SENTINEL) where SENTINEL < 0
  defp scan_map_get_sentinel({:=, _, [lhs, rhs]}) do
    with {:ok, var_name} <- plain_variable_name(lhs),
         {:ok, sentinel} <- extract_map_get_sentinel(rhs),
         true <- is_integer(sentinel) and sentinel < 0 do
      {:ok, var_name, sentinel}
    else
      _ -> :skip
    end
  end

  defp scan_map_get_sentinel(_), do: :skip

  # Extracts the sentinel value from a Map.get/3 call.
  defp extract_map_get_sentinel({{:., _, [mod, func_ref]}, _, [_map, _key, sentinel_ast]}) do
    if map_module?(mod) and unwrap_atom(func_ref) == :get do
      case unwrap_integer(sentinel_ast) do
        n when is_integer(n) -> {:ok, n}
        _ -> :skip
      end
    else
      :skip
    end
  end

  defp extract_map_get_sentinel(_), do: :skip

  # Returns the last statement index that is safe to modify
  # (before any rebinding of var_name).
  defp find_safe_end(statements, var_name, after_idx) do
    rebind_idx =
      statements
      |> Enum.with_index()
      |> Enum.find_value(fn {stmt, idx} ->
        if idx > after_idx and rebinds_variable?(stmt, var_name), do: idx
      end)

    if rebind_idx, do: rebind_idx - 1, else: length(statements) - 1
  end

  # Recursively checks if an AST subtree contains a comparison of
  # var_name against the sentinel value.
  defp contains_sentinel_comparison?(ast, var_name, sentinel) do
    {_, found} =
      Macro.prewalk(ast, false, fn
        _node, true ->
          {nil, true}

        {op, _, [left, right]} = node, false when op in @comparison_ops ->
          found =
            (match_var?(left, var_name) and match_value?(right, sentinel)) or
              (match_var?(right, var_name) and match_value?(left, sentinel))

          {node, found}

        node, acc ->
          {node, acc}
      end)

    found
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

  defp match_value?(ast, target) when is_integer(target) do
    unwrap_integer(ast) == target
  end

  # Handles bare integers, __block__-wrapped, and unary-minus forms.
  defp unwrap_integer(n) when is_integer(n), do: n
  defp unwrap_integer({:__block__, _, [n]}) when is_integer(n), do: n
  defp unwrap_integer({:-, _, [n]}) when is_integer(n) and n > 0, do: -n
  defp unwrap_integer({:-, _, [{:__block__, _, [n]}]}) when is_integer(n) and n > 0, do: -n
  defp unwrap_integer(_), do: nil

  defp unwrap_atom({:__block__, _, [atom]}) when is_atom(atom), do: atom
  defp unwrap_atom(atom) when is_atom(atom), do: atom
  defp unwrap_atom(_), do: nil

  defp map_module?({:__aliases__, _, [:Map]}), do: true
  defp map_module?({:__aliases__, _, [{:__block__, _, [:Map]}]}), do: true
  defp map_module?(_), do: false

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

  # ── Check: issue generation ──────────────────────────────────────

  defp find_issues(statements) do
    find_sentinel_patterns(statements)
    |> Enum.map(fn %{var_name: var_name, sentinel: sentinel} = pattern ->
      %Issue{
        rule: :no_map_get_sentinel,
        message:
          "`Map.get` with sentinel default `#{sentinel}` and comparison " <>
            "`#{var_name} != #{sentinel}` is a Python idiom. " <>
            "Use `Map.get/2` (returns `nil`) and compare with `!= nil`.",
        meta: %{line: get_pattern_line(statements, pattern)}
      }
    end)
  end

  defp get_pattern_line(statements, %{index: idx}) do
    case Enum.at(statements, idx) do
      {:=, meta, _} -> Keyword.get(meta, :line)
      _ -> nil
    end
  end

  # ── Fix: block rewriting ─────────────────────────────────────────

  defp has_fixable_pattern?(ast) do
    {_, found} =
      Macro.prewalk(ast, false, fn
        _node, true ->
          {nil, true}

        {:__block__, _, statements} = node, false when is_list(statements) ->
          {node, find_sentinel_patterns(statements) != []}

        node, acc ->
          {node, acc}
      end)

    found
  end

  defp maybe_rewrite_block({:__block__, meta, statements} = node)
       when is_list(statements) do
    patterns = find_sentinel_patterns(statements)

    if patterns == [] do
      node
    else
      new_statements =
        Enum.reduce(patterns, statements, &apply_single_fix/2)

      {:__block__, meta, new_statements}
    end
  end

  defp maybe_rewrite_block(node), do: node

  # Applies a single sentinel fix: drops the Map.get default and
  # replaces comparisons with nil in the safe range.
  defp apply_single_fix(
         %{var_name: var_name, sentinel: sentinel, index: idx, safe_end: safe_end},
         statements
       ) do
    statements
    |> Enum.with_index()
    |> Enum.map(fn {stmt, i} ->
      cond do
        i == idx ->
          drop_map_get_default(stmt)

        i > idx and i <= safe_end ->
          replace_sentinel_in_comparisons(stmt, var_name, sentinel)

        true ->
          stmt
      end
    end)
  end

  # Removes the third argument (sentinel default) from Map.get/3.
  defp drop_map_get_default({:=, eq_meta, [lhs, rhs]}) do
    {:=, eq_meta, [lhs, drop_sentinel_arg(rhs)]}
  end

  defp drop_sentinel_arg(
         {{:., _dot_meta, [mod, func_ref]} = dot, call_meta, [map, key, _sentinel]} = call
       ) do
    if map_module?(mod) and unwrap_atom(func_ref) == :get do
      {dot, call_meta, [map, key]}
    else
      call
    end
  end

  defp drop_sentinel_arg(other), do: other

  # Walks an AST subtree replacing sentinel comparisons with nil.
  defp replace_sentinel_in_comparisons(ast, var_name, sentinel) do
    Macro.postwalk(ast, fn
      {op, meta, [left, right]} = node when op in @comparison_ops ->
        cond do
          match_var?(left, var_name) and match_value?(right, sentinel) ->
            {op, meta, [left, nil]}

          match_var?(right, var_name) and match_value?(left, sentinel) ->
            {op, meta, [nil, right]}

          true ->
            node
        end

      node ->
        node
    end)
  end
end
