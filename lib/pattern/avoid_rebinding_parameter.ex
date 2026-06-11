defmodule Credence.Pattern.AvoidRebindingParameter do
  @moduledoc """
  Detects rebinding of function parameters by simple assignment inside
  `def`/`defp` bodies.

  Rebinding a function parameter shadows the original parameter, which is
  non-idiomatic and confusing. A distinct variable name clarifies intent
  and prevents accidental misuse of the original value.

  ## Bad

      def compute(n, k) do
        k = min(k, n - k)
        k + 1
      end

  ## Good

      def compute(n, k) do
        k_opt = min(k, n - k)
        k_opt + 1
      end
  """
  use Credence.Pattern.Rule
  alias Credence.Issue

  @impl true
  def check(ast, _opts) do
    {_ast, issues} =
      Macro.prewalk(ast, [], fn
        # Match both `def` and `defp` with a do-block
        {def_form, _meta, [{_fun_name, _fun_meta, params}, kw]} = node, issues
        when def_form in [:def, :defp] and is_list(params) and is_list(kw) ->
          case Credence.RuleHelpers.extract_do_body(kw) do
            {:ok, body} ->
              param_vars = extract_var_names(params)
              new_issues = find_rebindings(body, param_vars, issues)
              {node, new_issues}

            :error ->
              {node, issues}
          end

        node, issues ->
          {node, issues}
      end)

    Enum.reverse(issues)
  end

  @impl true
  def fix_patches(ast, _opts) do
    Credence.RuleHelpers.patches_from_postwalk(ast, fn
      {def_form, meta, [{fun_name, fun_meta, params}, kw]} = node
      when def_form in [:def, :defp] and is_list(params) and is_list(kw) ->
        case Credence.RuleHelpers.extract_do_body(kw) do
          {:ok, body} ->
            param_vars = extract_var_names(params)

            if MapSet.size(param_vars) > 0 do
              new_body = fix_body(body, param_vars)
              new_kw = Credence.RuleHelpers.replace_do_body(kw, new_body)
              {def_form, meta, [{fun_name, fun_meta, params}, new_kw]}
            else
              node
            end

          :error ->
            node
        end

      node ->
        node
    end)
  end

  defp fix_body(body, param_vars) do
    body_vars = extract_all_var_names(body)
    all_taken = MapSet.union(param_vars, body_vars)

    case body do
      {:__block__, meta, exprs} ->
        {new_exprs, _} = process_exprs(exprs, param_vars, %{}, all_taken)
        {:__block__, meta, new_exprs}

      single_expr ->
        {[result], _} = process_exprs([single_expr], param_vars, %{}, all_taken)
        result
    end
  end

  defp process_exprs([], _param_vars, renames, _all_taken), do: {[], renames}

  defp process_exprs([expr | rest], param_vars, renames, all_taken) do
    case expr do
      {:=, meta, [pattern, rhs]} ->
        pattern_vars = extract_var_names([pattern])
        already_renamed = MapSet.new(Map.keys(renames))
        unrenamed_params = MapSet.difference(param_vars, already_renamed)
        overlap = MapSet.intersection(pattern_vars, unrenamed_params)

        if MapSet.size(overlap) > 0 do
          new_renames =
            Enum.reduce(overlap, renames, fn var, acc ->
              new_name = generate_new_name(var, all_taken, acc)
              Map.put(acc, var, new_name)
            end)

          renamed_rhs = deep_rename(rhs, renames)
          renamed_pattern = deep_rename(pattern, new_renames)
          new_expr = {:=, meta, [renamed_pattern, renamed_rhs]}

          renamed_rest = Enum.map(rest, &deep_rename(&1, new_renames))

          {rest_result, final_renames} =
            process_exprs(renamed_rest, param_vars, new_renames, all_taken)

          {[new_expr | rest_result], final_renames}
        else
          renamed_expr = deep_rename(expr, renames)

          {rest_result, final_renames} =
            process_exprs(rest, param_vars, renames, all_taken)

          {[renamed_expr | rest_result], final_renames}
        end

      _ ->
        renamed_expr = deep_rename(expr, renames)

        {rest_result, final_renames} =
          process_exprs(rest, param_vars, renames, all_taken)

        {[renamed_expr | rest_result], final_renames}
    end
  end

  defp generate_new_name(var_name, all_taken, renames) do
    base = :"#{var_name}_opt"
    taken = MapSet.union(all_taken, MapSet.new(Map.values(renames)))
    find_available(base, taken, 1)
  end

  defp find_available(base, taken, n) do
    candidate = if n == 1, do: base, else: :"#{base}_#{n}"

    if MapSet.member?(taken, candidate) do
      find_available(base, taken, n + 1)
    else
      candidate
    end
  end

  defp deep_rename(ast, renames) when map_size(renames) == 0, do: ast
  defp deep_rename(ast, renames), do: do_deep_rename(ast, renames)

  defp do_deep_rename(list, renames) when is_list(list) do
    Enum.map(list, &do_deep_rename(&1, renames))
  end

  # Nested fn — rename its body but NOT its parameters
  defp do_deep_rename({:fn, meta, clauses}, renames) do
    new_clauses =
      Enum.map(clauses, fn
        {:->, arrow_meta, [params, body]} ->
          param_names = extract_var_names(params)
          body_renames = Map.drop(renames, MapSet.to_list(param_names))

          new_body =
            if map_size(body_renames) > 0, do: do_deep_rename(body, body_renames), else: body

          {:->, arrow_meta, [params, new_body]}

        clause ->
          clause
      end)

    {:fn, meta, new_clauses}
  end

  # Nested def/defp — rename its body but NOT its parameters
  defp do_deep_rename({def_form, meta, [{fun_name, fun_meta, params}, kw]}, renames)
       when def_form in [:def, :defp] and is_list(params) and is_list(kw) do
    param_names = extract_var_names(params)
    body_renames = Map.drop(renames, MapSet.to_list(param_names))

    new_kw =
      if map_size(body_renames) > 0 do
        Credence.RuleHelpers.replace_do_body(
          kw,
          do_deep_rename(Credence.RuleHelpers.extract_do_body(kw) |> elem(1), body_renames)
        )
      else
        kw
      end

    {def_form, meta, [{fun_name, fun_meta, params}, new_kw]}
  end

  # Variable node {name, meta, context}
  defp do_deep_rename({name, meta, context}, renames)
       when is_atom(name) and is_atom(context) do
    case Map.get(renames, name) do
      nil -> {name, meta, context}
      new_name -> {new_name, meta, context}
    end
  end

  # Generic AST 3-tuple
  defp do_deep_rename({form, meta, args}, renames) when is_list(args) do
    {form, meta, do_deep_rename(args, renames)}
  end

  # 2-tuple
  defp do_deep_rename({left, right}, renames) do
    {do_deep_rename(left, renames), do_deep_rename(right, renames)}
  end

  # Literal
  defp do_deep_rename(other, _renames), do: other

  defp extract_all_var_names(ast) do
    {_ast, vars} =
      Macro.prewalk(ast, MapSet.new(), fn
        {name, _, context} = node, acc when is_atom(name) and is_atom(context) ->
          {node, MapSet.put(acc, name)}

        node, acc ->
          {node, acc}
      end)

    vars
  end

  defp extract_var_names(ast) do
    {_ast, vars} =
      Macro.prewalk(ast, MapSet.new(), fn
        {:^, _, _} = node, acc ->
          {node, acc}

        {name, _, context} = node, acc when is_atom(name) and is_atom(context) ->
          if name != :_ and not String.starts_with?(Atom.to_string(name), "_") do
            {node, MapSet.put(acc, name)}
          else
            {node, acc}
          end

        node, acc ->
          {node, acc}
      end)

    vars
  end

  defp find_rebindings(body, param_vars, acc) do
    if MapSet.size(param_vars) == 0 do
      acc
    else
      {_ast, issues} =
        Macro.prewalk(body, acc, fn
          # Don't descend into nested fn — it has its own scope
          {:fn, _, _} = node, issues ->
            {node, issues}

          # Don't descend into nested def/defp — it has its own scope
          {def_form, _, _} = node, issues when def_form in [:def, :defp] ->
            {node, issues}

          # Simple rebinding: var = expr
          {:=, meta, [{var_name, _, context}, _rhs]} = node, issues
          when is_atom(var_name) and is_atom(context) ->
            if MapSet.member?(param_vars, var_name) do
              {node, [build_issue(var_name, meta) | issues]}
            else
              {node, issues}
            end

          # Destructuring rebinding: {a, b} = expr where a or b is a param
          {:=, meta, [pattern, _rhs]} = node, issues ->
            rebound = extract_var_names([pattern])
            overlap = MapSet.intersection(rebound, param_vars)

            if MapSet.size(overlap) > 0 do
              var_name = overlap |> MapSet.to_list() |> hd()
              {node, [build_issue(var_name, meta) | issues]}
            else
              {node, issues}
            end

          node, issues ->
            {node, issues}
        end)

      issues
    end
  end

  defp build_issue(var_name, meta) do
    %Issue{
      rule: :avoid_rebinding_parameter,
      message:
        "Variable `#{var_name}` shadows a function parameter. " <>
          "Use a distinct name (e.g. `#{var_name}_opt`) to avoid confusion.",
      meta: %{line: Keyword.get(meta, :line)}
    }
  end
end
