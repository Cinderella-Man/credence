defmodule Credence.Pattern.NoDestructureReconstruct do
  @moduledoc """
  Detects patterns where a list is destructured into individual variables
  and then immediately reassembled into the same list.

  ## Why this matters

  LLMs destructure lists element-by-element because they think in terms
  of individual values, then reconstruct the list to pass to an Enum
  function.  The reader sees named variables and expects them to be used
  individually, only to discover they're re-wrapped:

      # Flagged — destructure then reconstruct
      case String.split(ip, ".") do
        [p1, p2, p3, p4] ->
          Enum.all?([p1, p2, p3, p4], &valid_octet?/1)
      end

      # Idiomatic — bind as a whole, pattern match for length
      case String.split(ip, ".") do
        [_, _, _, _] = parts ->
          Enum.all?(parts, &valid_octet?/1)
      end

  ## Auto-fix strategy

  1. Bind the whole list with `= items` on the pattern
  2. Replace the reconstructed list `[a, b, c]` in the body with `items`
  3. Check which individual variables are still used elsewhere in the
     body — replace unused ones with `_` in the pattern

  ## Flagged patterns

  A list pattern `[a, b, c, ...]` in a `case` branch or function head
  where the body contains a list literal `[a, b, c, ...]` with the
  exact same variables in the same order.

  Only flagged when the pattern contains 2 or more simple variables
  (not literals, patterns, or underscore-prefixed names).
  """

  use Credence.Rule
  alias Credence.Issue

  @impl true
  def fixable?, do: true

  @impl true
  def check(ast, _opts) do
    {_ast, issues} =
      Macro.prewalk(ast, [], fn node, issues ->
        case check_node(node) do
          {:ok, new_issues} -> {node, new_issues ++ issues}
          :error -> {node, issues}
        end
      end)

    Enum.reverse(issues)
  end

  defp check_node({:case, _meta, [_expr, [do: clauses]]}) when is_list(clauses) do
    issues =
      Enum.flat_map(clauses, fn
        {:->, meta, [[pattern], body]} ->
          check_pattern_body(pattern, body, meta)

        _ ->
          []
      end)

    if issues == [], do: :error, else: {:ok, issues}
  end

  defp check_node({def_type, _meta, [{:when, _, [{_fn_name, _, args}, _guard]}, body]})
       when def_type in [:def, :defp] and is_list(args) do
    issues = Enum.flat_map(args, fn arg -> check_pattern_body(arg, body, []) end)
    if issues == [], do: :error, else: {:ok, issues}
  end

  defp check_node({def_type, _meta, [{_fn_name, _, args}, body]})
       when def_type in [:def, :defp] and is_list(args) do
    issues = Enum.flat_map(args, fn arg -> check_pattern_body(arg, body, []) end)
    if issues == [], do: :error, else: {:ok, issues}
  end

  defp check_node(_), do: :error

  defp check_pattern_body(pattern, body, meta) do
    case extract_var_names(pattern) do
      {:ok, var_names} when length(var_names) >= 2 ->
        if body_contains_same_list?(body, var_names) do
          [build_issue(var_names, meta)]
        else
          []
        end

      _ ->
        []
    end
  end

  @impl true
  def fix(source, _opts) do
    source
    |> Code.string_to_quoted!()
    |> Macro.postwalk(fn
      # Case expressions
      {:case, case_meta, [expr, [do: clauses]]} when is_list(clauses) ->
        fixed_clauses = Enum.map(clauses, &fix_case_clause/1)
        {:case, case_meta, [expr, [do: fixed_clauses]]}

      # Function heads with guard
      {def_type, def_meta, [{:when, when_meta, [{fn_name, head_meta, args}, guard]}, body]}
      when def_type in [:def, :defp] and is_list(args) ->
        {new_args, new_body} = fix_fn_args(args, body, guard)

        {def_type, def_meta,
         [{:when, when_meta, [{fn_name, head_meta, new_args}, guard]}, new_body]}

      # Function heads without guard
      {def_type, def_meta, [{fn_name, head_meta, args}, body]}
      when def_type in [:def, :defp] and is_atom(fn_name) and is_list(args) ->
        {new_args, new_body} = fix_fn_args(args, body, nil)
        {def_type, def_meta, [{fn_name, head_meta, new_args}, new_body]}

      node ->
        node
    end)
    |> Macro.to_string()
  end

  defp fix_case_clause({:->, meta, [[pattern], body]}) do
    case fix_pattern_body(pattern, body) do
      {:fixed, new_pattern, new_body} -> {:->, meta, [[new_pattern], new_body]}
      :no_fix -> {:->, meta, [[pattern], body]}
    end
  end

  defp fix_case_clause(other), do: other

  defp fix_fn_args(args, body, extra_ast) do
    Enum.reduce(args, {[], body}, fn arg, {fixed_args, current_body} ->
      case fix_pattern_body(arg, current_body, extra_ast) do
        {:fixed, new_arg, new_body} -> {fixed_args ++ [new_arg], new_body}
        :no_fix -> {fixed_args ++ [arg], current_body}
      end
    end)
  end

  defp fix_pattern_body(pattern, body, extra_ast \\ nil)

  defp fix_pattern_body(pattern, body, extra_ast) when is_list(pattern) do
    case extract_var_names(pattern) do
      {:ok, var_names} when length(var_names) >= 2 ->
        if body_contains_same_list?(body, var_names) do
          binding_var = {:items, [], nil}
          new_body = replace_reconstructed_list(body, var_names, binding_var)

          # Determine which individual variables are still used in the new body
          # and in any extra AST (e.g. guard clauses)
          used = collect_variable_names(new_body)

          used =
            if extra_ast do
              MapSet.union(used, collect_variable_names(extra_ast))
            else
              used
            end

          new_pattern_elements =
            Enum.map(pattern, fn
              {name, meta, ctx} when is_atom(name) and is_atom(ctx) ->
                if MapSet.member?(used, name), do: {name, meta, ctx}, else: {:_, meta, ctx}

              other ->
                other
            end)

          {:fixed, {:=, [], [new_pattern_elements, binding_var]}, new_body}
        else
          :no_fix
        end

      _ ->
        :no_fix
    end
  end

  defp fix_pattern_body(_, _, _), do: :no_fix

  defp replace_reconstructed_list(body, target_var_names, replacement) do
    Macro.postwalk(body, fn
      elements when is_list(elements) ->
        case extract_var_names(elements) do
          {:ok, ^target_var_names} -> replacement
          _ -> elements
        end

      node ->
        node
    end)
  end

  defp collect_variable_names(ast) do
    {_, names} =
      Macro.postwalk(ast, MapSet.new(), fn
        {name, _, ctx} = node, acc when is_atom(name) and is_atom(ctx) ->
          {node, MapSet.put(acc, name)}

        node, acc ->
          {node, acc}
      end)

    names
  end

  defp extract_var_names(elements) when is_list(elements) do
    names =
      Enum.map(elements, fn
        {name, _, ctx} when is_atom(name) and is_atom(ctx) ->
          str = Atom.to_string(name)
          if String.starts_with?(str, "_"), do: :skip, else: name

        _ ->
          :skip
      end)

    if Enum.any?(names, &(&1 == :skip)) do
      :error
    else
      {:ok, names}
    end
  end

  defp extract_var_names(_), do: :error

  defp body_contains_same_list?(body, target_var_names) do
    {_, found} =
      Macro.prewalk(body, false, fn
        node, true ->
          {node, true}

        elements, false when is_list(elements) ->
          case extract_var_names(elements) do
            {:ok, ^target_var_names} -> {elements, true}
            _ -> {elements, false}
          end

        node, false ->
          {node, false}
      end)

    found
  end

  defp build_issue(var_names, meta) do
    vars_str = Enum.map_join(var_names, ", ", &to_string/1)
    count = length(var_names)

    %Issue{
      rule: :no_destructure_reconstruct,
      message: """
      List `[#{vars_str}]` is destructured and then reassembled \
      into the same list.

      Bind the list as a whole and pattern match for length:

          [#{String.duplicate("_, ", count - 1)}_] = parts\
      """,
      meta: %{line: Keyword.get(meta, :line)}
    }
  end
end
