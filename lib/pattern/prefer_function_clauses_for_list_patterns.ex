defmodule Credence.Pattern.PreferFunctionClausesForListPatterns do
  @moduledoc """
  Detects a redundant `case` inside a *guarded* function clause that dispatches
  on the same list parameter checked by `is_list/1` in the guard, and promotes
  the `case` clauses to pattern-matching function heads.

  ## Bad

      defmodule TallyPFCFLP do
        def my_fun([], _k), do: 0

        def my_fun(list, k) when is_list(list) and is_integer(k) and k >= 0 do
          case list do
            [] -> 0
            [_single] -> 0
            [h | t] -> h + length(t) + k
          end
        end
      end

  ## Good

      defmodule TallyPFCFLP do
        def my_fun([], _k), do: 0

        def my_fun([_single], k) when is_integer(k) and k >= 0, do: 0

        def my_fun([h | t], k) when is_integer(k) and k >= 0, do: h + length(t) + k
      end

  ## Scope — what it flags

  This rule is the *guarded* counterpart of `no_case_on_param_dispatch` (which
  only handles an **unguarded, single bare-variable** head). It fires only when
  ALL of these hold:

  - The clause is `def`/`defp` with a `when` guard containing `is_list(var)`.
  - The function body is exactly `case var do … end` — no pre/post statements,
    no `rescue`/`catch`/`after`.
  - The `case` has at least 2 clauses, all matching list patterns, none using a
    `^` pin.
  - The `case` is **total over lists**: its guardless, fully-irrefutable list
    clauses cover every possible length (e.g. `[]` + `[h | t]`, or
    `[]` + `[_]` + `[a, b | _]`).

  ## Why these limits (safety)

  Each limit closes a way the rewrite could change the answer:

    * **`is_list` guard + case on that variable.** `is_list` guarantees a list,
      so the `case` only discriminates list *shape*; promoting the patterns to
      heads is the same dispatch.
    * **Totality over lists.** A non-total `case` raises `CaseClauseError` on an
      unmatched list, but the equivalent function heads raise
      `FunctionClauseError` (or fall through to a sibling clause) — a different
      answer. We only fire when the list patterns are exhaustive, so neither
      construct ever fails to match a list.
    * **Body is exactly the case / no `rescue`/`catch`/`after`.** Any extra
      statement would be silently dropped.
    * **No `^` pin.** A pinned `^v` matches the in-scope subject; as a function
      head pattern the variable would be unbound.

  Clause guards and the non-`is_list` part of the head guard are preserved
  verbatim (guard semantics are identical in a `case` clause and a function
  head). The original parameter name is rebound with `pattern = var` whenever
  the body or a guard still refers to it, so nothing is left unbound.

  ## Sibling clauses

  Promoted heads are emitted in place. A promoted head is dropped **only** when
  an earlier, *guardless* sibling clause of the same function has a pattern that
  already subsumes it — in that case both the promoted head and the original
  `case` branch were already dead, so removing it changes nothing. Guarded
  siblings never trigger a drop (their guard may fail, leaving the branch live).
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
              {:defmodule, mod_meta,
               [
                 aliases,
                 [
                   {{:__block__, do_meta, [:do]},
                    {:__block__, block_meta, transform_stmts(stmts)}}
                 ]
               ]}

            single_stmt ->
              case transform_single_stmt(single_stmt) do
                {:ok, new_stmts} ->
                  {:defmodule, mod_meta,
                   [aliases, [{{:__block__, do_meta, [:do]}, {:__block__, [], new_stmts}}]]}

                :no ->
                  node
              end
          end

        # Module with __block__ wrapper
        {:defmodule, mod_meta,
         [aliases, [{{:__block__, do_meta, [:do]}, {:__block__, block_meta, stmts}}]]}
        when is_list(stmts) ->
          {:defmodule, mod_meta,
           [
             aliases,
             [{{:__block__, do_meta, [:do]}, {:__block__, block_meta, transform_stmts(stmts)}}]
           ]}

        # Regular __block__
        {:__block__, meta, stmts} when is_list(stmts) ->
          {:__block__, meta, transform_stmts(stmts)}

        node ->
          node
      end)
    end)
  end

  # Transform a single statement (not wrapped in __block__). With no surrounding
  # block there are no preceding siblings to consider for the safe drop.
  defp transform_single_stmt(
         {def_type, _meta, [{:when, _when_meta, [_fun_head, _guard]}, _body_kw]} = node
       )
       when def_type in [:def, :defp] do
    case convertible(node) do
      {:ok, info} -> {:ok, build_replacement([], info)}
      :no -> :no
    end
  end

  defp transform_single_stmt(_), do: :no

  # ── detection ─────────────────────────────────────────────────────

  # Match def/defp with a `when` guard that contains `is_list(var)`, a body that
  # is exactly `case var do … end`, and a list-total set of case clauses.
  defp convertible({def_type, _meta, [{:when, when_meta, [fun_head, guard]}, body_kw]})
       when def_type in [:def, :defp] and is_list(body_kw) do
    with {:ok, list_var, remaining_guard} <- extract_is_list_guard(guard),
         {:ok, case_body} <- extract_do_body(body_kw),
         {:ok, case_subject, case_clauses} <- unwrap_case(case_body),
         true <- same_var?(case_subject, list_var) and length(case_clauses) >= 2,
         parsed when is_list(parsed) <- parse_case_clauses(case_clauses),
         true <- Enum.all?(parsed, fn {pattern, _, _} -> list_pattern?(pattern) end),
         true <- total_over_lists?(parsed) do
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
      _ -> :no
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
      {:_, _, _} -> true
      _ -> false
    end)
  end

  defp list_pattern?(_), do: false

  # ── totality over lists ───────────────────────────────────────────

  # The guardless, fully-irrefutable list clauses must cover every length: there
  # must be an "open" clause (`[… | tail]`, covering all lengths ≥ its arity) and
  # every shorter length must be covered by a "closed" clause (`[…]`). Clauses
  # with a guard, or whose element/tail patterns are not bare vars/`_`, cannot be
  # relied on to match and are ignored here (but are still emitted as heads).
  defp total_over_lists?(parsed) do
    shapes =
      for {pattern, nil, _body} <- parsed,
          shape = analyze_list_pattern(pattern),
          shape != :other,
          do: shape

    opens = for {:open, n} <- shapes, do: n
    closed = for {:closed, n} <- shapes, into: MapSet.new(), do: n

    case opens do
      [] -> false
      _ -> Enum.all?(0..(Enum.min(opens) - 1)//1, &MapSet.member?(closed, &1))
    end
  end

  # {:closed, n} — matches lists of exactly length n.
  # {:open, n}   — matches lists of length >= n (ends in `| tail_var`).
  # :other       — a refutable element/tail pattern; ignored for totality.
  defp analyze_list_pattern({:__block__, _, [[]]}), do: {:closed, 0}
  defp analyze_list_pattern({:__block__, _, [inner]}), do: analyze_list_pattern(inner)
  defp analyze_list_pattern([]), do: {:closed, 0}

  defp analyze_list_pattern(list) when is_list(list) do
    case List.last(list) do
      {:|, _, [head, tail]} ->
        elements = Enum.drop(list, -1) ++ [head]

        if Enum.all?(elements, &irrefutable_var?/1) and irrefutable_var?(tail),
          do: {:open, length(elements)},
          else: :other

      _ ->
        if Enum.all?(list, &irrefutable_var?/1), do: {:closed, length(list)}, else: :other
    end
  end

  defp analyze_list_pattern(_), do: :other

  # A bare variable or `_` — matches any single element with no refutation.
  defp irrefutable_var?({:__block__, _, [inner]}), do: irrefutable_var?(inner)
  defp irrefutable_var?({name, _, ctx}) when is_atom(name) and is_atom(ctx), do: true
  defp irrefutable_var?(_), do: false

  # ── rewrite ───────────────────────────────────────────────────────

  defp transform_stmts(stmts) do
    stmts
    |> Enum.with_index()
    |> Enum.flat_map(fn
      {{def_type, _meta, [{:when, _when_meta, [_fun_head, _guard]}, _body_kw]} = node, idx}
      when def_type in [:def, :defp] ->
        case convertible(node) do
          {:ok, info} -> build_replacement(Enum.take(stmts, idx), info)
          :no -> [node]
        end

      {node, _idx} ->
        [node]
    end)
  end

  defp build_replacement(preceding_stmts, %{
         def_type: def_type,
         fun_head: fun_head,
         list_var: {var_name, _, _},
         remaining_guard: remaining_guard,
         case_clauses: case_clauses
       }) do
    {fun_name, _fun_meta, original_params} = fun_head

    # Patterns already covered by an earlier *guardless* clause of the same
    # function are dead both before and after the rewrite — safe to drop.
    guardless_before = guardless_heads(preceding_stmts, fun_name)

    Enum.flat_map(case_clauses, fn {pattern, clause_guard, body} ->
      keep_bound? =
        mentions_var?(body, var_name) or mentions_var?(clause_guard, var_name) or
          mentions_var?(remaining_guard, var_name)

      new_params = replace_param(original_params, var_name, pattern, keep_bound?)

      if Enum.any?(guardless_before, &subsumes?(&1, new_params)) do
        []
      else
        combined_guard = combine_guards(clause_guard, remaining_guard)
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

  # Param lists of earlier *guardless* defs of `fun_name`. A guardless head is
  # `{def, _, [{name, _, params}, body]}` — a guarded one has `{:when, …}` in the
  # head position and so does not match here.
  defp guardless_heads(stmts, fun_name) do
    Enum.flat_map(stmts, fn
      {def_type, _, [{^fun_name, _, params}, _body]}
      when def_type in [:def, :defp] and is_list(params) ->
        [params]

      _ ->
        []
    end)
  end

  # Does `general` (an earlier guardless head's params) match everything
  # `specific` (a promoted head's params) matches? True when the lengths agree
  # and, position-by-position, `general` is a bare var/`_` or has an identical
  # pattern shape (up to variable renaming).
  defp subsumes?(general, specific) do
    length(general) == length(specific) and
      Enum.zip(general, specific)
      |> Enum.all?(fn {g, s} -> subsumes_param?(g, s) end)
  end

  defp subsumes_param?(general, specific) do
    case normalize(general) do
      :__var__ -> true
      normalized -> normalized == normalize(specific)
    end
  end

  # Structural normal form: strip metadata and collapse every bound variable and
  # `_` to a single token, so patterns equal up to renaming compare equal.
  defp normalize({:__block__, _, [inner]}), do: normalize(inner)
  defp normalize({name, _, ctx}) when is_atom(name) and is_atom(ctx), do: :__var__
  defp normalize({form, _meta, args}) when is_list(args), do: {normalize(form), normalize(args)}
  defp normalize(list) when is_list(list), do: Enum.map(list, &normalize/1)
  defp normalize({left, right}), do: {normalize(left), normalize(right)}
  defp normalize(other), do: other

  defp mentions_var?(nil, _var), do: false

  defp mentions_var?(ast, var) do
    {_ast, found} =
      Macro.prewalk(ast, false, fn
        {^var, _, ctx} = node, _ when is_atom(ctx) -> {node, true}
        node, acc -> {node, acc}
      end)

    found
  end

  # Replace `var_name` in the parameter list with the clause pattern. When the
  # body or a guard still refers to `var_name` and the pattern does not itself
  # bind it, keep it in scope with `pattern = var_name`.
  defp replace_param(params, var_name, pattern, keep_bound?) do
    Enum.map(params, fn
      {^var_name, _, ctx} when is_atom(ctx) ->
        if keep_bound? and not mentions_var?(pattern, var_name) do
          {:=, [], [pattern, {var_name, [], nil}]}
        else
          pattern
        end

      other ->
        other
    end)
  end

  # Combine case clause guard with remaining function guard
  defp combine_guards(nil, nil), do: nil
  defp combine_guards(clause_guard, nil), do: clause_guard
  defp combine_guards(nil, remaining_guard), do: remaining_guard

  defp combine_guards(clause_guard, remaining_guard),
    do: {:and, [], [clause_guard, remaining_guard]}

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
