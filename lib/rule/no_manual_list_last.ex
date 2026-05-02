defmodule Credence.Rule.NoManualListLast do
  @moduledoc """
  Detects hand-rolled reimplementations of `List.last/1`.

  ## Why this matters

  When `NoListLast` flags `List.last/1`, LLMs "fix" it by writing the
  exact same O(n) traversal under a different name:

      # Flagged — this IS List.last, just hand-rolled
      defp get_last_element([val]), do: val
      defp get_last_element([_ | rest]), do: get_last_element(rest)

  This has the same performance characteristics as `List.last/1` but
  adds unnecessary code.  The real fix is to restructure the algorithm
  to avoid needing the last element:

  - Track the value in an accumulator during a reduce
  - Reverse the list and take the head
  - Destructure from the other end

  ## Detection scope

  A two-clause `defp` (or `def`) function with arity 1 where:

  1. One clause matches `[val]` (single-element list) and returns `val`
  2. The other clause matches `[_ | rest]` and recurses with `rest`
  """

  @behaviour Credence.Rule
  alias Credence.Issue

  @impl true
  def check(ast, _opts) do
    clauses = collect_clauses(ast)

    clauses
    |> Enum.group_by(fn {name, arity, _def_type, _meta, _pattern, _body} -> {name, arity} end)
    |> Enum.flat_map(fn {_key, group} -> analyze_group(group) end)
    |> Enum.sort_by(fn issue -> issue.meta[:line] || 0 end)
  end

  # ------------------------------------------------------------
  # CLAUSE COLLECTION
  # ------------------------------------------------------------

  defp collect_clauses(ast) do
    {_ast, clauses} =
      Macro.prewalk(ast, [], fn node, acc ->
        case extract_clause(node) do
          {:ok, clause} -> {node, [clause | acc]}
          :error -> {node, acc}
        end
      end)

    Enum.reverse(clauses)
  end

  # Only unguarded clauses — guarded ones indicate more complex logic
  defp extract_clause({def_type, meta, [{fn_name, _, [arg]}, body]})
       when def_type in [:def, :defp] and is_atom(fn_name) do
    {:ok, {fn_name, 1, def_type, meta, arg, body}}
  end

  # Skip guarded clauses
  defp extract_clause({def_type, _meta, [{:when, _, _}, _body]})
       when def_type in [:def, :defp] do
    :error
  end

  defp extract_clause(_), do: :error

  # ------------------------------------------------------------
  # GROUP ANALYSIS
  # ------------------------------------------------------------

  defp analyze_group(clauses) when length(clauses) != 2, do: []

  defp analyze_group([clause_a, clause_b]) do
    {name, _, def_type, _, _, _} = clause_a

    cond do
      is_list_last?(clause_a, clause_b, name) ->
        meta = elem(clause_a, 3)
        [build_issue(def_type, name, meta)]

      is_list_last?(clause_b, clause_a, name) ->
        meta = elem(clause_b, 3)
        [build_issue(def_type, name, meta)]

      true ->
        []
    end
  end

  # ------------------------------------------------------------
  # PATTERN DETECTION
  #
  # base_clause: matches [val], returns val
  # recursive_clause: matches [_ | rest], calls name(rest)
  # ------------------------------------------------------------

  defp is_list_last?(base_clause, recursive_clause, fn_name) do
    single_element_return?(base_clause) and
      cons_recurse?(recursive_clause, fn_name)
  end

  # Matches: defp foo([val]), do: val
  # Pattern is a list with one simple variable, body returns that variable
  defp single_element_return?({_name, 1, _def_type, _meta, pattern, body}) do
    case pattern do
      [{var_name, _, ctx}] when is_atom(var_name) and is_atom(ctx) ->
        body_returns_var?(body, var_name)

      _ ->
        false
    end
  end

  defp body_returns_var?([do: {var_name, _, ctx}], target)
       when is_atom(var_name) and is_atom(ctx) do
    var_name == target
  end

  defp body_returns_var?(_, _), do: false

  # Matches: defp foo([_ | rest]), do: foo(rest)
  # Pattern is a cons with ignored head, body recurses on tail
  defp cons_recurse?({_name, 1, _def_type, _meta, pattern, body}, fn_name) do
    case pattern do
      [{:|, _, [head, {tail_name, _, ctx}]}]
      when is_atom(tail_name) and is_atom(ctx) ->
        wildcard?(head) and body_recurses_with?(body, fn_name, tail_name)

      _ ->
        false
    end
  end

  defp wildcard?({name, _, ctx}) when is_atom(name) and is_atom(ctx) do
    name == :_ or String.starts_with?(Atom.to_string(name), "_")
  end

  defp wildcard?(_), do: false

  # Body is: do: fn_name(tail_var)
  defp body_recurses_with?([do: {fn_name, _, [{var_name, _, ctx}]}], fn_name, tail_name)
       when is_atom(var_name) and is_atom(ctx) do
    var_name == tail_name
  end

  defp body_recurses_with?(_, _, _), do: false

  # ------------------------------------------------------------
  # MESSAGE GENERATION
  # ------------------------------------------------------------

  defp build_issue(def_type, fn_name, meta) do
    %Issue{
      rule: :no_manual_list_last,
      message: """
      `#{def_type} #{fn_name}/1` is a manual reimplementation of `List.last/1` \
      with the same O(n) cost.

      Rather than reimplementing list traversal, restructure the algorithm \
      to avoid needing the last element:

      • Track the value in an accumulator during Enum.reduce
      • Reverse the list and take the head: `hd(Enum.reverse(list))`
      • Build results so the needed value is at the head, not the tail
      """,
      meta: %{line: Keyword.get(meta, :line)}
    }
  end
end
