defmodule Credence.Rule.NoListAppendInRecursion do
  @moduledoc """
  Performance rule: Detects `acc ++ [expr]` passed directly in a recursive
  tail call, where a matching base case returns the accumulator.

  The auto-fix rewrites `acc ++ [expr]` to `[expr | acc]` in the recursive
  clause and wraps the base case return with `Enum.reverse/1`.

  ## Bad

      def build([h | t], result) do
        build(t, result ++ [h * 2])
      end

      def build([], result), do: result

  ## Good

      def build([h | t], result) do
        build(t, [h * 2 | result])
      end

      def build([], result), do: Enum.reverse(result)
  """
  use Credence.Rule
  alias Credence.Issue

  @impl true
  def fixable?, do: true

  @impl true
  def check(ast, _opts) do
    {_ast, issues} =
      Macro.prewalk(ast, [], fn
        {kind, meta, [{:when, _, [{name, _, params}, _guard]}, body_kw]} = node, issues
        when kind in [:def, :defp] and is_atom(name) and is_list(params) ->
          body = extract_body(body_kw)
          {node, check_clause(body, name, params, meta, issues)}

        {kind, meta, [{name, _, params}, body_kw]} = node, issues
        when kind in [:def, :defp] and is_atom(name) and is_list(params) ->
          body = extract_body(body_kw)
          {node, check_clause(body, name, params, meta, issues)}

        node, issues ->
          {node, issues}
      end)

    Enum.reverse(issues)
  end

  @impl true
  def fix(source, _opts) do
    ast = Sourceror.parse_string!(source)

    # Pass 1: determine which functions can be fixed
    fixable = analyze_functions(ast)

    if map_size(fixable) == 0 do
      source
    else
      # Pass 2: apply fixes
      ast
      |> Macro.postwalk(&apply_fix(&1, fixable))
      |> Sourceror.to_string()
    end
  end

  # ---------------------------------------------------------------------------
  # Check
  # ---------------------------------------------------------------------------

  defp check_clause(body, name, params, meta, issues) do
    if body_calls_self?(body, name) and direct_append_in_call?(body, name, params) do
      pp_meta = find_append_meta(body, name) || meta
      line = Keyword.get(pp_meta, :line) || Keyword.get(meta, :line)

      [
        %Issue{
          rule: :no_list_append_in_recursion,
          message:
            "`acc ++ [expr]` inside a recursive call copies the accumulator on every " <>
              "iteration (O(n²)). Use `[expr | acc]` and `Enum.reverse/1` in the base case.",
          meta: %{line: line}
        }
        | issues
      ]
    else
      issues
    end
  end

  # ---------------------------------------------------------------------------
  # Fix — Pass 1: analysis
  # ---------------------------------------------------------------------------

  defp analyze_functions(ast) do
    {_ast, by_fn} =
      Macro.prewalk(ast, %{}, fn
        {kind, _, [{:when, _, [{name, _, params}, _guard]}, body_kw]} = node, acc
        when kind in [:def, :defp] and is_atom(name) and is_list(params) ->
          {node, collect_clause(acc, name, params, body_kw)}

        {kind, _, [{name, _, params}, body_kw]} = node, acc
        when kind in [:def, :defp] and is_atom(name) and is_list(params) ->
          {node, collect_clause(acc, name, params, body_kw)}

        node, acc ->
          {node, acc}
      end)

    # Keep only functions with a recursive clause AND a matching base case
    by_fn
    |> Enum.flat_map(fn {key, clauses} ->
      acc_positions =
        clauses
        |> Enum.filter(&(&1.type == :recursive))
        |> Enum.map(& &1.acc_param_idx)
        |> Enum.reject(&is_nil/1)
        |> MapSet.new()

      base_positions =
        clauses
        |> Enum.filter(&(&1.type == :base))
        |> Enum.map(& &1.returns_param_idx)
        |> Enum.reject(&is_nil/1)
        |> MapSet.new()

      common = MapSet.intersection(acc_positions, base_positions)

      case Enum.at(MapSet.to_list(common), 0) do
        nil -> []
        pos -> [{key, pos}]
      end
    end)
    |> Map.new()
  end

  defp collect_clause(acc, name, params, body_kw) do
    body = extract_body(body_kw)
    key = {name, length(params)}
    clause = build_clause_info(name, params, body)
    Map.update(acc, key, [clause], &[clause | &1])
  end

  defp build_clause_info(name, params, body) do
    if body_calls_self?(body, name) do
      idx = find_acc_param_idx(body, name, params)
      %{type: :recursive, acc_param_idx: idx, returns_param_idx: nil}
    else
      idx = find_returned_param_idx(body, params)
      %{type: :base, acc_param_idx: nil, returns_param_idx: idx}
    end
  end

  defp find_acc_param_idx(body, name, params) do
    last = last_expression(body)

    case last do
      {^name, _, args} when is_list(args) ->
        Enum.find_value(args, fn
          {:++, _, [lhs, rhs]} ->
            case extract_single_elem_list(rhs) do
              {:ok, single} ->
                if not cons_cell?(single),
                  do: Enum.find_index(params, &same_var?(&1, lhs))

              :error ->
                nil
            end

          _ ->
            nil
        end)

      _ ->
        nil
    end
  end

  defp find_returned_param_idx(body, params) do
    last = last_expression(body)
    if simple_var?(last), do: Enum.find_index(params, &same_var?(&1, last))
  end

  # ---------------------------------------------------------------------------
  # Fix — Pass 2: apply transforms
  # ---------------------------------------------------------------------------

  defp apply_fix(
         {kind, meta, [{:when, _, [{name, _, params}, _guard]} = when_clause, body_kw]} = node,
         fixable
       )
       when kind in [:def, :defp] and is_atom(name) and is_list(params) do
    case Map.get(fixable, {name, length(params)}) do
      nil -> node
      acc_idx -> do_fix_clause(kind, meta, when_clause, body_kw, name, params, acc_idx)
    end
  end

  defp apply_fix(
         {kind, meta, [{name, _, params} = call, body_kw]} = node,
         fixable
       )
       when kind in [:def, :defp] and is_atom(name) and is_list(params) do
    case Map.get(fixable, {name, length(params)}) do
      nil -> node
      acc_idx -> do_fix_clause(kind, meta, call, body_kw, name, params, acc_idx)
    end
  end

  defp apply_fix(node, _fixable), do: node

  defp do_fix_clause(kind, meta, call_or_when, body_kw, name, params, acc_idx) do
    body = extract_body(body_kw)

    if body_calls_self?(body, name) do
      fix_recursive(kind, meta, call_or_when, body_kw, body, name)
    else
      fix_base(kind, meta, call_or_when, body_kw, body, params, acc_idx)
    end
  end

  # Replace acc ++ [expr] → [expr | acc] in the recursive call args
  defp fix_recursive(kind, meta, call_or_when, body_kw, body, name) do
    last = last_expression(body)

    new_last =
      case last do
        {^name, call_meta, args} when is_list(args) ->
          new_args =
            Enum.map(args, fn
              {:++, _, [acc_var, rhs]} = original ->
                case extract_single_elem_list(rhs) do
                  {:ok, expr} ->
                    if cons_cell?(expr), do: original, else: [{:|, [], [expr, acc_var]}]

                  :error ->
                    original
                end

              arg ->
                arg
            end)

          {name, call_meta, new_args}

        other ->
          other
      end

    new_body = replace_last_expression(body, new_last)
    {kind, meta, [call_or_when, put_body(body_kw, new_body)]}
  end

  # Wrap the base case return with Enum.reverse()
  defp fix_base(kind, meta, call_or_when, body_kw, body, params, acc_idx) do
    last = last_expression(body)
    acc_param = Enum.at(params, acc_idx)

    if acc_param && simple_var?(last) && same_var?(last, acc_param) do
      reverse =
        {{:., [], [{:__aliases__, [], [:Enum]}, :reverse]}, [], [last]}

      new_body = replace_last_expression(body, reverse)
      {kind, meta, [call_or_when, put_body(body_kw, new_body)]}
    else
      {kind, meta, [call_or_when, body_kw]}
    end
  end

  # ---------------------------------------------------------------------------
  # Shared helpers
  # ---------------------------------------------------------------------------

  # Used by check (Code.string_to_quoted AST) — lists are plain [expr]
  defp direct_append_in_call?(body, name, params) do
    last = last_expression(body)

    case last do
      {^name, _, args} when is_list(args) ->
        Enum.any?(args, fn
          {:++, _, [lhs, [single]]} ->
            not cons_cell?(single) and Enum.any?(params, &same_var?(&1, lhs))

          _ ->
            false
        end)

      _ ->
        false
    end
  end

  defp find_append_meta(body, name) do
    last = last_expression(body)

    case last do
      {^name, _, args} when is_list(args) ->
        Enum.find_value(args, fn
          {:++, meta, _} -> meta
          _ -> nil
        end)

      _ ->
        nil
    end
  end

  # Sourceror wraps list literals like [expr] in {:__block__, _, [[expr]]}.
  # Code.string_to_quoted keeps them as plain [expr].
  defp extract_single_elem_list([single]), do: {:ok, single}
  defp extract_single_elem_list({:__block__, _, [[single]]}), do: {:ok, single}
  defp extract_single_elem_list(_), do: :error

  defp body_calls_self?(nil, _), do: false

  defp body_calls_self?(body, name) do
    {_ast, found} =
      Macro.prewalk(body, false, fn
        {^name, _, args} = node, _ when is_list(args) -> {node, true}
        node, acc -> {node, acc}
      end)

    found
  end

  defp extract_body(body_kw) when is_list(body_kw) do
    Enum.find_value(body_kw, fn
      {{:__block__, _, [:do]}, body} -> body
      {:do, body} -> body
      _ -> nil
    end)
  end

  defp extract_body(body), do: body

  defp put_body(body_kw, new_body) when is_list(body_kw) do
    Enum.map(body_kw, fn
      {{:__block__, m, [:do]}, _old} -> {{:__block__, m, [:do]}, new_body}
      {:do, _old} -> {:do, new_body}
      other -> other
    end)
  end

  defp last_expression({:__block__, _, exprs}) when is_list(exprs), do: List.last(exprs)
  defp last_expression(expr), do: expr

  defp replace_last_expression({:__block__, meta, exprs}, new_last) do
    {:__block__, meta, List.replace_at(exprs, -1, new_last)}
  end

  defp replace_last_expression(_single, new_last), do: new_last

  defp simple_var?({name, _, ctx}) when is_atom(name) and (is_nil(ctx) or is_atom(ctx)),
    do: true

  defp simple_var?(_), do: false

  defp same_var?({name, _, _}, {name, _, _}) when is_atom(name), do: true
  defp same_var?(_, _), do: false

  defp cons_cell?({:|, _, _}), do: true
  defp cons_cell?(_), do: false
end
