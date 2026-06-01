defmodule Credence.Pattern.NoManualHasDuplicates do
  @moduledoc """
  Readability rule: Detects manual recursive duplicate detection using a Map or
  MapSet as a set accumulator.

  LLMs frequently generate a recursive helper that walks a list, tracks seen
  elements in a `%{}` map (or `MapSet`), and returns `true` on the first
  duplicate.  This entire pattern collapses to a single expression:

      Enum.uniq(list) != list

  ## Bad

      def has_duplicates(list), do: do_check(list, %{})

      defp do_check([], _seen), do: false
      defp do_check([head | tail], seen) do
        if Map.get(seen, head) do
          true
        else
          do_check(tail, Map.put(seen, head, true))
        end
      end

  ## Good

      def has_duplicates(list), do: Enum.uniq(list) != list

  ## Detection scope

  A multi-clause `defp` (or `def`) function with arity 2 where:

  1. One clause matches `([], _)` and returns `false`
  2. Another clause matches `([_ | _], accumulator)` and:
     - checks membership of the head in the accumulator (`Map.get`,
       `Map.has_key?`, `MapSet.member?`, `Map.fetch`, `Map.get_and_update`)
     - returns `true` in the membership branch
     - recurses with an updated accumulator in the other branch
  """

  use Credence.Pattern.Rule
  alias Credence.Issue

  @impl true
  def check(ast, _opts) do
    clauses = collect_clauses(ast)

    clauses
    |> Enum.group_by(fn {name, arity, _def_type, _meta, _params, _body} ->
      {name, arity}
    end)
    |> Enum.flat_map(fn {_key, group} -> analyze_group(group) end)
    |> Enum.sort_by(fn issue -> issue.meta[:line] || 0 end)
  end

  @impl true
  def fix_patches(_ast, _opts), do: []

  # Collect all function clauses from the AST
  defp collect_clauses(ast) do
    {_ast, clauses} =
      Macro.prewalk(ast, [], fn
        {kind, meta, [{:when, _, [{name, _, params}, _guard]}, body_kw]} = node, acc
        when kind in [:def, :defp] and is_atom(name) and is_list(params) ->
          body = extract_body(body_kw)
          entry = {name, length(params), kind, meta, params, body}
          {node, [entry | acc]}

        {kind, meta, [{name, _, params}, body_kw]} = node, acc
        when kind in [:def, :defp] and is_atom(name) and is_list(params) ->
          body = extract_body(body_kw)
          entry = {name, length(params), kind, meta, params, body}
          {node, [entry | acc]}

        node, acc ->
          {node, acc}
      end)

    Enum.reverse(clauses)
  end

  defp extract_body(body_kw) when is_list(body_kw) do
    Enum.find_value(body_kw, fn
      {{:__block__, _, [:do]}, body} -> body
      _ -> nil
    end)
  end

  defp extract_body(body), do: body

  # Analyze a group of clauses with the same {name, arity}
  defp analyze_group(group) when length(group) < 2, do: []

  defp analyze_group(group) do
    # Look for the pattern: base case returns false, recursive case checks set membership
    has_base_false? =
      Enum.any?(group, fn {_name, _arity, _kind, _meta, params, body} ->
        empty_list_base_false?(params, body)
      end)

    if has_base_false? do
      group
      |> Enum.find_value([], fn {_name, _arity, _kind, meta, params, body} ->
        if recursive_set_membership_check?(params, body) do
          [%Issue{
            rule: :no_manual_has_duplicates,
            message:
              "Manual recursive duplicate detection with a set accumulator can be " <>
                "replaced with `Enum.uniq(list) != list`.",
            meta: %{line: Keyword.get(meta, :line)}
          }]
        end
      end)
      |> List.wrap()
      |> List.flatten()
    else
      []
    end
  end

  # Checks if a clause is: defp func([], _seen), do: false
  defp empty_list_base_false?(params, body) do
    case {params, body} do
      {[first_param, _second_param], false} ->
        empty_list_pattern?(first_param)

      {[first_param, _second_param], {:__block__, _, [false]}} ->
        empty_list_pattern?(first_param)

      _ ->
        false
    end
  end

  defp empty_list_pattern?({:__block__, _, [[]]}), do: true
  defp empty_list_pattern?([]), do: true
  defp empty_list_pattern?(_), do: false

  # Checks if a clause is the recursive set-membership check pattern:
  #   defp func([head | tail], seen) do
  #     if set_member?(seen, head) do
  #       true
  #     else
  #       func(tail, updated_set)
  #     end
  #   end
  defp recursive_set_membership_check?(params, body) do
    case {params, body} do
      {[first_param, _set_param], {:if, _, [condition, clauses]}} when is_list(clauses) ->
        cons_pattern?(first_param) and
          set_membership_condition?(condition) and
          if_returns_true_and_recurses?(clauses)

      _ ->
        false
    end
  end

  # Matches [head | tail] pattern (Sourceror wraps lists in {:__block__, meta, [[elements]]})
  defp cons_pattern?({:__block__, _meta, [list]}) when is_list(list) do
    case list do
      [{:|, _, _} | _] -> true
      _ -> false
    end
  end

  defp cons_pattern?([{:|, _, _} | _]), do: true
  defp cons_pattern?(_), do: false

  # Checks if the condition is a set membership check:
  #   Map.get(seen, head), Map.has_key?(seen, head), MapSet.member?(seen, head),
  #   Map.fetch(seen, head), Map.get_and_update(seen, head, ...)
  defp set_membership_condition?(condition) do
    case condition do
      # Map.get(seen, head)
      {{:., _, [{:__aliases__, _, [:Map]}, :get]}, _, [_, _]} ->
        true

      # Map.get(seen, head, default)
      {{:., _, [{:__aliases__, _, [:Map]}, :get]}, _, [_, _, _]} ->
        true

      # Map.has_key?(seen, head)
      {{:., _, [{:__aliases__, _, [:Map]}, :has_key?]}, _, [_, _]} ->
        true

      # MapSet.member?(seen, head)
      {{:., _, [{:__aliases__, _, [:MapSet]}, :member?]}, _, [_, _]} ->
        true

      # Map.fetch(seen, head)
      {{:., _, [{:__aliases__, _, [:Map]}, :fetch]}, _, [_, _]} ->
        true

      _ ->
        false
    end
  end

  # Checks the if-clauses: do branch returns true, else branch recurses
  defp if_returns_true_and_recurses?(clauses) do
    do_body = extract_clause(clauses, :do)
    else_body = extract_clause(clauses, :else)

    is_true_literal?(do_body) and body_calls_self?(else_body)
  end

  defp extract_clause(clauses, key) do
    Enum.find_value(clauses, fn
      {{:__block__, _, [^key]}, body} -> body
      _ -> nil
    end)
  end

  defp is_true_literal?(true), do: true
  defp is_true_literal?({:__block__, _, [true]}), do: true
  defp is_true_literal?(_), do: false

  # Check if the body contains a self-recursive call
  defp body_calls_self?(body) do
    {_ast, found} =
      Macro.prewalk(body, false, fn
        {name, _, args} = node, acc when is_atom(name) and is_list(args) ->
          # Check if it looks like a recursive call (has 2 args)
          if length(args) == 2 do
            {node, true}
          else
            {node, acc}
          end

        node, acc ->
          {node, acc}
      end)

    found
  end
end
