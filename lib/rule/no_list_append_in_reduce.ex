defmodule Credence.Rule.NoListAppendInReduce do
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
  use Credence.Rule
  alias Credence.Issue

  @impl true
  def fixable?, do: true

  @impl true
  def check(ast, _opts) do
    {_ast, issues} =
      Macro.prewalk(ast, [], fn
        # 3-arg: Enum.reduce(enum, [], fn ...)
        {{:., _, [{:__aliases__, _, [:Enum]}, :reduce]}, meta, [_enum, [], fun]} = node,
        issues ->
          {node, check_lambda(fun, meta, issues)}

        # 2-arg piped: |> Enum.reduce([], fn ...)
        {{:., _, [{:__aliases__, _, [:Enum]}, :reduce]}, meta, [[], fun]} = node, issues ->
          {node, check_lambda(fun, meta, issues)}

        node, issues ->
          {node, issues}
      end)

    Enum.reverse(issues)
  end

  @impl true
  def fix(source, _opts) do
    source
    |> Sourceror.parse_string!()
    |> Macro.postwalk(fn
      # 3-arg standalone: Enum.reduce(enum, [], fn ...)
      {{:., dot_meta, [{:__aliases__, al_meta, [:Enum]}, :reduce]}, call_meta,
       [enum, initial, fun]} = node ->
        case try_fix_lambda(initial, fun) do
          {:ok, fixed_fun} ->
            fixed_reduce =
              {{:., dot_meta, [{:__aliases__, al_meta, [:Enum]}, :reduce]}, call_meta,
               [enum, initial, fixed_fun]}

            {:|>, [], [fixed_reduce, enum_reverse_call()]}

          :skip ->
            node
        end

      # Pipe: ... |> Enum.reduce([], fn ...) — insert |> Enum.reverse() stage
      {:|>, pipe_meta, [lhs, rhs]} = node ->
        case try_fix_piped_reduce(rhs) do
          {:ok, fixed_rhs} ->
            {:|>, [], [{:|>, pipe_meta, [lhs, fixed_rhs]}, enum_reverse_call()]}

          :skip ->
            node
        end

      node ->
        node
    end)
    |> Sourceror.to_string()
  end

  # ---------------------------------------------------------------------------
  # Check helpers
  # ---------------------------------------------------------------------------

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

  # ---------------------------------------------------------------------------
  # Fix helpers
  # ---------------------------------------------------------------------------

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

  # ---------------------------------------------------------------------------
  # Shared helpers
  # ---------------------------------------------------------------------------

  # Extracts the expression from acc ++ [expr], handling both
  # Code.string_to_quoted ([expr]) and Sourceror ({:__block__, _, [[expr]]})
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

  # Sourceror wraps list literals like [expr] in {:__block__, _, [[expr]]}.
  # Code.string_to_quoted keeps them as plain [expr].
  defp extract_single_elem_list([single]), do: {:ok, single}
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
