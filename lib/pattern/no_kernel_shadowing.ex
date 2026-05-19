defmodule Credence.Pattern.NoKernelShadowing do
  @moduledoc """
  Idiomatic rule: fixes variables that shadow `Kernel` functions.

  Using `max` or `min` as variable names (e.g., in `Enum.reduce` or function
  arguments) shadows the built-in Kernel functions. While `max(max, value)` is
  valid Elixir, it is unidiomatic and can lead to confusion.

  This rule renames shadowing variables to descriptive alternatives:
  `max` → `max_value`, `min` → `min_value`, `hd` → `head`, etc.
  """

  use Credence.Pattern.Rule
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

  @renames %{
    max: :max_value,
    min: :min_value,
    elem: :element,
    hd: :head,
    tl: :tail,
    length: :count,
    abs: :abs_value,
    round: :rounded,
    trunc: :truncated,
    div: :quotient,
    rem: :remainder,
    tuple_size: :tuple_len,
    map_size: :map_len,
    byte_size: :num_bytes,
    bit_size: :num_bits
  }

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

  @impl true
  def fix(source, _opts) do
    source
    |> Sourceror.parse_string!()
    |> Macro.postwalk(fn
      {name, meta, ctx} when name in @shadowed and is_atom(ctx) ->
        {Map.get(@renames, name, :"#{name}_value"), meta, ctx}

      node ->
        node
    end)
    |> Sourceror.to_string()
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
      rule: :no_kernel_shadowing,
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
