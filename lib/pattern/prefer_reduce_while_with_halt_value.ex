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

  # DSL-unsafe: introduces `case`/reduce-while control flow that Ash.Expr forbids
  # (use cond), Ecto.Query forbids, and Nx.Defn does not allow.
  @impl true
  def unsafe_in_dsl, do: :all
  alias Credence.Issue
  alias Credence.RuleHelpers

  @impl true
  def check(ast, _opts) do
    # Fire only where the full extraction block is present and safely fixable
    # (`{_, _, flag} = reduce_while(...); flag`), so `check` and `fix` agree.
    {_ast, issues} =
      Macro.prewalk(ast, [], fn
        {:__block__, _, stmts} = node, issues when is_list(stmts) ->
          case find_pattern(stmts) do
            {:ok, _idx, _binding, reduce_call, _bool_name} ->
              {node, [build_issue(call_meta(reduce_call)) | issues]}

            _ ->
              {node, issues}
          end

        node, issues ->
          {node, issues}
      end)

    Enum.reverse(issues)
  end

  defp call_meta({_dot, meta, _args}), do: meta

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
    tuple?(acc_node) and false_flag_acc?(acc_node) and
      single_clause_fn?(fn_node) and callback_matches?(fn_node)
  end

  # Only 3-element accumulators are safe: dropping the flag yields a 2-tuple,
  # which the generated `case` matches with `{_, _}`. Larger tuples would leave
  # an unmatched arity and crash with CaseClauseError on a non-halting run.
  defp tuple?({:{}, _, elems}) when is_list(elems) and length(elems) == 3, do: true
  defp tuple?(_), do: false

  # The initial accumulator's flag must be `false`: on an empty enumerable
  # reduce_while returns the initial accumulator unchanged, so a `true` seed
  # would make the original yield `true` while the fix yields `false`.
  defp false_flag_acc?({:{}, _, elems}) when is_list(elems) do
    last = List.last(elems)
    boolean_literal?(last) and unwrap_boolean(last) == false
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
      {:{}, _, param_elems} when is_list(param_elems) and length(param_elems) == 3 ->
        third_param_unused?(List.last(param_elems), body) and check_body_if(body)

      _ ->
        false
    end
  end

  defp third_param_unused?({:_, _, _}, _body), do: true

  defp third_param_unused?({name, _, context}, body)
       when is_atom(name) and (is_atom(context) or is_nil(context)) do
    {_body, used?} =
      Macro.prewalk(body, false, fn
        {^name, _, var_context} = node, _used
        when is_atom(var_context) or is_nil(var_context) ->
          {node, true}

        node, used ->
          {node, used}
      end)

    not used?
  end

  defp third_param_unused?(_, _body), do: false

  defp check_body_if(body) do
    case extract_if(body) do
      {:ok, if_node} -> if_anti_pattern?(if_node)
      _ -> false
    end
  end

  defp extract_if({:__block__, _, stmts}) when is_list(stmts) do
    extract_if(List.last(stmts))
  end

  defp extract_if({:if, _, _} = if_node), do: {:ok, if_node}
  defp extract_if(_), do: :error

  defp if_anti_pattern?({:if, _, [_, [do_kw, else_kw]]}) do
    with {:ok, do_body} <- extract_kw(do_kw, :do),
         {:ok, else_body} <- extract_kw(else_kw, :else),
         {:halt, halt_tuple} <- extract_halt_or_cont(do_body),
         {:cont, cont_tuple} <- extract_halt_or_cont(else_body),
         true <- tuple_arity?(halt_tuple, 3),
         true <- tuple_arity?(cont_tuple, 3),
         true <- halt_prefix_safe_to_discard?(halt_tuple),
         true <- tuple_with_boolean_last?(halt_tuple, true),
         true <- tuple_with_boolean_last?(cont_tuple, false) do
      true
    else
      _ -> false
    end
  end

  defp if_anti_pattern?(_), do: false

  defp tuple_arity?({:{}, _, elems}, n) when is_list(elems), do: length(elems) == n
  defp tuple_arity?(_, _), do: false

  defp extract_kw({{:__block__, _, [key]}, body}, key), do: {:ok, body}
  defp extract_kw(_, _), do: :error

  defp extract_halt_or_cont({:__block__, _, [inner]}), do: extract_halt_or_cont(inner)

  defp extract_halt_or_cont({{:__block__, _, [tag]}, value})
       when tag in [:halt, :cont],
       do: {tag, value}

  defp extract_halt_or_cont({tag, value}) when tag in [:halt, :cont], do: {tag, value}
  defp extract_halt_or_cont(_), do: :error

  defp tuple_with_boolean_last?({:{}, _, elems}, expected_bool) when is_list(elems) do
    last = List.last(elems)
    boolean_literal?(last) and unwrap_boolean(last) == expected_bool
  end

  defp halt_prefix_safe_to_discard?({:{}, _, [first, second, _flag]}) do
    discard_safe?(first) and discard_safe?(second)
  end

  defp halt_prefix_safe_to_discard?(_), do: false

  defp discard_safe?({:__block__, _, [value]}), do: discard_safe?(value)

  defp discard_safe?({name, _, context})
       when is_atom(name) and (is_atom(context) or is_nil(context)),
       do: true

  defp discard_safe?(value)
       when is_atom(value) or is_number(value) or is_binary(value) or is_nil(value),
       do: true

  defp discard_safe?(_), do: false

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

  # Find the safely-fixable pattern:
  #
  #     {_a, _b, flag} = Enum.reduce_while(..., {x, y, false}, fn ... end)
  #     flag                       # the block's last statement
  #
  # All conditions are required so the rewrite is behaviour-preserving and so
  # `check` (which reuses this) never flags a case the fix cannot transform:
  #   * exactly a 3-element binding whose first two elements are unused (`_`-vars)
  #   * the flag variable is the very last statement of the block (nothing after
  #     it can reference the now-removed binding)
  #   * the reduce_while call itself matches the narrowed anti-pattern
  defp find_pattern(stmts) do
    last_idx = length(stmts) - 1

    Enum.find_value(Enum.with_index(stmts), fn
      {{:=, _, [{:{}, _, bind_elems}, reduce_call]}, idx} when is_list(bind_elems) ->
        with true <- length(bind_elems) == 3,
             true <- first_binds_unused?(bind_elems),
             true <- idx + 1 == last_idx,
             true <- reduce_while_call_p?(reduce_call),
             {bool_name, _, ctx} when is_atom(bool_name) and is_atom(ctx) <-
               Enum.at(stmts, idx + 1),
             true <- elem(List.last(bind_elems), 0) == bool_name,
             {acc_node, fn_node} <- reduce_acc_fn(reduce_call),
             true <- anti_pattern?(acc_node, fn_node) do
          {:ok, idx, {:{}, [], bind_elems}, reduce_call, bool_name}
        else
          _ -> nil
        end

      _ ->
        nil
    end)
  end

  defp first_binds_unused?([a, b, _flag]) do
    underscore_var?(a) and underscore_var?(b)
  end

  defp first_binds_unused?(_), do: false

  defp underscore_var?({name, _, ctx}) when is_atom(name) and is_atom(ctx) do
    String.starts_with?(Atom.to_string(name), "_")
  end

  defp underscore_var?(_), do: false

  defp reduce_acc_fn({_dot, _meta, args}) when is_list(args) and length(args) >= 2 do
    {Enum.at(args, -2), List.last(args)}
  end

  defp reduce_acc_fn(_), do: :error

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
    new_stmts = List.update_at(stmts, -1, &transform_stmt/1)
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
