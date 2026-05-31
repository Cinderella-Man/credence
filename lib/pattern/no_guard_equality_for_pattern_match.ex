defmodule Credence.Pattern.NoGuardEqualityForPatternMatch do
  @moduledoc """
  Readability rule: Detects guard clauses that compare a parameter to a
  literal value with `==` when pattern matching in the function head would
  be clearer and more idiomatic.

  This only flags simple `var == literal` comparisons where `var` is one of
  the function's parameters and `literal` is an integer, atom, string, or
  the empty list `[]`.

  ## Bad

      defp do_count(n, _a, b) when n == 2, do: b
      def process(action) when action == :stop, do: :halted

  ## Good

      defp do_count(2, _a, b), do: b
      def process(:stop), do: :halted
  """
  use Credence.Pattern.Rule
  alias Credence.Issue

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
  def fix_patches(ast, _opts) do
    {_ast, patches} =
      Macro.prewalk(ast, [], fn
        {kind, _meta, [{:when, _when_meta, [call, guard]} = when_node | rest]} = node, acc
        when kind in [:def, :defp] ->
          {_name, _call_meta, params} = call
          param_names = extract_param_names(params)

          case build_when_patch(when_node, call, guard, rest, param_names) do
            nil -> {node, acc}
            patch -> {node, [patch | acc]}
          end

        node, acc ->
          {node, acc}
      end)

    Enum.reverse(patches)
  end

  # Builds a patch that replaces the `{:when, _, [call, guard]}` node's
  # source range with either the rewritten call (when every guard
  # equality has been substituted into the head) or `call when remaining_guard`
  # (when some guard expressions remain). Body is untouched.
  defp build_when_patch(when_node, call, guard, rest, param_names) do
    if guard_safe_to_fix?(guard) do
      case find_guard_equalities(guard, param_names) do
        [] ->
          nil

        matches ->
          remaining_guard = remove_matched_equalities(guard, param_names)
          matched_vars = MapSet.new(matches, fn {var, _, _} -> var end)

          if references_any?(remaining_guard, matched_vars) or
               body_references_any?(rest, matched_vars) do
            nil
          else
            {_name, _, params} = call
            new_params = apply_fixes_to_params(params, matches)
            new_call = put_elem(call, 2, new_params)

            change =
              case remaining_guard do
                nil -> Macro.to_string(new_call)
                remaining -> "#{Macro.to_string(new_call)} when #{Macro.to_string(remaining)}"
              end

            %{range: Sourceror.get_range(when_node), change: change}
          end
      end
    end
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
      {:==, meta, [{var_name, _, nil}, maybe_literal]}, acc when is_atom(var_name) ->
        case fixable_literal(maybe_literal) do
          {:ok, literal} ->
            if var_name in param_names, do: [{var_name, literal, meta} | acc], else: acc

          :error ->
            acc
        end

      {:==, meta, [maybe_literal, {var_name, _, nil}]}, acc when is_atom(var_name) ->
        case fixable_literal(maybe_literal) do
          {:ok, literal} ->
            if var_name in param_names, do: [{var_name, literal, meta} | acc], else: acc

          :error ->
            acc
        end

      _, acc ->
        acc
    end)
    |> Enum.reverse()
  end

  # Sourceror wraps literals in :__block__ to carry position metadata.
  defp fixable_literal({:__block__, _, [literal]})
       when is_integer(literal) or is_atom(literal) or is_binary(literal),
       do: {:ok, literal}

  # Empty list `[]` is a simple literal suitable for pattern matching.
  defp fixable_literal({:__block__, _, [[]]}), do: {:ok, []}

  defp fixable_literal(_), do: :error

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

  defp remove_from_guard({:==, _meta, [{var_name, _, ctx}, literal]} = node, param_names)
       when is_atom(var_name) and is_atom(ctx) do
    with {:ok, _} <- fixable_literal(literal),
         true <- var_name in param_names do
      nil
    else
      _ -> node
    end
  end

  defp remove_from_guard({:==, _meta, [literal, {var_name, _, ctx}]} = node, param_names)
       when is_atom(var_name) and is_atom(ctx) do
    with {:ok, _} <- fixable_literal(literal),
         true <- var_name in param_names do
      nil
    else
      _ -> node
    end
  end

  defp remove_from_guard(other, _param_names), do: other
end
