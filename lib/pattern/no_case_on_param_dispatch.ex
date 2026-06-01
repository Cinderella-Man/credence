defmodule Credence.Pattern.NoCaseOnParamDispatch do
  @moduledoc """
  Detects a function clause whose body is a `case` that dispatches
  on a tuple of its own parameters. Multi-clause function heads are the
  idiomatic Elixir way to express this.

  ## Bad

      def gcd(x, y) do
        case {x, y} do
          {0, y} -> y
          {x, 0} -> x
          _ -> gcd(y, rem(x, y))
        end
      end

  ## Good

      def gcd(0, y), do: y
      def gcd(x, 0), do: x
      def gcd(x, y), do: gcd(y, rem(x, y))

  ## Scope

  Only flags when:
  - The clause body is a single `case` expression.
  - The `case` subject is a tuple where every element is a bare
    variable that is one of the function's own parameters.
  - The `case` has at least 2 arms.

  Does NOT flag:
  - `case` on expressions that are not the function parameters.
  - `case` on a single parameter (not a tuple).
  - `case` on a tuple that includes non-parameter or computed expressions.

  ## Auto-fix

  None — generating multi-clause function definitions from a `case` is
  too complex for a reliable patch (guards, `@doc`/`@spec` placement,
  catch-all semantics). This is a check-only rule.
  """

  use Credence.Pattern.Rule
  alias Credence.Issue

  @impl true
  def check(ast, _opts) do
    {_ast, issues} =
      Macro.prewalk(ast, [], fn
        # def name(params) when guard do case {params} do ... end end
        {kind, _meta, [{:when, fmeta, [{name, _, params}, _guard]}, body_kw]} = node, acc
        when kind in [:def, :defp] and is_atom(name) and is_list(params) and is_list(body_kw) ->
          {node, maybe_flag(params, body_kw, fmeta, acc)}

        # def name(params) do case {params} do ... end end
        {kind, meta, [{name, _, params}, body_kw]} = node, acc
        when kind in [:def, :defp] and is_atom(name) and is_list(params) and is_list(body_kw) ->
          {node, maybe_flag(params, body_kw, meta, acc)}

        node, acc ->
          {node, acc}
      end)

    Enum.reverse(issues)
  end

  @impl true
  def fix_patches(_ast, _opts), do: []

  defp maybe_flag(params, body_kw, meta, acc) do
    with {:ok, case_meta, subject, case_kw} <- extract_case(body_kw),
         param_names = for({n, _, c} <- params, is_atom(n), is_atom(c), do: n),
         {:ok, var_count} when var_count >= 2 <- all_vars_in_params?(subject, param_names),
         true <- at_least_two_clauses?(case_kw) do
      line = Keyword.get(case_meta, :line) || Keyword.get(meta, :line)
      [build_issue(line) | acc]
    else
      _ -> acc
    end
  end

  # Extract the case expression from the body keyword list.
  defp extract_case(body_kw) when is_list(body_kw) do
    case body_kw do
      [{{:__block__, _, [:do]}, body} | _] -> unwrap_case(body)
      [{:do, body} | _] -> unwrap_case(body)
      _ -> :error
    end
  end

  defp unwrap_case({:__block__, _, [inner]}), do: unwrap_case(inner)

  defp unwrap_case({:case, case_meta, [subject, case_kw]}) when is_list(case_kw) do
    {:ok, case_meta, subject, case_kw}
  end

  defp unwrap_case(_), do: :error

  # Check that the tuple subject consists entirely of bare variables
  # that are all in the given param_names set.
  # Returns {:ok, count} on success, :error if any element is not a variable
  # or not in params.
  defp all_vars_in_params?(subject, param_names) do
    param_set = MapSet.new(param_names)
    vars = extract_all_tuple_vars(subject)

    case vars do
      :error -> :error
      names when is_list(names) ->
        if names != [] and Enum.all?(names, &MapSet.member?(param_set, &1)) do
          {:ok, length(names)}
        else
          :error
        end
    end
  end

  # Extract variable names from a tuple, returning :error if any
  # element is not a bare variable.
  # Handles {:__block__, _, [inner]}, {a, b} (2-tuple), {:{}, _, [a, b, c]} (3+).
  defp extract_all_tuple_vars({:__block__, _, [inner]}), do: extract_all_tuple_vars(inner)

  defp extract_all_tuple_vars({left, right}) do
    case {extract_all_tuple_vars(left), extract_all_tuple_vars(right)} do
      {ls, rs} when is_list(ls) and is_list(rs) -> ls ++ rs
      _ -> :error
    end
  end

  defp extract_all_tuple_vars({:{}, _, elements}) when is_list(elements) do
    results = Enum.map(elements, &extract_all_tuple_vars/1)

    if Enum.all?(results, &is_list/1) do
      List.flatten(results)
    else
      :error
    end
  end

  defp extract_all_tuple_vars({name, _, ctx}) when is_atom(name) and is_atom(ctx), do: [name]
  defp extract_all_tuple_vars(_), do: :error

  # Check if the case has at least 2 clauses.
  defp at_least_two_clauses?(kw) do
    case kw do
      [{{:__block__, _, [:do]}, clauses} | _] when is_list(clauses) ->
        length(clauses) >= 2

      _ ->
        false
    end
  end

  defp build_issue(line) do
    %Issue{
      rule: :no_case_on_param_dispatch,
      message:
        "A `case` dispatching on function parameters should use multi-clause " <>
          "function heads instead.",
      meta: %{line: line}
    }
  end
end
