defmodule Credence.Pattern.NoListReplaceAtInReduce do
  @moduledoc """
  Check-only rule: Detects `List.replace_at/3` and `List.update_at/3` called
  on the accumulator variable inside `Enum.reduce/2,3` or `for ... reduce`.

  Also detects calls to `defp` helper functions that delegate to
  `List.replace_at/3` or `List.update_at/3` on their first parameter,
  when called from a reduce body with the accumulator as the first argument.

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

      # Hidden behind a helper function — still flagged
      Enum.reduce(range, dp, fn i, dp ->
        update_dp(dp, i, compute(i))
      end)

      defp update_dp(dp, i, value) do
        row = Enum.at(dp, i)
        new_row = List.replace_at(row, 0, value)
        List.replace_at(dp, i, new_row)
      end

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
    # Pre-scan: find defp functions that use List.replace_at/update_at on first param
    suspicious_helpers = collect_suspicious_helpers(ast)

    {_ast, issues} =
      Macro.prewalk(ast, [], fn
        # 3-arg: Enum.reduce(enum, initial, fn ...)
        {{:., _, [{:__aliases__, _, [:Enum]}, :reduce]}, meta, [_enum, _initial, fun]} = node,
        issues ->
          {node, check_lambda(fun, meta, issues, suspicious_helpers)}

        # 2-arg piped: |> Enum.reduce(initial, fn ...)
        {{:., _, [{:__aliases__, _, [:Enum]}, :reduce]}, meta, [_initial, fun]} = node, issues ->
          {node, check_lambda(fun, meta, issues, suspicious_helpers)}

        # for ... reduce: for x <- range, reduce: initial do ... end
        {:for, for_meta, [_generator, _opts, [{{:__block__, _, [:do]}, clauses}]]} = node,
        issues ->
          {node, check_for_reduce_clauses(clauses, for_meta, issues, suspicious_helpers)}

        node, issues ->
          {node, issues}
      end)

    Enum.reverse(issues)
  end

  @impl true
  def fix_patches(_ast, _opts), do: []

  # --- private ---

  defp collect_suspicious_helpers(ast) do
    {_ast, helpers} =
      Macro.prewalk(ast, MapSet.new(), fn
        {:defp, _, children} = node, acc when is_list(children) and length(children) >= 2 ->
          case extract_defp_info(children) do
            {:ok, fn_name, params, body} ->
              if uses_list_replace_on_first_param?(body, params) do
                {node, MapSet.put(acc, fn_name)}
              else
                {node, acc}
              end

            :error ->
              {node, acc}
          end

        node, acc ->
          {node, acc}
      end)

    helpers
  end

  defp extract_defp_info([head, body_kw | _rest]) do
    with {:ok, fn_name, params} <- extract_defp_head(head),
         {:ok, body} <- extract_do_body(body_kw) do
      {:ok, fn_name, params, body}
    else
      _ -> :error
    end
  end

  defp extract_defp_info(_), do: :error

  defp extract_defp_head({fn_name, _, params})
       when is_atom(fn_name) and is_list(params),
       do: {:ok, fn_name, params}

  defp extract_defp_head({:when, _, [{fn_name, _, params}, _guard]})
       when is_atom(fn_name) and is_list(params),
       do: {:ok, fn_name, params}

  defp extract_defp_head(_), do: :error

  # Sourceror wraps do keyword: [{{:__block__, _, [:do]}, body}]
  defp extract_do_body([{{:__block__, _, [:do]}, body} | _]), do: {:ok, body}
  # Standard Elixir: [do: body]
  defp extract_do_body([{:do, body} | _]), do: {:ok, body}
  defp extract_do_body(_), do: :error

  defp uses_list_replace_on_first_param?(body, params) do
    case params do
      [{first_name, _, nil} | _] when is_atom(first_name) ->
        body
        |> Macro.prewalk(false, fn
          {{:., _, [{:__aliases__, _, [:List]}, fun]}, _, [{name, _, nil} | _]} = node, false
          when is_atom(name) and name == first_name and fun in [:replace_at, :update_at] ->
            {node, true}

          {:|>, _, [{name, _, nil}, {{:., _, [{:__aliases__, _, [:List]}, fun]}, _, _}]} = node,
          false
          when is_atom(name) and name == first_name and fun in [:replace_at, :update_at] ->
            {node, true}

          node, found ->
            {node, found}
        end)
        |> elem(1)

      _ ->
        false
    end
  end

  defp check_lambda({:fn, _, clauses}, _reduce_meta, issues, suspicious_helpers) do
    Enum.reduce(clauses, issues, fn {:->, clause_meta, [params, body]}, acc ->
      if length(params) == 2 do
        acc_var_name = extract_var_name(List.last(params))

        if acc_var_name do
          check_body(body, acc_var_name, clause_meta, acc, suspicious_helpers)
        else
          acc
        end
      else
        acc
      end
    end)
  end

  defp check_lambda(_, _, issues, _suspicious_helpers), do: issues

  defp check_for_reduce_clauses(clauses, _for_meta, issues, suspicious_helpers)
       when is_list(clauses) do
    Enum.reduce(clauses, issues, fn
      {:->, clause_meta, [params, body]}, acc ->
        acc_var_name = extract_var_name(List.first(params))

        if acc_var_name do
          check_body(body, acc_var_name, clause_meta, acc, suspicious_helpers)
        else
          acc
        end

      _, acc ->
        acc
    end)
  end

  defp check_for_reduce_clauses(_, _, issues, _suspicious_helpers), do: issues

  defp check_body(body, acc_var_name, clause_meta, issues, suspicious_helpers) do
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

        # Piped helper function call: acc |> helper(...)
        {:|>, _,
         [
           {acc_name, _, nil},
           {fn_name, call_meta, _args}
         ]} = node,
        found
        when is_atom(fn_name) and is_atom(acc_name) and acc_name == acc_var_name ->
          if MapSet.member?(suspicious_helpers, fn_name) do
            {node, [Keyword.get(call_meta, :line) || Keyword.get(clause_meta, :line) | found]}
          else
            {node, found}
          end

        # Helper function call with accumulator as first arg: helper(acc, ...)
        {fn_name, call_meta, [{acc_name, _, nil} | _rest]} = node, found
        when is_atom(fn_name) and is_atom(acc_name) and acc_name == acc_var_name ->
          if MapSet.member?(suspicious_helpers, fn_name) do
            {node, [Keyword.get(call_meta, :line) || Keyword.get(clause_meta, :line) | found]}
          else
            {node, found}
          end

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
