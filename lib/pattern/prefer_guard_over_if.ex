defmodule Credence.Pattern.PreferGuardOverIf do
  @moduledoc """
  Detects function clauses whose body is a single `if/else` with a
  guard-eligible condition. In idiomatic Elixir, prefer multi-clause
  functions with guards over wrapping the entire body in `if/else`.

  ## Bad

      defp accumulate_run(last_val, [head | tail] = list, current_run) do
        if head > last_val do
          accumulate_run(head, tail, [head | current_run])
        else
          {Enum.reverse(current_run), list}
        end
      end

  ## Good

      defp accumulate_run(last_val, [head | tail], current_run)
           when head > last_val do
        accumulate_run(head, tail, [head | current_run])
      end

      defp accumulate_run(_last_val, list, current_run) do
        {Enum.reverse(current_run), list}
      end

  ## Auto-fix

  Splits the `if/else` body into two function clauses: the first clause
  gets the condition as a `when` guard with the `do` branch as body; the
  second clause keeps the original head (with any existing guard preserved)
  and uses the `else` branch as its body.
  """

  use Credence.Pattern.Rule
  alias Credence.Issue

  @guard_type_checks [
    :is_atom,
    :is_binary,
    :is_bitstring,
    :is_boolean,
    :is_float,
    :is_function,
    :is_integer,
    :is_list,
    :is_map,
    :is_nil,
    :is_number,
    :is_pid,
    :is_port,
    :is_reference,
    :is_tuple
  ]

  @guard_builtins [
    :abs,
    :ceil,
    :floor,
    :round,
    :trunc,
    :length,
    :map_size,
    :tuple_size,
    :hd,
    :tl,
    :elem,
    :byte_size,
    :bit_size
  ]

  @guard_binary_ops [
    :==,
    :!=,
    :===,
    :!==,
    :<,
    :>,
    :<=,
    :>=,
    :+,
    :-,
    :*,
    :/,
    :rem,
    :div,
    :and,
    :or,
    :in
  ]

  @guard_unary_ops [:not, :-, :+]

  @impl true
  def check(ast, _opts) do
    {_ast, issues} =
      Macro.prewalk(ast, [], fn node, issues ->
        case check_node(node) do
          {:ok, line} ->
            issue = %Issue{
              rule: :prefer_guard_over_if,
              message:
                "Function clause body is a single `if/else` with a guard-eligible condition. " <>
                  "Prefer multi-clause functions with guards.",
              meta: %{line: line}
            }

            {node, [issue | issues]}

          :error ->
            {node, issues}
        end
      end)

    Enum.reverse(issues)
  end

  @impl true
  def fix_patches(ast, _opts) do
    {_ast, patches} =
      Macro.prewalk(ast, [], fn node, acc ->
        case try_build_patch(node) do
          {:ok, patch} -> {node, [patch | acc]}
          :error -> {node, acc}
        end
      end)

    Enum.reverse(patches)
  end

  # Match def/defp with explicit body keyword list
  defp check_node({def_kind, meta, [_head, body_kw]})
       when def_kind in [:def, :defp] and is_list(body_kw) do
    body = extract_body(body_kw)

    case extract_if_else(body) do
      {:ok, condition} ->
        if guard_eligible?(condition) and not simple_equality_with_literal?(condition),
          do: {:ok, meta[:line]},
          else: :error

      :error ->
        :error
    end
  end

  defp check_node(_), do: :error

  defp try_build_patch({def_kind, _meta, [head_ast, body_kw]} = node)
       when def_kind in [:def, :defp] and is_list(body_kw) do
    body = extract_body(body_kw)

    case extract_if_else(body) do
      {:ok, condition} ->
        if guard_eligible?(condition) and not simple_equality_with_literal?(condition) do
          {call, existing_guard} = extract_head_parts(head_ast)
          {do_body, else_body} = extract_branches(body)

          range = Sourceror.get_range(node)
          guard_names = if existing_guard, do: collect_var_names(existing_guard), else: MapSet.new()

          # Build first clause: defp call when condition do do_body end
          # Underscore-prefix any params unused in guard + condition + do_body
          first_guard = combine_guards(existing_guard, condition)
          first_used =
            guard_names
            |> MapSet.union(collect_var_names(condition))
            |> MapSet.union(collect_var_names(do_body))
          first_call = underscore_unused_params(call, first_used)
          first_head = build_head(first_call, first_guard)
          first_clause = {def_kind, [], [first_head, [do: do_body]]}
          first_text = Sourceror.to_string(first_clause)

          # Build second clause: defp call [when existing_guard] do else_body end
          # Underscore-prefix any params unused in guard + else_body
          second_used = MapSet.union(guard_names, collect_var_names(else_body))
          second_call = underscore_unused_params(call, second_used)
          second_head = build_head(second_call, existing_guard)
          second_clause = {def_kind, [], [second_head, [do: else_body]]}
          second_text = Sourceror.to_string(second_clause)

          change = "#{first_text}\n#{second_text}"

          {:ok, %{range: range, change: change}}
        else
          :error
        end

      :error ->
        :error
    end
  end

  defp try_build_patch(_), do: :error

  # Extract the `:do` value from a keyword list, handling both
  # `[do: body]` and `[{{:__block__, _, [:do]}, body}]` forms.
  defp extract_body(kw) do
    case Keyword.get(kw, :do) do
      nil ->
        Enum.find_value(kw, fn
          {{:__block__, _, [:do]}, body} -> body
          _ -> nil
        end)

      body ->
        body
    end
  end

  # Returns {:ok, condition} if the body is a single if/else expression.
  defp extract_if_else({:if, _meta, [condition, clauses]}) when is_list(clauses) do
    if has_both_branches?(clauses), do: {:ok, condition}, else: :error
  end

  # Unwrap single-expression blocks: {:__block__, _, [expr]}
  defp extract_if_else({:__block__, _, [expr]}), do: extract_if_else(expr)

  defp extract_if_else(_), do: :error

  defp has_both_branches?(clauses) do
    has_clause?(clauses, :do) and has_clause?(clauses, :else)
  end

  defp has_clause?(kw, key) do
    case Keyword.get(kw, key) do
      nil -> Enum.any?(kw, fn {{:__block__, _, [k]}, _} -> k == key; _ -> false end)
      _ -> true
    end
  end

  # Guard-eligibility check — conservative: only operators and built-in
  # guard functions are accepted. Any unknown call disqualifies the
  # condition.

  # Unwrap Sourceror single-expression blocks: {:__block__, _, [expr]}
  defp guard_eligible?({:__block__, _, [expr]}), do: guard_eligible?(expr)

  defp guard_eligible?({name, _, ctx})
       when is_atom(name) and (is_atom(ctx) or is_nil(ctx)),
       do: true

  defp guard_eligible?(lit)
       when is_number(lit) or is_atom(lit) or is_boolean(lit) or is_binary(lit),
       do: true

  # Binary operators allowed in guards
  defp guard_eligible?({op, _, [left, right]}) when op in @guard_binary_ops,
    do: guard_eligible?(left) and guard_eligible?(right)

  # Unary operators allowed in guards
  defp guard_eligible?({op, _, [arg]}) when op in @guard_unary_ops,
    do: guard_eligible?(arg)

  # Type-check guards (is_nil, is_integer, etc.)
  defp guard_eligible?({fn_name, _, [arg]}) when fn_name in @guard_type_checks,
    do: guard_eligible?(arg)

  # Built-in guard functions (length, abs, etc.) — accept any arity
  defp guard_eligible?({fn_name, _, args})
       when fn_name in @guard_builtins and is_list(args),
       do: Enum.all?(args, &guard_eligible?/1)

  # Anything else (function calls, pipe chains, etc.) is NOT guard-eligible
  defp guard_eligible?(_), do: false

  # Check if the condition is a simple `var == literal` or `var === literal`
  # comparison. These should use pattern matching in the function head instead
  # of guards (see `no_guard_equality_for_pattern_match`).
  defp simple_equality_with_literal?({op, _, [left, right]}) when op in [:==, :===] do
    var_and_literal?(left, right) or var_and_literal?(right, left)
  end

  defp simple_equality_with_literal?(_), do: false

  defp var_and_literal?({name, _, ctx}, literal)
       when is_atom(name) and (is_atom(ctx) or is_nil(ctx)) do
    matchable_literal?(literal)
  end

  defp var_and_literal?(_, _), do: false

  # Sourceror wraps literals in :__block__ to carry position metadata.
  defp matchable_literal?({:__block__, _, [val]}), do: matchable_literal?(val)
  defp matchable_literal?(n) when is_number(n), do: true
  defp matchable_literal?(a) when is_atom(a), do: true
  defp matchable_literal?(b) when is_binary(b), do: true
  defp matchable_literal?([]), do: true
  defp matchable_literal?(_), do: false

  # -- patch helpers ---------------------------------------------------------

  defp extract_head_parts({:when, _, [call, guard]}), do: {call, guard}
  defp extract_head_parts(call), do: {call, nil}

  defp extract_branches({:if, _meta, [_condition, clauses]}) when is_list(clauses) do
    do_body = extract_kw_value(clauses, :do)
    else_body = extract_kw_value(clauses, :else)
    {do_body, else_body}
  end

  defp extract_branches({:__block__, _, [expr]}), do: extract_branches(expr)
  defp extract_branches(_), do: {nil, nil}

  defp extract_kw_value(kw, key) do
    case Keyword.get(kw, key) do
      nil ->
        Enum.find_value(kw, fn
          {{:__block__, _, [^key]}, body} -> body
          _ -> nil
        end)

      body ->
        body
    end
  end

  defp combine_guards(nil, new), do: new
  defp combine_guards(existing, new), do: {:and, [], [existing, new]}

  defp build_head(call, nil), do: call
  defp build_head(call, guard), do: {:when, [], [call, guard]}

  # Collect all variable names referenced in an AST subtree.
  defp collect_var_names(ast) do
    {_, names} =
      Macro.prewalk(ast, MapSet.new(), fn
        {name, _, ctx} = node, acc
        when is_atom(name) and (is_atom(ctx) or is_nil(ctx)) and name != :_ ->
          {node, MapSet.put(acc, name)}

        node, acc ->
          {node, acc}
      end)

    names
  end

  # In a function head AST, prefix any variable not in `used_names` with `_`.
  defp underscore_unused_params(head, used_names) do
    Macro.postwalk(head, fn
      {name, meta, ctx} when is_atom(name) and (is_atom(ctx) or is_nil(ctx)) ->
        if name in used_names or name == :_ do
          {name, meta, ctx}
        else
          {:"_#{name}", meta, ctx}
        end

      node ->
        node
    end)
  end
end
