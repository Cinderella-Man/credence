defmodule Credence.Pattern.NoListReplaceAtInReduce do
  @moduledoc """
  Check-only rule: Detects `List.replace_at/3` and `List.update_at/3` called
  on the accumulator variable inside `Enum.reduce/2,3` or `for ... reduce`.

  Both functions rebuild the entire list up to the target index — O(n) per
  call. Using them on the accumulator inside a loop compounds to O(n²).
  Use a map (`Map.put/3`) or a tuple (`put_elem/3`) instead.

  ## Bad

      Enum.reduce(range, list, fn i, acc ->
        List.replace_at(acc, i, compute(i))
      end)

      Enum.reduce(range, dp, fn i, dp ->
        dp
        |> List.replace_at(i, left)
        |> List.replace_at(i + 1, right)
      end)

      for i <- 1..n, reduce: table do
        table ->
          List.update_at(table, i, fn _ -> compute(i) end)
      end

  ## Good

      Enum.reduce(range, %{}, fn i, acc ->
        Map.put(acc, i, compute(i))
      end)

      tuple = List.to_tuple(list)

      Enum.reduce(range, tuple, fn i, acc ->
        put_elem(acc, i, compute(i))
      end)
  """

  use Credence.Pattern.Rule
  alias Credence.Issue

  @impl true
  def check(ast, _opts) do
    {_ast, issues} =
      Macro.prewalk(ast, [], fn
        # 3-arg: Enum.reduce(enum, initial, fn ...)
        {{:., _, [{:__aliases__, _, [:Enum]}, :reduce]}, meta, [_enum, _initial, fun]} = node,
        issues ->
          {node, check_lambda(fun, meta, issues)}

        # 2-arg piped: |> Enum.reduce(initial, fn ...)
        {{:., _, [{:__aliases__, _, [:Enum]}, :reduce]}, meta, [_initial, fun]} = node, issues ->
          {node, check_lambda(fun, meta, issues)}

        # for ... reduce: for x <- range, reduce: initial do ... end
        {:for, for_meta, [_generator, _opts, [{{:__block__, _, [:do]}, clauses}]]} = node,
        issues ->
          {node, check_for_reduce_clauses(clauses, for_meta, issues)}

        node, issues ->
          {node, issues}
      end)

    Enum.reverse(issues)
  end

  @impl true
  def fix_patches(_ast, _opts), do: []

  # --- private ---

  defp check_lambda({:fn, _, clauses}, _reduce_meta, issues) do
    Enum.reduce(clauses, issues, fn {:->, clause_meta, [params, body]}, acc ->
      if length(params) == 2 do
        acc_var_name = extract_var_name(List.last(params))

        if acc_var_name do
          check_body(body, acc_var_name, clause_meta, acc)
        else
          acc
        end
      else
        acc
      end
    end)
  end

  defp check_lambda(_, _, issues), do: issues

  defp check_for_reduce_clauses(clauses, _for_meta, issues) when is_list(clauses) do
    Enum.reduce(clauses, issues, fn
      {:->, clause_meta, [params, body]}, acc ->
        acc_var_name = extract_var_name(List.first(params))

        if acc_var_name do
          check_body(body, acc_var_name, clause_meta, acc)
        else
          acc
        end

      _, acc ->
        acc
    end)
  end

  defp check_for_reduce_clauses(_, _, issues), do: issues

  defp check_body(body, acc_var_name, clause_meta, issues) do
    {_ast, replacements} =
      Macro.prewalk(body, [], fn
        # Direct call: List.replace_at(acc, idx, val) or List.update_at(acc, idx, fn)
        {{:., _, [{:__aliases__, _, [:List]}, fun]}, call_meta,
         [{acc_name, _, nil}, _idx, _val]} = node,
        found
        when is_atom(acc_name) and acc_name == acc_var_name and fun in [:replace_at, :update_at] ->
          {node, [Keyword.get(call_meta, :line) || Keyword.get(clause_meta, :line) | found]}

        # Piped call: acc |> List.replace_at(idx, val) or acc |> List.update_at(idx, fn)
        {:|>, _,
         [
           {acc_name, _, nil},
           {{:., _, [{:__aliases__, _, [:List]}, fun]}, call_meta, [_idx, _val]}
         ]} = node,
        found
        when is_atom(acc_name) and acc_name == acc_var_name and fun in [:replace_at, :update_at] ->
          {node, [Keyword.get(call_meta, :line) || Keyword.get(clause_meta, :line) | found]}

        node, found ->
          {node, found}
      end)

    case replacements do
      [] ->
        issues

      [line | _] ->
        [
          %Issue{
            rule: :no_list_replace_at_in_reduce,
            message:
              "`List.replace_at/3` / `List.update_at/3` on the reduce accumulator " <>
                "rebuilds the entire list on every iteration (O(n) per call). " <>
                "Use `Map.put/3` or convert to a tuple and use `put_elem/3`.",
            meta: %{line: line}
          }
          | issues
        ]
    end
  end

  defp extract_var_name({name, _, ctx}) when is_atom(name) and (is_nil(ctx) or is_atom(ctx)),
    do: name

  defp extract_var_name(_), do: nil
end
