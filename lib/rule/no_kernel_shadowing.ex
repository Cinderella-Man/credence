defmodule Credence.Rule.NoKernelShadowing do
  @moduledoc """
  Idiomatic rule: warns when variables shadow `Kernel` functions.

  Using `max` or `min` as variable names (e.g., in `Enum.reduce` or function
  arguments) shadows the built-in Kernel functions.

  While `max(max, value)` is valid Elixir, it is considered unidiomatic and
  can lead to confusion or subtle bugs.

  Prefer:
    - `max_val`, `global_max`, or `limit` instead of `max`
    - `min_val`, `local_min`, or `bottom` instead of `min`
  """
  @behaviour Credence.Rule
  alias Credence.Issue

  @shadowed [
    :max,
    :min,
    :elem,
    :hd,
    :tl,
    :length,
    :abs,
    :round,
    :trunc,
    :div,
    :rem,
    :tuple_size,
    :map_size,
    :byte_size,
    :bit_size
  ]

  @impl true
  def check(ast, _opts) do
    {_ast, issues} =
      Macro.prewalk(ast, [], fn
        # Match operator (=)
        {:=, meta, [lhs, _rhs]} = node, issues ->
          new_issues = extract_vars(lhs, meta)
          {node, new_issues ++ issues}

        # Match fn parameters
        {:fn, _meta, clauses} = node, issues ->
          vars =
            clauses
            |> Enum.flat_map(fn {:->, meta, [params, _body]} ->
              extract_vars_from_list(params, meta)
            end)

          {node, vars ++ issues}

        # Match def/defp function arguments
        {def_type, _meta, [{_name, meta, args}, _body]} = node, issues
        when def_type in [:def, :defp] and is_list(args) ->
          vars = extract_vars_from_list(args, meta)
          {node, vars ++ issues}

        node, issues ->
          {node, issues}
      end)

    Enum.reverse(issues)
  end

  # --- Helpers ---

  defp extract_vars(ast, meta) do
    Macro.prewalk(ast, [], fn
      {name, var_meta, ctx} = node, acc
      when name in @shadowed and is_atom(ctx) ->
        issue = trigger_issue(var_meta || meta, name)
        {node, [issue | acc]}

      node, acc ->
        {node, acc}
    end)
    |> elem(1)
  end

  defp extract_vars_from_list(list, meta) do
    Enum.flat_map(list, &extract_vars(&1, meta))
  end

  defp trigger_issue(meta, name) do
    %Issue{
      rule: :no_max_min_shadowing,
      severity: :warning,
      message: """
      The variable `#{name}` shadows the built-in `Kernel.#{name}/2` function.

      This is unidiomatic and can make code harder to read, especially when
      calling `#{name}(#{name}, other)`.

      Consider renaming this variable to `#{name}_val`, `global_#{name}`, or
      something more descriptive.
      """,
      meta: %{line: Keyword.get(meta, :line)}
    }
  end
end
