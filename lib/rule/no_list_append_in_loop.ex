defmodule Credence.Rule.NoListAppendInLoop do
  @moduledoc """
  Performance rule: Detects the use of `++` inside looping constructs
  that cannot be auto-fixed.

  Appending to a list with `++` is O(n) because it must copy the entire
  left-hand list. Inside a loop or recursion this compounds to O(n²).
  Prefer prepending with `[item | acc]` and calling `Enum.reverse/1`
  after the loop completes.

  Note: simple `acc ++ [expr]` patterns inside `Enum.reduce` with `[]`
  initial are handled by `ListAppendInReduce`, and direct `acc ++ [expr]`
  in recursive tail calls (with a matching base case) are handled by
  `ListAppendInRecursion`. This rule covers the remaining unfixable cases:
  `for` comprehensions, indirect appends in recursion, and complex reduce
  patterns.

  ## Bad — inside a for comprehension

      for item <- list do
        acc = []
        acc ++ [item]
      end

  ## Bad — indirect append in recursion (assigned to variable first)

      defp slide([next | rest], window, current, max) do
        new_window = window ++ [next]
        slide(rest, new_window, current, max)
      end

  ## Good

      Enum.reduce(list, [], fn item, acc ->
        [item * 2 | acc]
      end)
      |> Enum.reverse()
  """
  use Credence.Rule
  alias Credence.Issue

  @impl true
  def check(ast, _opts) do
    {_ast, issues} =
      Macro.prewalk(ast, [], fn
        # Enum.reduce/3 — skip if fixable by ListAppendInReduce
        {{:., _, [{:__aliases__, _, [:Enum]}, :reduce]}, _, [_enumerable, acc_init, fun]} = node,
        issues ->
          if acc_init == [] and fixable_reduce_lambda?(fun) do
            {node, issues}
          else
            {node, find_append(fun, issues)}
          end

        # for comprehensions
        {:for, _, args} = node, issues when is_list(args) ->
          do_block = Keyword.get(List.last(args) || [], :do)
          {node, find_append(do_block, issues)}

        # def/defp with guard — skip if fixable by ListAppendInRecursion
        {kind, _, [{:when, _, [{name, _, params}, _guard]}, body_kw]} = node, issues
        when kind in [:def, :defp] and is_atom(name) and is_list(params) ->
          body = extract_body(body_kw)
          {node, check_recursive(body, name, params, issues)}

        # def/defp without guard
        {kind, _, [{name, _, params}, body_kw]} = node, issues
        when kind in [:def, :defp] and is_atom(name) and is_list(params) ->
          body = extract_body(body_kw)
          {node, check_recursive(body, name, params, issues)}

        node, issues ->
          {node, issues}
      end)

    Enum.reverse(issues)
  end

  # Only flag ++ in recursive functions when the pattern is NOT the simple
  # fixable one (acc ++ [expr] directly in the recursive call args).
  defp check_recursive(body, name, params, issues) do
    if body_calls_self?(body, name) do
      if direct_append_in_recursive_call?(body, name, params) do
        # Fixable by ListAppendInRecursion — skip
        issues
      else
        find_append(body, issues)
      end
    else
      issues
    end
  end

  # Checks if the last expression is name(..., acc ++ [expr], ...)
  # where acc matches a parameter.
  defp direct_append_in_recursive_call?(body, name, params) do
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

  # --- Reduce fixability check (same as ListAppendInReduce) ---

  defp fixable_reduce_lambda?({:fn, _, [{:->, _, [params, body]}]}) when length(params) == 2 do
    acc_var = List.last(params)

    if simple_var?(acc_var) do
      last = last_expression(body)

      case last do
        {:++, _, [lhs, [single]]} ->
          same_var?(lhs, acc_var) and not cons_cell?(single)

        _ ->
          false
      end
    else
      false
    end
  end

  defp fixable_reduce_lambda?(_), do: false

  # --- Shared helpers ---

  defp find_append(ast, acc) do
    {_ast, issues} =
      Macro.prewalk(ast, acc, fn
        {:++, meta, _args} = node, issues ->
          {node, [build_issue(meta) | issues]}

        node, issues ->
          {node, issues}
      end)

    issues
  end

  defp body_calls_self?(nil, _name), do: false

  defp body_calls_self?(body, name) do
    {_ast, found} =
      Macro.prewalk(body, false, fn
        {^name, _, args} = node, _acc when is_list(args) -> {node, true}
        node, acc -> {node, acc}
      end)

    found
  end

  defp extract_body(body_kw) when is_list(body_kw), do: Keyword.get(body_kw, :do)
  defp extract_body(body), do: body

  defp last_expression({:__block__, _, exprs}) when is_list(exprs), do: List.last(exprs)
  defp last_expression(expr), do: expr

  defp simple_var?({name, _, ctx}) when is_atom(name) and (is_nil(ctx) or is_atom(ctx)), do: true
  defp simple_var?(_), do: false

  defp same_var?({name, _, _}, {name, _, _}) when is_atom(name), do: true
  defp same_var?(_, _), do: false

  defp cons_cell?({:|, _, _}), do: true
  defp cons_cell?(_), do: false

  defp build_issue(meta) do
    %Issue{
      rule: :no_list_append_in_loop,
      message:
        "Avoid using '++' inside loops or recursive functions. Prefer prepending with '[item | acc]' and calling 'Enum.reverse/1' outside the loop.",
      meta: %{line: Keyword.get(meta, :line)}
    }
  end
end
