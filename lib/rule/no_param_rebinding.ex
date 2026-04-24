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
        # Match anonymous functions: fn args -> body end
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

  # Extract all variable names from a pattern (parameter list).
  # This handles simple vars, tuple destructuring, list destructuring, etc.
  defp extract_var_names(ast) do
    {_ast, vars} =
      Macro.prewalk(ast, MapSet.new(), fn
        # Skip pinned variables (^var) — these are matches, not bindings
        {:^, _, _} = node, acc ->
          {node, acc}

        {name, _, context} = node, acc when is_atom(name) and is_atom(context) ->
          # Filter out special atoms like :_ and module aliases
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

  # Walk the body looking for `var = ...` where `var` is in our param set.
  # We only look at the top-level body, not nested fn's (those have their own scope).
  defp find_rebindings(body, param_vars, acc) do
    if MapSet.size(param_vars) == 0 do
      acc
    else
      {_ast, issues} =
        Macro.prewalk(body, acc, fn
          # Skip nested fn's — they have their own parameter scope
          {:fn, _, _} = node, issues ->
            # Return node but don't descend (we'll use prewalk's normal recursion
            # but the nested fn will be caught by the outer check/2 prewalk)
            {node, issues}

          # Match: var = expr (where var is a param name being rebound)
          {:=, meta, [{var_name, _, context}, _rhs]} = node, issues
          when is_atom(var_name) and is_atom(context) ->
            if MapSet.member?(param_vars, var_name) do
              issue = %Issue{
                rule: :no_param_rebinding,
                severity: :info,
                message:
                  "Variable `#{var_name}` shadows a parameter from the enclosing `fn`. " <>
                    "Use a distinct name (e.g. `new_#{var_name}`) to avoid confusion.",
                meta: %{line: Keyword.get(meta, :line)}
              }

              {node, [issue | issues]}
            else
              {node, issues}
            end

          # Also match destructuring that rebinds: {a, b} = ... where a or b is a param
          {:=, meta, [pattern, _rhs]} = node, issues ->
            rebound = extract_var_names([pattern])
            overlap = MapSet.intersection(rebound, param_vars)

            if MapSet.size(overlap) > 0 do
              var_name = overlap |> MapSet.to_list() |> hd()

              issue = %Issue{
                rule: :no_param_rebinding,
                severity: :info,
                message:
                  "Variable `#{var_name}` shadows a parameter from the enclosing `fn`. " <>
                    "Use a distinct name (e.g. `new_#{var_name}`) to avoid confusion.",
                meta: %{line: Keyword.get(meta, :line)}
              }

              {node, [issue | issues]}
            else
              {node, issues}
            end

          node, issues ->
            {node, issues}
        end)

      issues
    end
  end
end
