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
  use Credence.Rule
  alias Credence.Issue

  @impl true
  def fixable?, do: true

  @impl true
  def check(ast, _opts) do
    {_ast, issues} =
      Macro.prewalk(ast, [], fn
        {_kind, _meta, [{:when, _, _} | _]} = node, issues ->
          case extract_guard_matches(node) do
            [] ->
              {node, issues}

            matches ->
              new_issues = Enum.map(matches, &build_issue/1)
              {node, new_issues ++ issues}
          end

        node, issues ->
          {node, issues}
      end)

    Enum.reverse(issues)
  end

  @impl true
  def fix(source, _opts) do
    {_ok, ast} = Code.string_to_quoted(source)

    ast
    |> Macro.postwalk(fn
      {kind, meta, [{:when, when_meta, [call, guard]} | rest]} = node
      when kind in [:def, :defp] ->
        {_name, _call_meta, params} = call
        param_names = extract_param_names(params)

        case fix_when_clause(kind, meta, when_meta, call, guard, rest, param_names) do
          :unchanged -> node
          fixed -> fixed
        end

      node ->
        node
    end)
    |> Macro.to_string()
  end

  defp extract_guard_matches({kind, _meta, [{:when, _, [call, guard]} | _]})
       when kind in [:def, :defp] do
    {_name, _, params} = call
    param_names = extract_param_names(params)
    find_guard_equalities(guard, param_names)
  end

  defp extract_guard_matches(_), do: []

  defp extract_param_names(params) when is_list(params) do
    for {name, _, context} <- params, is_atom(name), is_atom(context), do: name
  end

  defp extract_param_names(_), do: []

  defp find_guard_equalities(guard, param_names) do
    guard
    |> flatten_guard()
    |> Enum.reduce([], fn
      {:==, meta, [{var_name, _, nil}, literal]}, acc
      when is_atom(var_name) and
             (is_integer(literal) or is_atom(literal) or is_binary(literal)) ->
        if var_name in param_names, do: [{var_name, literal, meta} | acc], else: acc

      {:==, meta, [literal, {var_name, _, nil}]}, acc
      when is_atom(var_name) and
             (is_integer(literal) or is_atom(literal) or is_binary(literal)) ->
        if var_name in param_names, do: [{var_name, literal, meta} | acc], else: acc

      _, acc ->
        acc
    end)
    |> Enum.reverse()
  end

  defp flatten_guard({:and, _, [left, right]}), do: flatten_guard(left) ++ flatten_guard(right)
  defp flatten_guard({:or, _, [left, right]}), do: flatten_guard(left) ++ flatten_guard(right)
  defp flatten_guard(other), do: [other]

  defp build_issue({var_name, literal, meta}) do
    %Issue{
      rule: :no_guard_equality_for_pattern_match,
      message:
        "Guard `#{var_name} == #{inspect(literal)}` can be replaced by " <>
          "pattern matching `#{inspect(literal)}` directly in the function head.",
      meta: %{line: Keyword.get(meta, :line)}
    }
  end

  defp fix_when_clause(kind, meta, when_meta, call, guard, rest, param_names) do
    if guard_safe_to_fix?(guard) do
      matches = find_guard_equalities(guard, param_names)

      case matches do
        [] ->
          :unchanged

        matches ->
          remaining_guard = remove_matched_equalities(guard, param_names)
          matched_vars = MapSet.new(matches, fn {var, _, _} -> var end)

          if references_any?(remaining_guard, matched_vars) or
               body_references_any?(rest, matched_vars) do
            :unchanged
          else
            {_name, _call_meta, params} = call
            new_params = apply_fixes_to_params(params, matches)
            new_call = put_elem(call, 2, new_params)

            case remaining_guard do
              nil ->
                {kind, meta, [new_call | rest]}

              remaining ->
                {kind, meta, [{:when, when_meta, [new_call, remaining]} | rest]}
            end
          end
      end
    else
      :unchanged
    end
  end

  defp references_any?(nil, _var_names), do: false

  defp references_any?(ast, var_names) do
    {_, found} =
      Macro.prewalk(ast, false, fn
        {name, _, ctx} = node, acc when is_atom(name) and is_atom(ctx) ->
          {node, acc or MapSet.member?(var_names, name)}

        node, acc ->
          {node, acc}
      end)

    found
  end

  defp body_references_any?(rest, var_names) when is_list(rest) do
    rest
    |> List.flatten()
    |> Enum.any?(fn
      {_key, body} -> references_any?(body, var_names)
      _ -> false
    end)
  end

  defp body_references_any?(_, _), do: false

  defp guard_safe_to_fix?(guard), do: not guard_has_or?(guard)

  defp guard_has_or?({:or, _, _}), do: true
  defp guard_has_or?({:and, _, [left, right]}), do: guard_has_or?(left) or guard_has_or?(right)
  defp guard_has_or?(_), do: false

  defp apply_fixes_to_params(params, matches) do
    match_map = Map.new(matches, fn {var_name, literal, _meta} -> {var_name, literal} end)

    Enum.map(params, fn
      {name, meta, context} when is_atom(name) and is_atom(context) ->
        case Map.get(match_map, name) do
          nil -> {name, meta, context}
          literal -> literal
        end

      other ->
        other
    end)
  end

  defp remove_matched_equalities(guard, param_names) do
    remove_from_guard(guard, param_names)
  end

  defp remove_from_guard({:and, meta, [left, right]}, param_names) do
    case {remove_from_guard(left, param_names), remove_from_guard(right, param_names)} do
      {nil, nil} -> nil
      {nil, remaining} -> remaining
      {remaining, nil} -> remaining
      {l, r} -> {:and, meta, [l, r]}
    end
  end

  defp remove_from_guard({:==, meta, [{var_name, var_meta, ctx}, literal]}, param_names)
       when is_atom(var_name) and is_atom(ctx) and
              (is_integer(literal) or is_atom(literal) or is_binary(literal)) do
    if var_name in param_names,
      do: nil,
      else: {:==, meta, [{var_name, var_meta, ctx}, literal]}
  end

  defp remove_from_guard({:==, meta, [literal, {var_name, var_meta, ctx}]}, param_names)
       when is_atom(var_name) and is_atom(ctx) and
              (is_integer(literal) or is_atom(literal) or is_binary(literal)) do
    if var_name in param_names,
      do: nil,
      else: {:==, meta, [literal, {var_name, var_meta, ctx}]}
  end

  defp remove_from_guard(other, _param_names), do: other
end
