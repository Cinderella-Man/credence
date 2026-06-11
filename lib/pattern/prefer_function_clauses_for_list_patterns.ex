defmodule Credence.Pattern.PreferFunctionClausesForListPatterns do
  @moduledoc """
  Detects a redundant `case` inside a guarded function clause that dispatches
  on the same list parameter checked by `is_list/1` in the guard. The case
  clauses can be promoted to pattern-matching function heads, making the code
  more idiomatic and readable.

  ## Bad

      def my_fun([], _k), do: 0
      def my_fun(list, k) when is_list(list) and is_integer(k) and k >= 0 do
        case list do
          [] -> 0
          [_single] -> 0
          [h | t] ->
            # ... complex body
        end
      end

  ## Good

      def my_fun([], _k), do: 0
      def my_fun([_single], k) when is_integer(k) and k >= 0, do: 0
      def my_fun([h | t], k) when is_integer(k) and k >= 0 do
        # ... complex body (without wrapping case)
      end

  ## Scope — what it flags

  This rule fires when ALL of these hold:

  - The function clause is `def`/`defp` with a `when` guard containing
    `is_list(var)`.
  - The function body is exactly `case var do ... end` (no pre/post
    statements).
  - The `case` has at least 2 clauses, all matching on list patterns
    (empty `[]`, cons `[h | t]`, single-element `[_]`, etc.).
  - None of the case clauses use `^` pins (pinning in function heads is
    unbound).
  - The case has no `rescue`/`catch`/`after` — those would be silently
    dropped.

  ## Why these limits (safety)

  - **`is_list` guard + case on same variable.** The `case` is structurally
    redundant with the guard: `is_list` guarantees the value is a list, so
    the case only dispatches on list shape. Promoting the case patterns to
    function heads removes the double dispatch.
  - **No `^` pins.** A pinned variable `^v` in a case clause references the
    in-scope subject; as a function-head pattern the variable would be
    unbound.
  - **Body is exactly the case.** Any extra statement would be silently
    dropped by the rewrite.
  - **List patterns only.** Non-list patterns (tuples, maps, literals) in
    the case are left alone — the rewrite would not be idiomatic.
  """
  use Credence.Pattern.Rule
  alias Credence.Issue
  alias Credence.RuleHelpers

  @impl true
  def check(ast, _opts) do
    {_ast, issues} =
      Macro.prewalk(ast, [], fn node, acc ->
        case convertible(node) do
          {:ok, info} -> {node, [build_issue(info) | acc]}
          :no -> {node, acc}
        end
      end)

    Enum.reverse(issues)
  end

  @impl true
  def fix_patches(ast, opts) do
    source = Keyword.get(opts, :source) || Sourceror.to_string(ast)

    RuleHelpers.patches_from_ast_transform(ast, source, fn ast ->
      Macro.prewalk(ast, fn
        # Module with single def statement (no __block__ wrapper)
        {:defmodule, mod_meta, [aliases, [{{:__block__, do_meta, [:do]}, body}]]} = node ->
          case body do
            {:__block__, block_meta, stmts} when is_list(stmts) ->
              {:defmodule, mod_meta, [aliases, [{{:__block__, do_meta, [:do]}, {:__block__, block_meta, transform_stmts(stmts)}}]]}
            single_stmt ->
              case transform_single_stmt(single_stmt) do
                {:ok, new_stmts} ->
                  {:defmodule, mod_meta, [aliases, [{{:__block__, do_meta, [:do]}, {:__block__, [], new_stmts}}]]}
                :no ->
                  node
              end
          end

        # Module with __block__ wrapper
        {:defmodule, mod_meta, [aliases, [{{:__block__, do_meta, [:do]}, {:__block__, block_meta, stmts}}]]} when is_list(stmts) ->
          {:defmodule, mod_meta, [aliases, [{{:__block__, do_meta, [:do]}, {:__block__, block_meta, transform_stmts(stmts)}}]]}

        # Regular __block__
        {:__block__, meta, stmts} when is_list(stmts) ->
          {:__block__, meta, transform_stmts(stmts)}

        node ->
          node
      end)
    end)
  end

  # Transform a single statement (not wrapped in __block__)
  defp transform_single_stmt({def_type, _meta, [{:when, _when_meta, [_fun_head, _guard]}, _body_kw]} = node)
       when def_type in [:def, :defp] do
    case convertible(node) do
      {:ok, info} -> {:ok, build_replacement([node], info)}
      :no -> :no
    end
  end

  defp transform_single_stmt(_), do: :no

  # ── detection ─────────────────────────────────────────────────────

  # Match def/defp with a `when` guard that contains `is_list(var)`.
  defp convertible({def_type, _meta, [{:when, when_meta, [fun_head, guard]}, body_kw]})
       when def_type in [:def, :defp] and is_list(body_kw) do
    case extract_is_list_guard(guard) do
      {:ok, list_var, remaining_guard} ->
        case extract_do_body(body_kw) do
          {:ok, case_body} ->
            case unwrap_case(case_body) do
              {:ok, case_subject, case_clauses} ->
                if same_var?(case_subject, list_var) and length(case_clauses) >= 2 do
                  case parse_case_clauses(case_clauses) do
                    parsed when is_list(parsed) ->
                      if Enum.all?(parsed, fn {pattern, _, _} -> list_pattern?(pattern) end) do
                        {:ok,
                         %{
                           def_type: def_type,
                           when_meta: when_meta,
                           fun_head: fun_head,
                           list_var: list_var,
                           remaining_guard: remaining_guard,
                           case_clauses: parsed
                         }}
                      else
                        :no
                      end

                    :error ->
                      :no
                  end
                else
                  :no
                end

              _ ->
                :no
            end

          _ ->
            :no
        end

      _ ->
        :no
    end
  end

  defp convertible(_), do: :no

  # Extract the body from a keyword block: [{{:__block__, _, [:do]}, body}]
  defp extract_do_body([{{:__block__, _, [:do]}, body}]), do: {:ok, body}
  defp extract_do_body([{:do, body}]), do: {:ok, body}
  defp extract_do_body(_), do: :error

  # Extract `is_list(var)` from a guard expression, returning the variable
  # and the remaining guard (or nil if nothing remains).
  defp extract_is_list_guard({:is_list, _, [{name, _, ctx} = var]})
       when is_atom(name) and is_atom(ctx) do
    {:ok, var, nil}
  end

  # Guard is `is_list(var) and rest` or `rest and is_list(var)`
  defp extract_is_list_guard({:and, _meta, [left, right]}) do
    case extract_is_list_guard(left) do
      {:ok, var, nil} ->
        {:ok, var, right}

      {:ok, var, remaining} ->
        {:ok, var, {:and, [], [remaining, right]}}

      :error ->
        case extract_is_list_guard(right) do
          {:ok, var, nil} -> {:ok, var, left}
          {:ok, var, remaining} -> {:ok, var, {:and, [], [left, remaining]}}
          :error -> :error
        end
    end
  end

  defp extract_is_list_guard(_), do: :error

  # Check if a variable node matches another variable node by name
  defp same_var?({name, _, ctx1}, {name, _, ctx2})
       when is_atom(name) and is_atom(ctx1) and is_atom(ctx2),
       do: true

  defp same_var?(_, _), do: false

  # Unwrap a case from the function body
  defp unwrap_case({:__block__, _, [inner]}), do: unwrap_case(inner)

  defp unwrap_case({:case, _, [subject, case_kw]}) when is_list(case_kw) do
    case extract_do_body(case_kw) do
      {:ok, clauses} when is_list(clauses) -> {:ok, subject, clauses}
      _ -> :error
    end
  end

  defp unwrap_case(_), do: :error

  # Parse each case clause into {pattern, guard | nil, body}
  defp parse_case_clauses(clauses) do
    Enum.reduce_while(clauses, [], fn clause, acc ->
      case parse_clause(clause) do
        {:ok, parsed} -> {:cont, [parsed | acc]}
        :error -> {:halt, :error}
      end
    end)
    |> case do
      :error -> :error
      reversed -> Enum.reverse(reversed)
    end
  end

  defp parse_clause({:->, _, [[{:when, _, [pattern, guard]}], body]}) do
    if has_pin?(pattern), do: :error, else: {:ok, {pattern, guard, body}}
  end

  defp parse_clause({:->, _, [[pattern], body]}) do
    if has_pin?(pattern), do: :error, else: {:ok, {pattern, nil, body}}
  end

  defp parse_clause(_), do: :error

  defp has_pin?(ast) do
    {_ast, found} =
      Macro.prewalk(ast, false, fn
        {:^, _, _} = node, _ -> {node, true}
        node, acc -> {node, acc}
      end)

    found
  end

  # Check if a pattern is a list pattern (empty list, cons, or single-element)
  defp list_pattern?({:__block__, _, [inner]}), do: list_pattern?(inner)
  # Empty list []
  defp list_pattern?({:__block__, _, [[]]}), do: true
  defp list_pattern?([]), do: true
  # Cons pattern [h | t]
  defp list_pattern?([{:|, _, _} | _]), do: true
  # List literal [a, b, ...] with elements
  defp list_pattern?([_ | _] = elements) do
    Enum.all?(elements, fn
      {:|, _, _} -> true
      {name, _, ctx} when is_atom(name) and is_atom(ctx) -> true
      {name, _, nil} when is_atom(name) -> true
      {:_, _, _} -> true
      _ -> false
    end)
  end

  defp list_pattern?(_), do: false

  # ── rewrite ───────────────────────────────────────────────────────

  defp transform_stmts(stmts) do
    Enum.flat_map(stmts, fn
      {_def_type, _meta, [{:when, _when_meta, [_fun_head, _guard]}, _body_kw]} = node ->
        case convertible(node) do
          {:ok, info} -> build_replacement(stmts, info)
          :no -> [node]
        end

      node ->
        [node]
    end)
  end

  defp build_replacement(all_stmts, %{
         def_type: def_type,
         fun_head: fun_head,
         list_var: list_var,
         remaining_guard: remaining_guard,
         case_clauses: case_clauses
       }) do
    {fun_name, _fun_meta, original_params} = fun_head

    # Collect existing function heads to avoid generating redundant clauses
    existing_heads = collect_existing_heads(all_stmts, fun_name)

    # Replace the list_var in params with the pattern from each case clause
    # Filter out patterns that are already covered by existing function clauses
    Enum.flat_map(case_clauses, fn {pattern, clause_guard, body} ->
      # Build the new parameter list, replacing list_var with the pattern
      new_params = replace_param(original_params, list_var, pattern)

      # Check if this pattern is already covered by an existing function clause
      if pattern_already_covered?(new_params, existing_heads) do
        # Skip this clause - it's already handled by an existing function clause
        []
      else
        # Combine guards: clause guard + remaining function guard
        combined_guard = combine_guards(clause_guard, remaining_guard)

        # Build the function clause
        [build_function_clause(def_type, fun_name, new_params, combined_guard, body)]
      end
    end)
  end

  # Build a single function clause
  defp build_function_clause(def_type, fun_name, params, guard, body) do
    fun_head = {fun_name, [], params}

    # Wrap body in a block to force multi-line rendering
    wrapped_body = ensure_block(body)

    case guard do
      nil ->
        {def_type, [], [fun_head, [{{:__block__, [], [:do]}, wrapped_body}]]}

      guard ->
        {def_type, [],
         [{:when, [], [fun_head, guard]}, [{{:__block__, [], [:do]}, wrapped_body}]]}
    end
  end

  # Ensure the body is wrapped in a block for multi-line rendering
  defp ensure_block({:__block__, _, _} = block), do: block
  defp ensure_block(single_expr), do: {:__block__, [], [single_expr]}

  # Collect existing function heads to avoid generating redundant clauses
  defp collect_existing_heads(stmts, fun_name) do
    Enum.flat_map(stmts, fn
      {def_type, _, [{head_name, _, params} | _]} when def_type in [:def, :defp] ->
        if head_name == fun_name do
          [params]
        else
          []
        end

      {def_type, _, [{:when, _, [{head_name, _, params}, _guard]} | _]}
      when def_type in [:def, :defp] ->
        if head_name == fun_name do
          [params]
        else
          []
        end

      _ ->
        []
    end)
  end

  # Check if a pattern is already covered by an existing function clause
  defp pattern_already_covered?(new_params, existing_heads) do
    Enum.any?(existing_heads, fn existing_params ->
      params_match?(new_params, existing_params)
    end)
  end

  # Check if two parameter lists match (considering wildcards)
  defp params_match?(new_params, existing_params) do
    length(new_params) == length(existing_params) and
      Enum.zip(new_params, existing_params)
      |> Enum.all?(fn {new, existing} -> param_match?(new, existing) end)
  end

  # Check if two individual parameters match
  # Wildcards match anything
  defp param_match?(_, {:_, _, _}), do: true
  defp param_match?(_, {:_k, _, _}), do: true
  # Empty list patterns match
  defp param_match?({:__block__, _, [[]]}, {:__block__, _, [[]]}), do: true
  defp param_match?([], []), do: true
  # Same variable names match
  defp param_match?({name, _, ctx1}, {name, _, ctx2})
       when is_atom(name) and is_atom(ctx1) and is_atom(ctx2),
       do: true
  # Default: no match
  defp param_match?(_, _), do: false

  # Replace a specific variable in the parameter list with a pattern
  defp replace_param(params, {var_name, _, _}, pattern) do
    Enum.map(params, fn
      {^var_name, _, ctx} when is_atom(ctx) -> pattern
      other -> other
    end)
  end

  # Combine case clause guard with remaining function guard
  defp combine_guards(nil, nil), do: nil
  defp combine_guards(clause_guard, nil), do: clause_guard
  defp combine_guards(nil, remaining_guard), do: remaining_guard
  defp combine_guards(clause_guard, remaining_guard), do: {:and, [], [clause_guard, remaining_guard]}

  # ── issue ─────────────────────────────────────────────────────────

  defp build_issue(%{when_meta: when_meta, def_type: def_type}) do
    %Issue{
      rule: :prefer_function_clauses_for_list_patterns,
      message:
        "Redundant `case` inside a guarded #{def_type} clause. " <>
          "The case dispatches on the same list parameter checked by `is_list/1` in the guard. " <>
          "Promote the case patterns to function heads instead.",
      meta: %{line: Keyword.get(when_meta, :line)}
    }
  end
end
