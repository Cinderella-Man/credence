defmodule Credence.Pattern.NoListAppendInReduce do
  @moduledoc """
  Performance rule: Detects `acc ++ [expr]` as the return value inside
  `Enum.reduce/3` when the initial accumulator is `[]`.

  Appending to a list with `++` is O(n) — it copies the entire left-hand
  list on every iteration, compounding to O(n²). The auto-fix rewrites to
  prepend with `[expr | acc]` and wraps the reduce with `|> Enum.reverse()`,
  which is O(n) total.

  ## Bad

      Enum.reduce(list, [], fn item, acc ->
        acc ++ [item * 2]
      end)

      list |> Enum.reduce([], fn item, acc ->
        acc ++ [process(item)]
      end)

  ## Good

      Enum.reduce(list, [], fn item, acc ->
        [item * 2 | acc]
      end)
      |> Enum.reverse()
  """
  use Credence.Pattern.Rule
  alias Credence.Issue

  @impl true
  def check(ast, _opts) do
    {_ast, issues} =
      Macro.prewalk(ast, [], fn
        # 3-arg: Enum.reduce(enum, [], fn ...)
        {{:., _, [{:__aliases__, _, [:Enum]}, :reduce]}, meta, [_enum, initial, fun]} = node,
        issues ->
          if empty_list?(initial),
            do: {node, check_lambda(fun, meta, issues)},
            else: {node, issues}

        # 2-arg piped: |> Enum.reduce([], fn ...)
        {{:., _, [{:__aliases__, _, [:Enum]}, :reduce]}, meta, [initial, fun]} = node, issues ->
          if empty_list?(initial),
            do: {node, check_lambda(fun, meta, issues)},
            else: {node, issues}

        node, issues ->
          {node, issues}
      end)

    Enum.reverse(issues)
  end

  @impl true
  def fix_patches(ast, _opts) do
    # Fix targets that sit inside a tighter-binding operator (`reduce ++ […]`)
    # must use the CALL form of the reverse wrap, not the pipe form — see
    # `wrap_with_reverse/2`.
    unsafe = unsafe_targets(ast)

    Credence.RuleHelpers.patches_from_postwalk(ast, fn
      # 3-arg standalone: Enum.reduce(enum, [], fn ...)
      {{:., dot_meta, [{:__aliases__, al_meta, [:Enum]}, :reduce]}, call_meta,
       [enum, initial, fun]} = node ->
        case try_fix_lambda(initial, fun) do
          {:ok, fixed_fun} ->
            fixed_reduce =
              {{:., dot_meta, [{:__aliases__, al_meta, [:Enum]}, :reduce]}, call_meta,
               [enum, initial, fixed_fun]}

            wrap_with_reverse(fixed_reduce, MapSet.member?(unsafe, node))

          :skip ->
            node
        end

      # Pipe: ... |> Enum.reduce([], fn ...) — insert the reverse stage
      {:|>, pipe_meta, [lhs, rhs]} = node ->
        case try_fix_piped_reduce(rhs) do
          {:ok, fixed_rhs} ->
            wrap_with_reverse({:|>, pipe_meta, [lhs, fixed_rhs]}, MapSet.member?(unsafe, node))

          :skip ->
            node
        end

      node ->
        node
    end)
  end

  # `target |> Enum.reverse()` mis-associates when `target` is an operand of an
  # operator that binds tighter than `|>` (`reduce |> Enum.reverse() ++ […]`
  # parses as `reduce |> (Enum.reverse() ++ […])`, which won't compile). In that
  # context emit the CALL form `Enum.reverse(target)` instead — a function call
  # binds tighter than every operator, so it is correct everywhere. Elsewhere keep
  # the idiomatic pipe form.
  defp wrap_with_reverse(target, _unsafe_context? = true) do
    {{:., [], [{:__aliases__, [], [:Enum]}, :reverse]}, [], [target]}
  end

  defp wrap_with_reverse(target, _unsafe_context? = false) do
    {:|>, [], [target, enum_reverse_call()]}
  end

  # The set of fix-target nodes (a standalone empty-init `Enum.reduce/3`, or a
  # pipe whose final stage is an empty-init `Enum.reduce/2`) that appear as a
  # direct operand of a binary operator binding tighter than `|>`.
  defp unsafe_targets(ast) do
    {_ast, set} =
      Macro.prewalk(ast, MapSet.new(), fn
        {op, _, [a, b]} = node, acc when is_atom(op) ->
          if tighter_than_pipe?(op),
            do: {node, acc |> mark_if_target(a) |> mark_if_target(b)},
            else: {node, acc}

        node, acc ->
          {node, acc}
      end)

    set
  end

  defp mark_if_target(acc, node) do
    if fix_target?(node), do: MapSet.put(acc, node), else: acc
  end

  defp fix_target?(
         {{:., _, [{:__aliases__, _, [:Enum]}, :reduce]}, _, [_enum, init, _fun]}
       ),
       do: empty_list?(init)

  defp fix_target?(
         {:|>, _, [_lhs, {{:., _, [{:__aliases__, _, [:Enum]}, :reduce]}, _, [init, _fun]}]}
       ),
       do: empty_list?(init)

  defp fix_target?(_), do: false

  # `|>` has precedence 160; an operator binding strictly tighter would swallow a
  # trailing `|> Enum.reverse()`. (Equal-precedence left-associative operators —
  # the pipe/arrow family — chain correctly, so `> 160`, not `>=`.)
  defp tighter_than_pipe?(op) do
    case Code.Identifier.binary_op(op) do
      {_assoc, precedence} -> precedence > 160
      _ -> false
    end
  end

  # Check helpers
  defp check_lambda({:fn, _, [{:->, _, [params, body]}]}, meta, issues)
       when length(params) == 2 do
    acc_var = List.last(params)

    if simple_var?(acc_var) do
      case extract_append_expr(body, acc_var) do
        {:ok, _expr, pp_meta} ->
          line = Keyword.get(pp_meta, :line) || Keyword.get(meta, :line)
          [build_issue(line) | issues]

        :error ->
          issues
      end
    else
      issues
    end
  end

  defp check_lambda(_, _, issues), do: issues
  # Fix helpers
  defp try_fix_lambda(initial, fun) do
    with true <- empty_list?(initial),
         {:ok, fixed_fun} <- fix_lambda_body(fun) do
      {:ok, fixed_fun}
    else
      _ -> :skip
    end
  end

  defp try_fix_piped_reduce(
         {{:., dot_meta, [{:__aliases__, al_meta, [:Enum]}, :reduce]}, call_meta, [initial, fun]}
       ) do
    case try_fix_lambda(initial, fun) do
      {:ok, fixed_fun} ->
        {:ok,
         {{:., dot_meta, [{:__aliases__, al_meta, [:Enum]}, :reduce]}, call_meta,
          [initial, fixed_fun]}}

      :skip ->
        :skip
    end
  end

  defp try_fix_piped_reduce(_), do: :skip

  defp fix_lambda_body({:fn, fn_meta, [{:->, clause_meta, [params, body]}]})
       when length(params) == 2 do
    acc_var = List.last(params)

    if simple_var?(acc_var) do
      case extract_append_expr(body, acc_var) do
        {:ok, expr, _meta} ->
          cons = [{:|, [], [expr, acc_var]}]
          new_body = replace_last_expression(body, cons)
          {:ok, {:fn, fn_meta, [{:->, clause_meta, [params, new_body]}]}}

        :error ->
          :error
      end
    else
      :error
    end
  end

  defp fix_lambda_body(_), do: :error
  # Shared helpers
  # Extracts the expression from `acc ++ [expr]`. Sourceror wraps the
  # `[expr]` list literal in `{:__block__, _, [[expr]]}` for position meta.
  defp extract_append_expr(body, acc_var) do
    last = last_expression(body)

    case last do
      {:++, meta, [lhs, rhs]} ->
        case extract_single_elem_list(rhs) do
          {:ok, single_expr} ->
            if same_var?(lhs, acc_var) and not cons_cell?(single_expr) do
              {:ok, single_expr, meta}
            else
              :error
            end

          :error ->
            :error
        end

      _ ->
        :error
    end
  end

  defp extract_single_elem_list({:__block__, _, [[single]]}), do: {:ok, single}
  defp extract_single_elem_list(_), do: :error

  defp empty_list?([]), do: true
  defp empty_list?({:__block__, _, [[]]}), do: true
  defp empty_list?(_), do: false

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

  defp enum_reverse_call do
    {{:., [], [{:__aliases__, [], [:Enum]}, :reverse]}, [], []}
  end

  defp build_issue(line) do
    %Issue{
      rule: :no_list_append_in_reduce,
      message:
        "`acc ++ [expr]` inside `Enum.reduce` copies the accumulator on every iteration (O(n²)). " <>
          "Use `[expr | acc]` and `Enum.reverse/1` after the reduce.",
      meta: %{line: line}
    }
  end
end
