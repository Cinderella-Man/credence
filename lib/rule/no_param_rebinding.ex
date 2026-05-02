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
  @behaviour Credence.Rule
  alias Credence.Issue

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
