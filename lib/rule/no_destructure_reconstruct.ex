defmodule Credence.Rule.NoDestructureReconstruct do
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

  ## Flagged patterns

  A list pattern `[a, b, c, ...]` in a `case` branch or function head
  where the body contains a list literal `[a, b, c, ...]` with the
  exact same variables in the same order.

  Only flagged when the pattern contains 2 or more simple variables
  (not literals, patterns, or underscore-prefixed names).

  ## Severity

  `:info`
  """

  @behaviour Credence.Rule
  alias Credence.Issue

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

  # ------------------------------------------------------------
  # NODE MATCHING
  # ------------------------------------------------------------

  # case expr do [a, b, c] -> body; ... end
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

  # def/defp foo([a, b, c]), do: body (unguarded)
  # Must come after guarded to avoid :when swallowing
  defp check_node({def_type, _meta, [{:when, _, [{_fn_name, _, args}, _guard]}, body]})
       when def_type in [:def, :defp] and is_list(args) do
    issues =
      args
      |> Enum.flat_map(fn arg -> check_pattern_body(arg, body, []) end)

    if issues == [], do: :error, else: {:ok, issues}
  end

  defp check_node({def_type, _meta, [{_fn_name, _, args}, body]})
       when def_type in [:def, :defp] and is_list(args) do
    issues =
      args
      |> Enum.flat_map(fn arg -> check_pattern_body(arg, body, []) end)

    if issues == [], do: :error, else: {:ok, issues}
  end

  defp check_node(_), do: :error

  # ------------------------------------------------------------
  # PATTERN/BODY ANALYSIS
  # ------------------------------------------------------------

  defp check_pattern_body(pattern, body, meta) do
    case extract_var_list(pattern) do
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

  # ------------------------------------------------------------
  # PATTERN EXTRACTION
  #
  # Only matches a flat list of simple, non-underscore variables.
  # Returns :error if any element is a literal, pattern, or
  # underscore-prefixed name.
  # ------------------------------------------------------------

  defp extract_var_list(elements) when is_list(elements) do
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

  defp extract_var_list(_), do: :error

  # ------------------------------------------------------------
  # BODY INSPECTION
  #
  # Walk the body AST looking for a list literal that contains
  # the exact same variables in the exact same order.
  # ------------------------------------------------------------

  defp body_contains_same_list?(body, target_var_names) do
    {_, found} =
      Macro.prewalk(body, false, fn
        node, true ->
          {node, true}

        elements, false when is_list(elements) ->
          case extract_var_list(elements) do
            {:ok, ^target_var_names} -> {elements, true}
            _ -> {elements, false}
          end

        node, false ->
          {node, false}
      end)

    found
  end

  # ------------------------------------------------------------
  # MESSAGE GENERATION
  # ------------------------------------------------------------

  defp build_issue(var_names, meta) do
    vars_str = Enum.map_join(var_names, ", ", &to_string/1)
    count = length(var_names)

    %Issue{
      rule: :no_destructure_reconstruct,
      severity: :info,
      message: """
      List `[#{vars_str}]` is destructured and then reassembled \
      into the same list.

      Bind the list as a whole and pattern match for length:

          [#{"_ , " |> String.duplicate(count - 1)}_ ] = parts
      """,
      meta: %{line: Keyword.get(meta, :line)}
    }
  end
end
