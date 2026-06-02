defmodule Credence.Pattern.NoSumByReduce do
  @moduledoc "Flags transform-and-sum reduce patterns that should use Enum.sum_by/2."

  use Credence.Pattern.Rule
  alias Credence.Issue

  @impl true
  def priority, do: 502

  @impl true
  def check(ast, _opts) do
    {_ast, issues} =
      Macro.prewalk(ast, [], fn
        {{:., _, _}, meta, args} = node, issues ->
          if reduce_call?(node) and sum_by_body?(args) do
            issue = %Issue{
              rule: :no_sum_by_reduce,
              message: "Transform-and-sum reduce detected. Prefer Enum.sum_by/2.",
              meta: %{line: Keyword.get(meta, :line)}
            }

            {node, [issue | issues]}
          else
            {node, issues}
          end

        node, issues ->
          {node, issues}
      end)

    Enum.reverse(issues)
  end

  @impl true
  def fix_patches(ast, _opts) do
    Credence.RuleHelpers.patches_from_postwalk(ast, fn
      {{:., _, _}, _meta, args} = node ->
        if reduce_call?(node) and sum_by_body?(args) do
          case args do
            [enum, _acc_init, fn_ast] -> sum_by_call(enum, fn_ast)
            [_acc_init, fn_ast] -> sum_by_call_piped(fn_ast)
          end
        else
          node
        end

      node ->
        node
    end)
  end

  defp sum_by_call(enum, fn_ast) do
    new_fn = transform_fn(fn_ast)
    {{:., [], [{:__aliases__, [], [:Enum]}, :sum_by]}, [], [enum, new_fn]}
  end

  defp sum_by_call_piped(fn_ast) do
    new_fn = transform_fn(fn_ast)
    {{:., [], [{:__aliases__, [], [:Enum]}, :sum_by]}, [], [new_fn]}
  end

  defp transform_fn({:fn, fn_meta, clauses}) do
    new_clauses =
      Enum.map(clauses, fn
        {:->, arrow_meta, [[elem_pattern, {acc_name, _, _}], body]} ->
          transform = extract_transform(body, acc_name)
          {:->, arrow_meta, [[elem_pattern], transform]}
      end)

    {:fn, fn_meta, new_clauses}
  end

  defp extract_transform({:__block__, _, [body]}, acc_name),
    do: extract_transform(body, acc_name)

  defp extract_transform({:+, _, [{acc_var, _, _}, transform]}, acc_name)
       when acc_var == acc_name,
       do: transform

  defp extract_transform({:+, _, [transform, {acc_var, _, _}]}, acc_name)
       when acc_var == acc_name,
       do: transform

  # No-op catch-all: _, acc -> acc  →  _ -> 0
  defp extract_transform({acc_var, _, _}, acc_name)
       when acc_var == acc_name,
       do: 0

  defp extract_transform(other, _acc_name), do: other

  defp reduce_call?({{:., _, [{:__aliases__, _, [:Enum]}, :reduce]}, _, _}), do: true
  defp reduce_call?({{:., _, [:Enum, :reduce]}, _, _}), do: true
  defp reduce_call?(_), do: false

  defp sum_by_body?([
         _enum,
         acc_init,
         {:fn, _, [{:->, _, [[{elem, _, _}, {acc, _, _}], body]}]}
       ])
       when is_atom(elem) and is_atom(acc) do
    body = unwrap_block(body)
    literal_zero?(acc_init) and transform_sum?(body, elem, acc) and not simple_sum?(body, elem, acc)
  end

  # Multi-clause reduce with no-op catch-all (e.g. chunk_every without :discard)
  defp sum_by_body?([
         _enum,
         acc_init,
         {:fn, _, clauses}
       ])
       when is_list(clauses) and length(clauses) > 1 do
    literal_zero?(acc_init) and sum_with_noop_catchall?(clauses)
  end

  # Piped reduce: 2-arg single-clause
  defp sum_by_body?([
         acc_init,
         {:fn, _, [{:->, _, [[{elem, _, _}, {acc, _, _}], body]}]}
       ])
       when is_atom(elem) and is_atom(acc) do
    body = unwrap_block(body)
    literal_zero?(acc_init) and transform_sum?(body, elem, acc) and not simple_sum?(body, elem, acc)
  end

  # Piped reduce: 2-arg multi-clause with no-op catch-all
  defp sum_by_body?([
         acc_init,
         {:fn, _, clauses}
       ])
       when is_list(clauses) and length(clauses) > 1 do
    literal_zero?(acc_init) and sum_with_noop_catchall?(clauses)
  end

  defp sum_by_body?(_), do: false

  # --- multi-clause sum helpers ---

  defp sum_with_noop_catchall?(clauses) do
    {sum_clauses, other_clauses} = Enum.split_with(clauses, &sum_clause?/1)
    length(sum_clauses) == 1 and Enum.all?(other_clauses, &noop_catchall?/1)
  end

  defp sum_clause?({:->, _, [[_elem_pattern, {acc, _, _}], body]})
       when is_atom(acc) do
    body = unwrap_block(body)
    transform_sum?(body, nil, acc)
  end

  defp sum_clause?(_), do: false

  defp noop_catchall?({:->, _, [[_pattern, {acc, _, _}], body]})
       when is_atom(acc) do
    case unwrap_block(body) do
      {body_acc, _, _} when is_atom(body_acc) -> body_acc == acc
      _ -> false
    end
  end

  defp noop_catchall?(_), do: false

  defp literal_zero?(0), do: true
  defp literal_zero?({:__block__, _, [0]}), do: true
  defp literal_zero?(_), do: false

  defp unwrap_block({:__block__, _, [body]}), do: body
  defp unwrap_block(body), do: body

  # Check body is acc + expr or expr + acc
  defp transform_sum?({:+, _, [{acc_var, _, _}, _expr]}, _elem, acc)
       when acc_var == acc,
       do: true

  defp transform_sum?({:+, _, [_expr, {acc_var, _, _}]}, _elem, acc)
       when acc_var == acc,
       do: true

  defp transform_sum?(_, _, _), do: false

  # Check if this is a simple sum (just acc + elem or elem + acc) — leave to no_explicit_sum_reduce
  defp simple_sum?({:+, _, [{acc_var, _, _}, {elem_var, _, _}]}, elem, acc)
       when acc_var == acc and elem_var == elem,
       do: true

  defp simple_sum?({:+, _, [{elem_var, _, _}, {acc_var, _, _}]}, elem, acc)
       when elem_var == elem and acc_var == acc,
       do: true

  defp simple_sum?(_, _, _), do: false
end
