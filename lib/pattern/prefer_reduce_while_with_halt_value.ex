defmodule Credence.Pattern.PreferReduceWhileWithHaltValue do
  @moduledoc """
  Detects `Enum.reduce_while/3` that carries a boolean flag in the accumulator
  solely to signal whether to halt, when the halt value itself could convey the
  answer directly.

  ## Bad

      {_prefix_sum, _seen_sums, found?} =
        Enum.reduce_while(list, {0, MapSet.new([0]), false}, fn num, {ps, ss, _f} ->
          new_sum = ps + num

          if MapSet.member?(ss, new_sum) do
            {:halt, {new_sum, ss, true}}
          else
            {:cont, {new_sum, MapSet.put(ss, new_sum), false}}
          end
        end)

      found?

  ## Good

      Enum.reduce_while(list, {0, MapSet.new([0])}, fn num, {ps, ss} ->
        new_sum = ps + num

        if MapSet.member?(ss, new_sum) do
          {:halt, true}
        else
          {:cont, {new_sum, MapSet.put(ss, new_sum)}}
        end
      end)
      |> case do
        true -> true
        {_, _} -> false
      end

  ## Auto-fix

  Removes the boolean flag from the accumulator, callback parameters,
  and halt/continue tuples.  Replaces the post-reduce extraction of
  the flag with a pipe into `case` that distinguishes the halt value
  (`true`) from a normal tuple result.
  """

  use Credence.Pattern.Rule
  alias Credence.Issue
  alias Credence.RuleHelpers

  @impl true
  def check(ast, _opts) do
    {_ast, issues} =
      Macro.prewalk(ast, [], fn
        {{:., _, _} = dot, meta, args} = node, issues when is_list(args) ->
          if reduce_while_call?(dot) and length(args) >= 2 do
            acc_node = Enum.at(args, -2)
            fn_node = List.last(args)

            if anti_pattern?(acc_node, fn_node) do
              {node, [build_issue(meta) | issues]}
            else
              {node, issues}
            end
          else
            {node, issues}
          end

        node, issues ->
          {node, issues}
      end)

    Enum.reverse(issues)
  end

  @impl true
  def fix_patches(ast, opts) do
    source = Keyword.get(opts, :source, "")

    RuleHelpers.patches_from_ast_transform(ast, source, fn ast ->
      transform_ast(ast)
    end)
  end

  # ── Anti-pattern detection ─────────────────────────────────────────

  defp reduce_while_call?({:., _, [{:__aliases__, _, [:Enum]}, :reduce_while]}), do: true
  defp reduce_while_call?({:., _, [:Enum, :reduce_while]}), do: true
  defp reduce_while_call?(_), do: false

  defp anti_pattern?(acc_node, fn_node) do
    tuple?(acc_node) and has_boolean_last?(acc_node) and
      single_clause_fn?(fn_node) and callback_matches?(fn_node)
  end

  defp tuple?({:{}, _, elems}) when is_list(elems) and length(elems) >= 3, do: true
  defp tuple?(_), do: false

  defp has_boolean_last?({:{}, _, elems}) when is_list(elems) do
    last = List.last(elems)
    boolean_literal?(last)
  end

  defp boolean_literal?({:__block__, _, [bool]}) when is_boolean(bool), do: true
  defp boolean_literal?(bool) when is_boolean(bool), do: true
  defp boolean_literal?(_), do: false

  defp unwrap_boolean({:__block__, _, [bool]}) when is_boolean(bool), do: bool
  defp unwrap_boolean(bool) when is_boolean(bool), do: bool

  defp single_clause_fn?({:fn, _, [{:->, _, _}]}), do: true
  defp single_clause_fn?(_), do: false

  defp callback_matches?({:fn, _, [{:->, _, [params, body]}]}) do
    case Enum.at(params, 1) do
      {:{}, _, param_elems} when is_list(param_elems) and length(param_elems) >= 3 ->
        check_body_if(body)

      _ ->
        false
    end
  end

  defp check_body_if(body) do
    case extract_if(body) do
      {:ok, if_node} -> if_anti_pattern?(if_node)
      _ -> false
    end
  end

  defp extract_if({:__block__, _, stmts}) when is_list(stmts) do
    Enum.find_value(stmts, fn
      {:if, _, _} = if_node -> {:ok, if_node}
      _ -> nil
    end)
  end

  defp extract_if({:if, _, _} = if_node), do: {:ok, if_node}
  defp extract_if(_), do: :error

  defp if_anti_pattern?({:if, _, [_, [do_kw, else_kw]]}) do
    with {:ok, do_body} <- extract_kw(do_kw, :do),
         {:ok, else_body} <- extract_kw(else_kw, :else),
         {:halt, halt_tuple} <- extract_halt_or_cont(do_body),
         {:cont, cont_tuple} <- extract_halt_or_cont(else_body),
         true <- tuple_with_boolean_last?(halt_tuple, true),
         true <- tuple_with_boolean_last?(cont_tuple, false),
         true <- same_tuple_arity?(halt_tuple, cont_tuple) do
      true
    else
      _ -> false
    end
  end

  defp if_anti_pattern?(_), do: false

  defp same_tuple_arity?({:{}, _, a_elems}, {:{}, _, b_elems}) do
    length(a_elems) == length(b_elems)
  end

  defp extract_kw({{:__block__, _, [key]}, body}, key), do: {:ok, body}
  defp extract_kw(_, _), do: :error

  defp extract_halt_or_cont({:__block__, _, [inner]}), do: extract_halt_or_cont(inner)

  defp extract_halt_or_cont({{:__block__, _, [tag]}, value})
       when tag in [:halt, :cont],
       do: {tag, value}

  defp extract_halt_or_cont({tag, value}) when tag in [:halt, :cont], do: {tag, value}
  defp extract_halt_or_cont(_), do: :error

  defp tuple_with_boolean_last?({:{}, _, elems}, expected_bool) when is_list(elems) do
    unwrap_boolean(List.last(elems)) == expected_bool
  end

  defp tuple_with_boolean_last?(_, _), do: false

  # ── AST transformation ─────────────────────────────────────────────

  # Transform the entire AST, looking for blocks that contain the anti-pattern
  # reduce_while result pattern.
  defp transform_ast(ast) do
    Macro.postwalk(ast, fn
      {:__block__, meta, stmts} = node when is_list(stmts) ->
        transform_block_if_needed(stmts, meta, node)

      node ->
        node
    end)
  end

  # Check if a block has the pattern:
  #   {a, b, flag} = Enum.reduce_while(..., {x, y, false}, fn ... end)
  #   flag
  # And rewrite it to:
  #   Enum.reduce_while(..., {x, y}, fn ... end) |> case do ... end
  defp transform_block_if_needed(stmts, meta, fallback) do
    case find_pattern(stmts) do
      {:ok, idx, _binding, reduce_call, _bool_var_name} ->
        # 1. Transform the reduce_while call (remove boolean from acc, callback)
        transformed_call = transform_reduce_while(reduce_call)

        # 2. Build the case expression
        case_expr = build_case_expr()

        # 3. Build pipe: Enum.reduce_while(...) |> case do ... end
        piped = {:|>, [], [transformed_call, case_expr]}

        # 4. Reconstruct block: everything before + piped, skip old assignment + flag var
        before = Enum.take(stmts, idx)
        after_flag = Enum.drop(stmts, idx + 2)

        {:__block__, meta, before ++ [piped] ++ after_flag}

      _ ->
        fallback
    end
  end

  # Find the pattern: binding = reduce_while(...); bool_var
  defp find_pattern(stmts) do
    Enum.find_value(Enum.with_index(stmts), fn
      {{:=, _, [{:{}, _, [_ | _] = bind_elems}, reduce_call]}, idx} ->
        if reduce_while_call_p?(reduce_call) and length(bind_elems) >= 3 do
          case Enum.at(stmts, idx + 1) do
            {bool_name, _, ctx} when is_atom(bool_name) and is_atom(ctx) ->
              last_bind = List.last(bind_elems)

              if elem(last_bind, 0) == bool_name do
                {:ok, idx, {:{}, [], bind_elems}, reduce_call, bool_name}
              end

            _ ->
              nil
          end
        end

      _ ->
        nil
    end)
  end

  defp reduce_while_call_p?({{:., _, _} = dot, _, args})
       when is_list(args) and length(args) >= 2,
       do: reduce_while_call?(dot)

  defp reduce_while_call_p?(_), do: false

  # Transform the reduce_while call: remove boolean from acc, params, halt/cont.
  defp transform_reduce_while({dot, call_meta, args}) do
    acc_node = Enum.at(args, -2)
    fn_node = List.last(args)

    new_acc = remove_last_tuple_elem(acc_node)
    new_fn = transform_callback(fn_node)
    new_args = args |> List.replace_at(-2, new_acc) |> List.replace_at(-1, new_fn)
    {dot, call_meta, new_args}
  end

  defp transform_callback({:fn, fn_meta, [{:->, arrow_meta, [params, body]}]}) do
    new_params =
      Enum.map(params, fn
        {:{}, t_meta, elems} when length(elems) >= 3 ->
          {:{}, t_meta, Enum.drop(elems, -1)}

        other ->
          other
      end)

    new_body = transform_body(body)
    {:fn, fn_meta, [{:->, arrow_meta, [new_params, new_body]}]}
  end

  defp transform_body({:__block__, meta, stmts}) when is_list(stmts) do
    new_stmts = Enum.map(stmts, &transform_stmt/1)
    {:__block__, meta, new_stmts}
  end

  defp transform_body(stmt), do: transform_stmt(stmt)

  defp transform_stmt({:if, if_meta, [cond_expr, branches]}) do
    new_branches =
      Enum.map(branches, fn
        {{:__block__, kw_meta, [key]}, body} when key in [:do, :else] ->
          {{:__block__, kw_meta, [key]}, transform_halt_cont_body(body)}

        other ->
          other
      end)

    {:if, if_meta, [cond_expr, new_branches]}
  end

  defp transform_stmt(other), do: other

  defp transform_halt_cont_body({:__block__, meta, [inner]}) do
    case extract_halt_or_cont(inner) do
      {:halt, {:{}, _t_meta, elems}} when is_list(elems) and length(elems) >= 3 ->
        # {:halt, {tuple..., true}} -> {:halt, true}
        bool_val = unwrap_boolean(List.last(elems))
        {:__block__, meta, [{:halt, bool_val}]}

      {:cont, {:{}, t_meta, elems}} when is_list(elems) and length(elems) >= 3 ->
        # {:cont, {tuple..., false}} -> {:cont, {tuple...}}
        new_tuple = {:{}, t_meta, Enum.drop(elems, -1)}
        {:__block__, meta, [{:cont, new_tuple}]}

      _ ->
        {:__block__, meta, [inner]}
    end
  end

  defp transform_halt_cont_body(other), do: other

  defp remove_last_tuple_elem({:{}, meta, elems}) when is_list(elems) and length(elems) >= 3 do
    {:{}, meta, Enum.drop(elems, -1)}
  end

  defp remove_last_tuple_elem(other), do: other

  # Build: |> case do true -> true; {_, _} -> false end
  defp build_case_expr do
    true_clause = {:->, [], [[{:__block__, [], [true]}], {:__block__, [], [true]}]}

    false_clause =
      {:->, [],
       [
         [{:__block__, [], [{{:_, [], nil}, {:_, [], nil}}]}],
         {:__block__, [], [false]}
       ]}

    {:case, [], [[do: [true_clause, false_clause]]]}
  end

  defp build_issue(meta) do
    %Issue{
      rule: :prefer_reduce_while_with_halt_value,
      message:
        "`Enum.reduce_while/3` carries a boolean flag in the accumulator " <>
          "solely to signal halt. Use the halt value itself to convey the " <>
          "answer — it is more direct and idiomatic.",
      meta: %{line: Keyword.get(meta, :line)}
    }
  end
end
