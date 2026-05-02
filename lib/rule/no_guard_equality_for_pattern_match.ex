defmodule Credence.Rule.NoGuardEqualityForPatternMatch do
  @moduledoc """
  Readability rule: Detects guard clauses that compare a parameter to a
  literal value with `==` when pattern matching in the function head would
  be clearer and more idiomatic.

  This only flags simple `var == literal` comparisons where `var` is one of
  the function's parameters and `literal` is an integer, atom, or string.

  ## Bad

      defp do_count(n, _a, b) when n == 2, do: b
      def process(action) when action == :stop, do: :halted

  ## Good

      defp do_count(2, _a, b), do: b
      def process(:stop), do: :halted
  """
  @behaviour Credence.Rule
  alias Credence.Issue

  @impl true
  def check(ast, _opts) do
    {_ast, issues} =
      Macro.prewalk(ast, [], fn
        {kind, _meta, [{:when, _, [call, guard]} | _rest]} = node, issues
        when kind in [:def, :defp] ->
          {_name, _, params} = call
          param_names = extract_param_names(params)
          new_issues = find_guard_equalities(guard, param_names, issues)
          {node, new_issues}

        node, issues ->
          {node, issues}
      end)

    Enum.reverse(issues)
  end

  # Extract simple variable names from the parameter list.
  # Handles plain vars like `n`, ignores patterns like `[h | t]` and `{a, b}`.
  defp extract_param_names(params) when is_list(params) do
    for {name, _, context} <- params, is_atom(name), is_atom(context), do: name
  end

  defp extract_param_names(_), do: []

  # Recursively flatten `and`/`or` guards and check each part.
  defp find_guard_equalities(guard, param_names, acc) do
    parts = flatten_guard(guard)

    Enum.reduce(parts, acc, fn
      # var == literal
      {:==, meta, [{var_name, _, nil}, literal]}, acc
      when is_atom(var_name) and (is_integer(literal) or is_atom(literal) or is_binary(literal)) ->
        if var_name in param_names do
          [build_issue(var_name, literal, meta) | acc]
        else
          acc
        end

      # literal == var (reversed)
      {:==, meta, [literal, {var_name, _, nil}]}, acc
      when is_atom(var_name) and (is_integer(literal) or is_atom(literal) or is_binary(literal)) ->
        if var_name in param_names do
          [build_issue(var_name, literal, meta) | acc]
        else
          acc
        end

      _, acc ->
        acc
    end)
  end

  defp flatten_guard({:and, _, [left, right]}), do: flatten_guard(left) ++ flatten_guard(right)
  defp flatten_guard({:or, _, [left, right]}), do: flatten_guard(left) ++ flatten_guard(right)
  defp flatten_guard(other), do: [other]

  defp build_issue(var_name, literal, meta) do
    %Issue{
      rule: :no_guard_equality_for_pattern_match,
      message:
        "Guard `#{var_name} == #{inspect(literal)}` can be replaced by " <>
          "pattern matching `#{inspect(literal)}` directly in the function head.",
      meta: %{line: Keyword.get(meta, :line)}
    }
  end
end
