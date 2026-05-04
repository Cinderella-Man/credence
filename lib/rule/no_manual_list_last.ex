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

  ## Auto-fix

  Replaces the hand-rolled function with a `List.last/1` delegation and
  rewrites call sites within the same source file.
  """

  use Credence.Rule
  alias Credence.Issue

  @impl true
  def fixable?, do: true

  @impl true
  def check(ast, _opts) do
    clauses = collect_clauses(ast)

    clauses
    |> Enum.group_by(fn {name, arity, _def_type, _meta, _pattern, _body} ->
      {name, arity}
    end)
    |> Enum.flat_map(fn {_key, group} -> analyze_group(group) end)
    |> Enum.sort_by(fn issue -> issue.meta[:line] || 0 end)
  end

  @impl true
  def fix(source, _opts) do
    ast = Code.string_to_quoted!(source)
    matches = find_matching_functions(ast)

    if Enum.empty?(matches) do
      source
    else
      match_names = MapSet.new(matches, fn {name, _def_type} -> name end)
      match_set = MapSet.new(matches)

      transformed = transform_ast(ast, match_set, match_names)

      Macro.to_string(transformed)
    end
  end

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

  defp extract_clause({def_type, meta, [{fn_name, _, [arg]}, body]})
       when def_type in [:def, :defp] and is_atom(fn_name) do
    {:ok, {fn_name, 1, def_type, meta, arg, body}}
  end

  defp extract_clause({def_type, _meta, [{:when, _, _}, _body]})
       when def_type in [:def, :defp] do
    :error
  end

  defp extract_clause(_), do: :error

  defp analyze_group(clauses) when length(clauses) != 2, do: []

  defp analyze_group([clause_a, clause_b]) do
    {name, _, def_type, _, _, _} = clause_a

    cond do
      list_last?(clause_a, clause_b, name) ->
        meta = elem(clause_a, 3)
        [build_issue(def_type, name, meta)]

      list_last?(clause_b, clause_a, name) ->
        meta = elem(clause_b, 3)
        [build_issue(def_type, name, meta)]

      true ->
        []
    end
  end

  defp list_last?(base_clause, recursive_clause, fn_name) do
    single_element_return?(base_clause) and
      cons_recurse?(recursive_clause, fn_name)
  end

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

  defp body_recurses_with?(
         [do: {fn_name, _, [{var_name, _, ctx}]}],
         fn_name,
         tail_name
       )
       when is_atom(var_name) and is_atom(ctx) do
    var_name == tail_name
  end

  defp body_recurses_with?(_, _, _), do: false

  defp find_matching_functions(ast) do
    clauses = collect_clauses(ast)

    clauses
    |> Enum.group_by(fn {name, arity, _def_type, _meta, _pattern, _body} ->
      {name, arity}
    end)
    |> Enum.flat_map(fn {_key, group} -> analyze_group_for_fix(group) end)
  end

  defp analyze_group_for_fix(clauses) when length(clauses) != 2, do: []

  defp analyze_group_for_fix([clause_a, clause_b]) do
    {name, _, def_type, _, _, _} = clause_a

    cond do
      list_last?(clause_a, clause_b, name) -> [{name, def_type}]
      list_last?(clause_b, clause_a, name) -> [{name, def_type}]
      true -> []
    end
  end

  # ------------------------------------------------------------
  # FIX — recursive AST transformer
  #
  # A custom recursive walker that:
  #  • handles 2-tuples (keyword pairs like {:do, body})
  #  • skips function-definition name/pattern nodes so they
  #    are never confused with call sites
  #  • removes recursive clauses and replaces base clauses
  #    with List.last/1 delegation
  # ------------------------------------------------------------

  defp transform_ast(node, match_set, match_names) do
    case node do
      # ---- Pipe call: x |> fn_name() or x |> fn_name ----
      {:|>, pipe_meta, [lhs, {fn_name, call_meta, pipe_args}]}
      when is_atom(fn_name) and (pipe_args == [] or is_nil(pipe_args)) ->
        if MapSet.member?(match_names, fn_name) do
          list_last_fn = {{:., [], [{:__aliases__, [], [:List]}, :last]}, [], []}

          {:|>, pipe_meta, [transform_ast(lhs, match_set, match_names), list_last_fn]}
        else
          {:|>, pipe_meta,
           [
             transform_ast(lhs, match_set, match_names),
             {fn_name, call_meta, pipe_args}
           ]}
        end

      # ---- Function definition ----
      {def_type, meta, [{fn_name, name_meta, args}, body]}
      when def_type in [:def, :defp] and is_atom(fn_name) ->
        if MapSet.member?(match_set, {fn_name, def_type}) do
          pattern = hd(args)

          if single_element_var_pattern?(pattern) do
            make_list_last_def(def_type, meta, fn_name)
          else
            {:__block__, [], []}
          end
        else
          new_body = transform_ast(body, match_set, match_names)
          {def_type, meta, [{fn_name, name_meta, args}, new_body]}
        end

      # ---- __block__ — filter out removed clauses ----
      {:__block__, meta, body} ->
        new_body =
          body
          |> Enum.flat_map(fn elem ->
            case transform_ast(elem, match_set, match_names) do
              {:__block__, [], []} -> []
              other -> [other]
            end
          end)

        case new_body do
          [single] -> single
          _ -> {:__block__, meta, new_body}
        end

      # ---- Direct call: fn_name(arg) ----
      {fn_name, meta, [arg]} when is_atom(fn_name) ->
        if MapSet.member?(match_names, fn_name) do
          transformed_arg = transform_ast(arg, match_set, match_names)
          {{:., [], [{:__aliases__, [], [:List]}, :last]}, [], [transformed_arg]}
        else
          {fn_name, meta, [transform_ast(arg, match_set, match_names)]}
        end

      # ---- Generic 3-tuple (fallthrough) ----
      {tag, meta, args} when is_list(args) ->
        {tag, meta, Enum.map(args, &transform_ast(&1, match_set, match_names))}

      # ---- 2-tuple (keyword pair like {:do, expr}) ----
      {left, right} ->
        {transform_ast(left, match_set, match_names),
         transform_ast(right, match_set, match_names)}

      # ---- List ----
      list when is_list(list) ->
        Enum.map(list, &transform_ast(&1, match_set, match_names))

      # ---- Leaf (atom, number, string, nil …) ----
      other ->
        other
    end
  end

  defp single_element_var_pattern?(pattern) do
    case pattern do
      [{var_name, _, ctx}] when is_atom(var_name) and is_atom(ctx) -> true
      _ -> false
    end
  end

  defp make_list_last_def(def_type, meta, fn_name) do
    var = {:list, [], nil}
    list_last_body = {{:., [], [{:__aliases__, [], [:List]}, :last]}, [], [var]}
    {def_type, meta, [{fn_name, [], [var]}, [do: list_last_body]]}
  end

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
