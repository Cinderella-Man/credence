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

  # Comparison operators are total over Elixir terms: they never raise and
  # always return a strict boolean. This is what makes a guard rewrite safe.
  @comparison_ops [:==, :!=, :===, :!==, :<, :>, :<=, :>=]

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
  defp check_node({def_kind, meta, [head, body_kw]})
       when def_kind in [:def, :defp] and is_list(body_kw) do
    body = extract_body(body_kw)

    case extract_if_else(body) do
      {:ok, condition} ->
        if guard_eligible?(condition) and not simple_equality_with_literal?(condition) and
             not head_has_bitstring?(head),
           do: {:ok, meta[:line]},
           else: :error

      :error ->
        :error
    end
  end

  defp check_node(_), do: :error

  # A function head containing a binary/bitstring pattern (`<<c::utf8, rest::binary>>`)
  # is skipped: the clause-splitting rewrite re-renders the head and
  # `underscore_unused_params/2` mistakes the segment type specifiers (`utf8`,
  # `binary`, …) for unused variables, underscoring them into `_utf8`/`_binary`
  # — invalid specifiers that don't compile (the reverted bug).
  defp head_has_bitstring?(head_ast) do
    {_node, found?} =
      Macro.prewalk(head_ast, false, fn
        {:<<>>, _, _} = node, _acc -> {node, true}
        node, acc -> {node, acc}
      end)

    found?
  end

  defp try_build_patch({def_kind, _meta, [head_ast, body_kw]} = node)
       when def_kind in [:def, :defp] and is_list(body_kw) do
    body = extract_body(body_kw)

    case extract_if_else(body) do
      {:ok, condition} ->
        if guard_eligible?(condition) and not simple_equality_with_literal?(condition) and
             not head_has_bitstring?(head_ast) do
          {call, existing_guard} = extract_head_parts(head_ast)
          {do_body, else_body} = extract_branches(body)

          range = Sourceror.get_range(node)

          # Check if the condition contains var == var equalities between
          # parameters. When it does, we must use a `when` guard instead
          # of renaming variables (which would create unreachable clauses).
          var_equalities = extract_var_equalities(condition, call)
          has_var_equalities? = length(var_equalities) > 0

          guard_names =
            if existing_guard, do: collect_var_names(existing_guard), else: MapSet.new()

          # Build first clause: defp call when condition do do_body end
          # For var == var conditions, keep the original condition as a guard.
          first_combined_guard = combine_guards(existing_guard, condition)
          first_guard = first_combined_guard

          first_used =
            guard_names
            |> MapSet.union(collect_var_names(do_body))
            |> MapSet.union(collect_var_names(first_guard))

          first_head = build_head(underscore_unused_params(call, first_used), first_guard)
          first_clause = {def_kind, [], [first_head, [do: do_body]]}
          first_text = Sourceror.to_string(first_clause)

          # Build second clause: defp call [when existing_guard] do else_body end
          # For var == var equalities, the second clause is the catch-all
          # (no guard from the if condition). Otherwise, negate the guard.
          second_guard =
            if has_var_equalities? do
              # Keep only the existing guard (if any) for the else branch
              existing_guard
            else
              existing_guard
            end

          second_used =
            guard_names
            |> MapSet.union(collect_var_names(else_body))
            |> MapSet.union(collect_var_names(second_guard))

          second_head = build_head(underscore_unused_params(call, second_used), second_guard)
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
      nil ->
        Enum.any?(kw, fn
          {{:__block__, _, [k]}, _} -> k == key
          _ -> false
        end)

      _ ->
        true
    end
  end

  # Guard-eligibility check — deliberately narrowed to the *safe core* where a
  # guard rewrite gives the exact same answer as the original `if/else`.
  #
  # `if` and a `when` guard diverge on two things:
  #   * a guard swallows errors (treats a raise as "no match") while `if`
  #     propagates them — so any sub-expression that can raise (arithmetic,
  #     `rem`/`div` by zero, `length`/`hd`/`elem`/… on the wrong type) is unsafe;
  #   * a guard succeeds only on the strict boolean `true`, while `if` takes the
  #     do-branch on any truthy value — so a bare variable (`if flag`) or
  #     `not`/`and`/`or` over a non-boolean is unsafe.
  #
  # We therefore accept ONLY boolean-valued conditions built from:
  #   * comparison operators over variable/literal leaves (total, never raise),
  #   * type-check guards (`is_*`, never raise), and
  #   * `and`/`or`/`not` combining such boolean sub-conditions.
  # Everything else (arithmetic, guard builtins, `in`, bare variables) is left
  # alone.
  defp guard_eligible?(node), do: bool_guard?(node)

  # Unwrap Sourceror single-expression blocks: {:__block__, _, [expr]}
  defp bool_guard?({:__block__, _, [expr]}), do: bool_guard?(expr)

  # Comparison over leaves — the only operators that never raise.
  defp bool_guard?({op, _, [left, right]}) when op in @comparison_ops,
    do: value_guard?(left) and value_guard?(right)

  # Boolean combinators over boolean sub-conditions.
  defp bool_guard?({op, _, [left, right]}) when op in [:and, :or],
    do: bool_guard?(left) and bool_guard?(right)

  defp bool_guard?({:not, _, [arg]}), do: bool_guard?(arg)

  # Type-check guards (is_nil, is_integer, etc.) over leaves.
  defp bool_guard?({fn_name, _, args})
       when fn_name in @guard_type_checks and is_list(args),
       do: Enum.all?(args, &value_guard?/1)

  defp bool_guard?(_), do: false

  # A "leaf" usable as a comparison/type-check argument: a variable or a
  # literal. Both are evaluation-safe (no raise) inside an `if` condition.
  defp value_guard?({:__block__, _, [expr]}), do: value_guard?(expr)

  defp value_guard?({name, _, ctx})
       when is_atom(name) and (is_atom(ctx) or is_nil(ctx)),
       do: true

  defp value_guard?(lit)
       when is_number(lit) or is_atom(lit) or is_boolean(lit) or is_binary(lit),
       do: true

  defp value_guard?(_), do: false

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

  # -- var-equality detection -----------------------------------------------

  # Extract var == var equalities from the guard condition where both sides
  # appear as parameters in the function head. Returns [{left_name, right_name}].
  defp extract_var_equalities(condition, call) do
    param_names = collect_param_names(call)

    {_ast, equalities} =
      Macro.prewalk(condition, [], fn
        {op, _, [left, right]} = node, acc when op in [:==, :===] ->
          case {var_name(left), var_name(right)} do
            {l, r} when is_atom(l) and is_atom(r) and l != r ->
              if l in param_names and r in param_names do
                {node, [{l, r} | acc]}
              else
                {node, acc}
              end
            _ ->
              {node, acc}
          end

        node, acc ->
          {node, acc}
      end)

    Enum.uniq(equalities)
  end

  # Collect all parameter variable names from a function call head.
  defp collect_param_names(call) do
    {_, names} =
      Macro.prewalk(call, MapSet.new(), fn
        {name, _, ctx} = node, acc
        when is_atom(name) and (is_atom(ctx) or is_nil(ctx)) and name != :_ ->
          {node, MapSet.put(acc, name)}
        node, acc ->
          {node, acc}
      end)
    names
  end

  # Extract the variable name from an AST node, handling __block__ wrappers.
  defp var_name({name, _, ctx}) when is_atom(name) and (is_atom(ctx) or is_nil(ctx)), do: name
  defp var_name({:__block__, _, [expr]}), do: var_name(expr)
  defp var_name(_), do: nil

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
