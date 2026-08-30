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

  ## Bad

      defmodule BadNDR do
        def process([a, b, c]) do
          Enum.map([a, b, c], &(&1 * 2))
        end
      end

  ## Good

      defmodule BadNDR do
        def process([_, _, _] = items) do
          Enum.map(items, &(&1 * 2))
        end
      end
  """

  use Credence.Pattern.Rule
  # Safe in all three families: matches only a def/defp clause head or an
  # existing `case` clause whose pattern is a list of ≥2 bare variables, and
  # rewrites that pattern plus the list literal it rebuilds — never an operator
  # or a control construct. The source scan flags this rule because the
  # construct appears in it, but the matcher cannot reach a DSL expression, so
  # the deliberate answer is the empty list rather than an allowlist entry — the
  # fixture-level oracle does not flag it at all.
  @impl true
  def unsafe_in_dsl, do: []
  alias Credence.Issue
  alias Credence.RuleHelpers

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

  defp check_node({:case, _meta, [_expr, kw_list]}) when is_list(kw_list) do
    with {:ok, clauses} <- RuleHelpers.extract_do_body(kw_list),
         true <- is_list(clauses) do
      issues =
        Enum.flat_map(clauses, fn
          {:->, meta, [[pattern], body]} -> check_pattern_body(pattern, body, meta)
          _ -> []
        end)

      if issues == [], do: :error, else: {:ok, issues}
    else
      _ -> :error
    end
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
        if body_contains_same_list?(body, var_names) and
             not reassigns_any?(body, var_names) do
          [build_issue(var_names, meta)]
        else
          []
        end

      _ ->
        []
    end
  end

  @impl true
  def fix_patches(ast, _opts) do
    RuleHelpers.patches_from_postwalk(ast, &maybe_rewrite/1)
  end

  defp maybe_rewrite({:case, case_meta, [expr, kw_list]} = node) when is_list(kw_list) do
    with {:ok, clauses} <- RuleHelpers.extract_do_body(kw_list),
         true <- is_list(clauses),
         fixed_clauses <- Enum.map(clauses, &fix_case_clause/1),
         true <- fixed_clauses != clauses do
      {:case, case_meta, [expr, RuleHelpers.replace_do_body(kw_list, fixed_clauses)]}
    else
      _ -> node
    end
  end

  defp maybe_rewrite(
         {def_type, def_meta, [{:when, when_meta, [{fn_name, head_meta, args}, guard]}, body]} =
           node
       )
       when def_type in [:def, :defp] and is_list(args) do
    case rewrite_args_and_body(args, body, guard) do
      {:changed, new_args, new_body} ->
        {def_type, def_meta,
         [{:when, when_meta, [{fn_name, head_meta, new_args}, guard]}, new_body]}

      :unchanged ->
        node
    end
  end

  defp maybe_rewrite({def_type, def_meta, [{fn_name, head_meta, args}, body]} = node)
       when def_type in [:def, :defp] and is_atom(fn_name) and is_list(args) do
    case rewrite_args_and_body(args, body, nil) do
      {:changed, new_args, new_body} ->
        {def_type, def_meta, [{fn_name, head_meta, new_args}, new_body]}

      :unchanged ->
        node
    end
  end

  defp maybe_rewrite(node), do: node

  defp rewrite_args_and_body(args, body, extra_ast) do
    {new_args, new_body, changed?} =
      Enum.reduce(args, {[], body, false}, fn arg, {acc, cur_body, changed} ->
        case fix_pattern_body(arg, cur_body, extra_ast) do
          {:fixed, new_arg, new_body} -> {acc ++ [new_arg], new_body, true}
          :no_fix -> {acc ++ [arg], cur_body, changed}
        end
      end)

    if changed?, do: {:changed, new_args, new_body}, else: :unchanged
  end

  defp fix_case_clause({:->, meta, [[pattern], body]}) do
    case fix_pattern_body(pattern, body) do
      {:fixed, new_pattern, new_body} -> {:->, meta, [[new_pattern], new_body]}
      :no_fix -> {:->, meta, [[pattern], body]}
    end
  end

  defp fix_case_clause(other), do: other

  defp fix_pattern_body(pattern, body, extra_ast \\ nil) do
    with {:ok, elements, list_node} <- RuleHelpers.unwrap_list(pattern),
         {:ok, var_names} when length(var_names) >= 2 <- extract_names_from_elements(elements),
         true <- body_contains_same_list?(body, var_names),
         false <- reassigns_any?(body, var_names) do
      binding_var = {:items, [], nil}
      new_body = replace_reconstructed_list(body, var_names, binding_var)

      used = collect_variable_names(new_body)

      used =
        if extra_ast, do: MapSet.union(used, collect_variable_names(extra_ast)), else: used

      new_elements =
        Enum.map(elements, fn
          {name, meta, ctx} when is_atom(name) and is_atom(ctx) ->
            if MapSet.member?(used, name), do: {name, meta, ctx}, else: {:_, meta, ctx}

          other ->
            other
        end)

      new_list = RuleHelpers.rewrap_list(list_node, new_elements)
      {:fixed, {:=, [], [new_list, binding_var]}, new_body}
    else
      _ -> :no_fix
    end
  end

  defp replace_reconstructed_list(body, target_var_names, replacement) do
    # Prewalk so we hit the `:__block__` wrapper before descending into
    # the inner list — replacing the inner list alone leaves the
    # bracket-carrying wrapper behind, which re-renders as `[items]`.
    Macro.prewalk(body, fn
      {:__block__, _, [elements]} = node when is_list(elements) ->
        case extract_names_from_elements(elements) do
          {:ok, ^target_var_names} -> replacement
          _ -> node
        end

      node ->
        node
    end)
  end

  # The fix rebinds the whole list as `items` on the pattern and substitutes the
  # reconstructed `[a, b, c]` in the body with `items`. That is only sound when
  # the reconstructed list still equals the bound input — i.e. none of the
  # destructured variables were reassigned between the head pattern and the
  # reconstruction. If the body rebinds any of them (`script = …`,
  # `{:ok, y} <- …`, `left = lazy(left)`), `items` holds the *original* values
  # while the reconstruction used the recomputed ones, so substituting `items`
  # silently returns stale data. Bail (in both check and fix) when any
  # destructured name appears on the LHS of a match (`=`) or `<-` in the body.
  defp reassigns_any?(body, var_names) do
    target = MapSet.new(var_names)

    {_, found} =
      Macro.prewalk(body, false, fn
        node, true ->
          {node, true}

        {op, _, [lhs, _rhs]} = node, false when op in [:=, :<-] ->
          {node, not MapSet.disjoint?(collect_variable_names(lhs), target)}

        node, false ->
          {node, false}
      end)

    found
  end

  defp body_contains_same_list?(body, target_var_names) do
    {_, found} =
      Macro.prewalk(body, false, fn
        node, true ->
          {node, true}

        node, false ->
          case RuleHelpers.unwrap_list(node) do
            {:ok, elements, _} ->
              case extract_names_from_elements(elements) do
                {:ok, ^target_var_names} -> {node, true}
                _ -> {node, false}
              end

            :error ->
              {node, false}
          end
      end)

    found
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

  defp extract_var_names(pattern) do
    with {:ok, elements, _} <- RuleHelpers.unwrap_list(pattern) do
      extract_names_from_elements(elements)
    end
  end

  defp extract_names_from_elements(elements) when is_list(elements) do
    names =
      Enum.map(elements, fn
        {name, _, ctx} when is_atom(name) and is_atom(ctx) ->
          str = Atom.to_string(name)
          if String.starts_with?(str, "_"), do: :skip, else: name

        _ ->
          :skip
      end)

    if Enum.any?(names, &(&1 == :skip)), do: :error, else: {:ok, names}
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
