defmodule Credence.Pattern.NoListConcatWithRecursiveResult do
  @moduledoc """
  Check-only rule: detects `++` in the return expression of a recursive
  function where one operand is (or is bound to) a recursive call to the
  same function.

  Using `++` to combine a computed list with a recursive result copies the
  left-hand list on every recursion level, creating O(n²) behavior. Use an
  accumulator with `[elem | acc]` and `Enum.reverse/1` in the base case,
  or `Enum.flat_map/2`, instead.

  This rule complements `no_list_append_in_recursion`, which catches
  `acc ++ [expr]` inside the *arguments* of a tail-recursive call. This
  rule catches `list ++ recursive_result()` in the *return* expression.

  ## Bad

      defp substrings(s, len, i) when i >= len, do: []
      defp substrings(s, len, i) do
        current = for j <- 1..(len - i), do: String.slice(s, i, j)
        rest = substrings(s, len, i + 1)
        current ++ rest
      end

  ## Good

      defp substrings(s, len, i, acc \\ [])
      defp substrings(_s, len, i, acc) when i >= len, do: Enum.reverse(acc)
      defp substrings(s, len, i, acc) do
        new = for j <- (len - i)..1//-1, do: String.slice(s, i, j)
        substrings(s, len, i + 1, new ++ acc)
      end
  """
  use Credence.Pattern.Rule
  alias Credence.Issue

  @impl true
  def check(ast, _opts) do
    {_ast, issues} =
      Macro.prewalk(ast, [], fn
        {kind, meta, [{:when, _, [{name, _, params}, _guard]}, body_kw]} = node, issues
        when kind in [:def, :defp] and is_atom(name) and is_list(params) ->
          body = extract_body(body_kw)
          {node, check_clause(body, name, meta, issues)}

        {kind, meta, [{name, _, params}, body_kw]} = node, issues
        when kind in [:def, :defp] and is_atom(name) and is_list(params) ->
          body = extract_body(body_kw)
          {node, check_clause(body, name, meta, issues)}

        node, issues ->
          {node, issues}
      end)

    Enum.reverse(issues)
  end

  @impl true
  def fix_patches(_ast, _opts), do: []

  defp check_clause(body, name, meta, issues) do
    case find_recursive_concat(body, name) do
      {:ok, concat_meta} ->
        line = Keyword.get(concat_meta, :line) || Keyword.get(meta, :line)

        [
          %Issue{
            rule: :no_list_concat_with_recursive_result,
            message:
              "`++` with a recursive call result copies the list on every " <>
                "recursion level (O(n²)). Use an accumulator with `[elem | acc]` " <>
                "and `Enum.reverse/1` in the base case, or `Enum.flat_map/2`.",
            meta: %{line: line}
          }
          | issues
        ]

      :error ->
        issues
    end
  end

  defp find_recursive_concat(body, name) do
    bindings = collect_self_call_bindings(body, name)

    case last_expression(body) do
      {:++, meta, [lhs, rhs]} ->
        if recursive_operand?(lhs, name, bindings) or recursive_operand?(rhs, name, bindings) do
          {:ok, meta}
        else
          :error
        end

      _ ->
        :error
    end
  end

  defp collect_self_call_bindings(body, name) do
    {_, bindings} =
      Macro.prewalk(body, %{}, fn
        {:=, _, [{var_name, _, ctx}, {^name, _, args}]} = node, acc
        when is_atom(var_name) and (is_nil(ctx) or is_atom(ctx)) and is_list(args) ->
          {node, Map.put(acc, var_name, true)}

        node, acc ->
          {node, acc}
      end)

    bindings
  end

  defp recursive_operand?({callee, _, args}, name, _bindings)
      when is_atom(callee) and is_list(args) and callee == name,
      do: true

  defp recursive_operand?({var_name, _, ctx}, _name, bindings)
       when is_atom(var_name) and (is_nil(ctx) or is_atom(ctx)) do
    Map.has_key?(bindings, var_name)
  end

  defp recursive_operand?(_, _, _), do: false

  defp extract_body(body_kw) when is_list(body_kw) do
    Enum.find_value(body_kw, fn
      {{:__block__, _, [:do]}, body} -> body
      _ -> nil
    end)
  end

  defp extract_body(body), do: body

  defp last_expression({:__block__, _, exprs}) when is_list(exprs), do: List.last(exprs)
  defp last_expression(expr), do: expr
end
