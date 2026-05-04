defmodule Credence.Rule.NoParamRebinding do
  @moduledoc """
  Style & correctness rule: Detects rebinding of parameter names inside
  anonymous function (`fn`) bodies.
  When a variable from the parameter destructure is rebound inside the body,
  readers lose track of which binding is "live" at each point. This is a
  common source of subtle bugs, especially in `Enum.reduce` callbacks where
  the accumulator is destructured.

  ## Bad

      Enum.reduce(arr, {0, :queue.new()}, fn x, {count, q} ->
        q = :queue.in(x, q)       # rebinds `q` from the parameter
        count = count + 1          # rebinds `count` from the parameter
        {count, q}
      end)

  ## Good

      Enum.reduce(arr, {0, :queue.new()}, fn x, {count, q} ->
        new_q = :queue.in(x, q)
        new_count = count + 1
        {new_count, new_q}
      end)
  """
  use Credence.Rule
  alias Credence.Issue

  @impl true
  def fixable?, do: true

  @impl true
  def check(ast, _opts) do
    {_ast, issues} =
      Macro.prewalk(ast, [], fn
        {:fn, _meta, clauses} = node, issues when is_list(clauses) ->
          new_issues =
            Enum.reduce(clauses, issues, fn
              {:->, _arrow_meta, [params, body]}, acc ->
                param_vars = extract_var_names(params)
                find_rebindings(body, param_vars, acc)

              _, acc ->
                acc
            end)

          {node, new_issues}

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
      {:fn, meta, clauses} when is_list(clauses) ->
        new_clauses =
          Enum.map(clauses, fn
            {:->, arrow_meta, [params, body]} ->
              param_vars = extract_var_names(params)

              if MapSet.size(param_vars) > 0 do
                new_body = fix_body(body, param_vars)
                {:->, arrow_meta, [params, new_body]}
              else
                {:->, arrow_meta, [params, body]}
              end

            clause ->
              clause
          end)

        {:fn, meta, new_clauses}

      node ->
        node
    end)
    |> Sourceror.to_string()
  end

  defp fix_body(body, param_vars) do
    # Collect every variable name already present so we never generate a
    # rename that collides with an existing name.
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

  # Walk the expression list left-to-right.  When we hit an assignment
  # whose LHS overlaps with yet-unrenamed parameter names we:
  #   1. Pick a fresh name for each overlapping variable.
  #   2. Rename the LHS using the *new* rename map.
  #   3. Keep the RHS using the *old* rename map (it still refers to
  #      the parameter).
  #   4. Apply the new rename map to every subsequent expression.
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

          # RHS sees the OLD rename state (still references the parameter)
          renamed_rhs = deep_rename(rhs, renames)
          # LHS gets the NEW name
          renamed_pattern = deep_rename(pattern, new_renames)
          new_expr = {:=, meta, [renamed_pattern, renamed_rhs]}

          # Everything after this assignment sees the new names
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
    base = :"new_#{var_name}"
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

  # Walks an AST and replaces every occurrence of a variable whose name
  # is a key in `renames` with the corresponding value.
  #
  # IMPORTANT: when it enters a *nested* `fn` it drops any rename that
  # conflicts with that fn's own parameters, so the inner scope is not
  # corrupted.  References to the outer variable that are NOT shadowed
  # by the inner fn's parameters ARE still renamed.
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

  # Variable node  {name, meta, context}
  defp do_deep_rename({name, meta, context}, renames)
       when is_atom(name) and is_atom(context) do
    case Map.get(renames, name) do
      nil -> {name, meta, context}
      new_name -> {new_name, meta, context}
    end
  end

  # Generic AST 3-tuple (call, special form, alias, …)
  defp do_deep_rename({form, meta, args}, renames) when is_list(args) do
    {form, meta, do_deep_rename(args, renames)}
  end

  # 2-tuple (keyword pair or literal pair)
  defp do_deep_rename({left, right}, renames) do
    {do_deep_rename(left, renames), do_deep_rename(right, renames)}
  end

  # Literal (atom, number, string, …)
  defp do_deep_rename(other, _renames), do: other

  # Collect every variable name that appears anywhere in `ast`
  # (used for collision avoidance when generating new names).
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
      rule: :no_param_rebinding,
      message:
        "Variable `#{var_name}` shadows a parameter from the enclosing `fn`. " <>
          "Use a distinct name (e.g. `new_#{var_name}`) to avoid confusion.",
      meta: %{line: Keyword.get(meta, :line)}
    }
  end
end
