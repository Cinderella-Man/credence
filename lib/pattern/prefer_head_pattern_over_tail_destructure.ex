defmodule Credence.Pattern.PreferHeadPatternOverTailDestructure do
  @moduledoc """
  Detects patterns where a cons cell's tail in a function head is immediately
  destructured in the body to extract its head, when the destructuring could
  be combined into a single pattern match in the function clause head.

  ## Bad

      def process([head | tail]) do
        [first | _] = tail
        {head, first}
      end

  ## Good

      def process([head, first | _rest]) do
        {head, first}
      end

  The anti-pattern introduces an intermediate binding that can be eliminated
  by expanding the cons pattern to include the destructured element directly.
  The fix only fires when:

  * The tail variable from the cons pattern is only used in the one
    destructuring binding — it is not referenced elsewhere in the body,
    guard, or other parameters.
  * The inner destructuring discards its own tail (`_` only).
  * The binding is not the last statement in the body (removing it must
    not change the return value).

  ## Behaviour note — the fix narrows the clause's domain

  Combining the head pattern (`[head, first | _rest]`) rejects a single-element
  list that the old head (`[head | tail]`) accepted-then-`MatchError`'d on when
  the body's `[first | _] = tail` ran against `[]`. That is behaviour-preserving
  ONLY when a rejected one-element list would still raise rather than fall through
  to a *later* clause of the same function. So the rule fires **only on the last
  clause of its name/arity**: with no later clause to catch it, a one-element list
  raises under both shapes (old: `MatchError` at the body binding; new:
  `FunctionClauseError` at the head), and every input that *returned* a value is
  unchanged. A clause followed by another clause of the same name/arity (e.g. a
  `[x]` or catch-all) is left alone — narrowing it there would silently change
  dispatch. Recursive functions whose recursive clause is last still qualify.
  """

  use Credence.Pattern.Rule
  alias Credence.Issue
  alias Credence.RuleHelpers

  @impl true
  def check(ast, _opts) do
    last = last_clause_lines(ast)

    {_ast, issues} =
      Macro.prewalk(ast, [], fn node, acc ->
        case plan_clause(node, last) do
          {:plan, clause_issues, _new_def} -> {node, acc ++ clause_issues}
          :skip -> {node, acc}
        end
      end)

    issues
  end

  @impl true
  def fix_patches(ast, _opts) do
    last = last_clause_lines(ast)

    transformed =
      Macro.prewalk(ast, fn node ->
        case plan_clause(node, last) do
          {:plan, _issues, new_def} -> new_def
          :skip -> node
        end
      end)

    RuleHelpers.patches_from_diff(ast, transformed)
  end

  # --- dispatch safety: only the LAST clause of a name/arity may be narrowed ---
  #
  # Folding the tail into the head narrows the clause's domain: a one-element list
  # that the old head `[a | b]` accepted-then-crashed on no longer matches the new
  # head `[a, c | _]`. That is behaviour-preserving ONLY if there is no *later*
  # clause of the same name/arity for the one-element list to fall through to —
  # otherwise the old code raised (MatchError) while the new code silently
  # dispatches to that later clause. So we fire only on the last clause of its
  # name/arity (recursive `base first, recursive last` functions still qualify;
  # a clause followed by a `[x]`/catch-all does not).
  defp last_clause_lines(ast) do
    {_ast, acc} =
      Macro.prewalk(ast, %{}, fn
        {kind, meta, [head, body_kw]} = node, acc
        when kind in [:def, :defp] and is_list(body_kw) ->
          case clause_key(head) do
            {:ok, key} -> {node, Map.update(acc, key, line_of(meta), &max(&1, line_of(meta)))}
            :skip -> {node, acc}
          end

        node, acc ->
          {node, acc}
      end)

    acc
  end

  defp clause_key(head) do
    call =
      case head do
        {:when, _, [c, _]} -> c
        c -> c
      end

    case call do
      {name, _, params} when is_atom(name) and is_list(params) -> {:ok, {name, length(params)}}
      {name, _, ctx} when is_atom(name) and is_atom(ctx) -> {:ok, {name, 0}}
      _ -> :skip
    end
  end

  defp line_of(meta), do: Keyword.get(meta, :line, 0)

  # --- shared clause planner: drives both check and fix so they always agree ---

  defp plan_clause({kind, meta, [head, body_kw]} = node, last)
       when kind in [:def, :defp] and is_list(body_kw) do
    with true <- last_clause?(node, last),
         {:ok, body} <- RuleHelpers.extract_do_body(body_kw),
         {:ok, call, guard} <- split_head(head),
         {fn_name, fn_meta, params} when is_list(params) <- call do
      taken = collect_var_names({kind, meta, [head, body_kw]})

      results =
        params
        |> Enum.with_index()
        |> Enum.flat_map(fn {param, idx} ->
          case find_tail_destructure(param, body, guard, params, idx) do
            {:ok, outer_head, tail_var, inner_head, binding_node} ->
              [{idx, outer_head, tail_var, inner_head, binding_node}]

            :skip ->
              []
          end
        end)

      if results == [] do
        :skip
      else
        # Apply body fixes (remove bindings)
        new_body =
          Enum.reduce(results, body, fn {_, _, _, _, binding_node}, b ->
            remove_top_level_binding(b, binding_node)
          end)

        # Build new params
        new_params =
          params
          |> Enum.with_index()
          |> Enum.map(fn {param, idx} ->
            case Enum.find(results, fn {i, _, _, _, _} -> i == idx end) do
              {_, outer_head, _, inner_head, _} ->
                build_new_cons(param, outer_head, inner_head, taken)

              nil ->
                param
            end
          end)

        new_call = {fn_name, fn_meta, new_params}
        new_head = rebuild_head(new_call, guard)
        new_def = {kind, meta, [new_head, RuleHelpers.replace_do_body(body_kw, new_body)]}

        issues =
          Enum.map(results, fn {_, outer_head, tail_var, _, binding_node} ->
            build_issue(outer_head, tail_var, binding_node)
          end)

        {:plan, issues, new_def}
      end
    else
      _ -> :skip
    end
  end

  defp plan_clause(_, _), do: :skip

  # The clause is eligible only if it is the last (highest source line) clause of
  # its name/arity — see `last_clause_lines/1`.
  defp last_clause?({_kind, meta, [head, _body]}, last) do
    case clause_key(head) do
      {:ok, key} -> Map.get(last, key) == line_of(meta)
      :skip -> false
    end
  end

  # --- detection ---

  # Looks for a cons pattern [outer_head | tail_var] in the parameter, where
  # tail_var is immediately destructured as [inner_head | _] = tail_var in
  # the body. Only fires when inner_head is a simple variable and the inner
  # tail is `_` (anonymous).
  defp find_tail_destructure(param, body, guard, params, idx) do
    with {:ok, outer_head, tail_var} <- extract_cons_param(param),
         false <- underscore?(tail_var),
         {:ok, inner_head, inner_tail, binding_node} <-
           find_top_level_cons_binding(body, tail_var),
         true <- underscore?(inner_tail),
         true <- simple_var?(inner_head),
         true <- body_allows_removal?(body, binding_node),
         true <- tail_var_safe?(body, binding_node, tail_var, guard, params, idx) do
      {:ok, outer_head, tail_var, inner_head, binding_node}
    else
      _ -> :skip
    end
  end

  # Extract head and tail from a cons pattern parameter.
  # Sourceror wraps bracketed patterns in :__block__.
  defp extract_cons_param({:__block__, _, [[{:|, _, [head, tail]}]]}) do
    {:ok, head, tail}
  end

  defp extract_cons_param({:|, _, [head, tail]}) do
    {:ok, head, tail}
  end

  defp extract_cons_param(_), do: :skip

  # Find a top-level binding `[inner_head | inner_tail] = tail_var` in the body.
  # Matches on the variable NAME atom (not the full AST node) because the same
  # variable in different source locations carries different Sourceror metadata.
  defp find_top_level_cons_binding({:__block__, _, statements}, tail_var)
       when is_list(statements) do
    {tail_name, _, _} = tail_var

    Enum.find_value(statements, :skip, fn stmt ->
      case stmt do
        {:=, _, [lhs, {^tail_name, _, ctx}]} when is_atom(ctx) ->
          case extract_cons_pattern(lhs) do
            {:ok, inner_head, inner_tail} -> {:ok, inner_head, inner_tail, stmt}
            :skip -> nil
          end

        _ ->
          nil
      end
    end)
  end

  defp find_top_level_cons_binding(body, tail_var) do
    {tail_name, _, _} = tail_var

    case body do
      {:=, _, [lhs, {^tail_name, _, ctx}]} when is_atom(ctx) ->
        case extract_cons_pattern(lhs) do
          {:ok, inner_head, inner_tail} -> {:ok, inner_head, inner_tail, body}
          :skip -> :skip
        end

      _ ->
        :skip
    end
  end

  # Extract head and tail from a cons pattern on the LHS of a binding.
  defp extract_cons_pattern({:__block__, _, [[{:|, _, [head, tail]}]]}) do
    {:ok, head, tail}
  end

  defp extract_cons_pattern({:|, _, [head, tail]}) do
    {:ok, head, tail}
  end

  defp extract_cons_pattern(_), do: :skip

  defp simple_var?({name, _, ctx}) when is_atom(name) and is_atom(ctx), do: true
  defp simple_var?(_), do: false

  defp underscore?({:_, _, _}), do: true
  defp underscore?(_), do: false

  # The body must have more than one statement and the binding must not be
  # the last one (removing the last statement would change the return value).
  defp body_allows_removal?({:__block__, _meta, statements}, binding_node)
       when is_list(statements) and length(statements) > 1 do
    Enum.any?(statements, &(&1 == binding_node)) and
      List.last(statements) != binding_node
  end

  defp body_allows_removal?(_, _), do: false

  # The tail variable must not be used anywhere except in the one binding.
  defp tail_var_safe?(body, binding_node, tail_var, guard, params, idx) do
    body_without = remove_top_level_binding(body, binding_node)

    other_params_use? =
      params
      |> Enum.with_index()
      |> Enum.any?(fn {p, i} -> i != idx and var_used?(p, tail_var) end)

    not (var_used?(body_without, tail_var) or
           guard_uses?(guard, tail_var) or
           other_params_use?)
  end

  # --- fix helpers ---

  # Build the new cons pattern as a bare list (no __block__ wrapper).
  # patches_from_diff compares this against the original __block__-wrapped
  # pattern and emits a patch covering the full bracket range.
  defp build_new_cons(_original_param, outer_head, inner_head, taken) do
    new_tail_name = fresh_name(:_rest, taken)
    new_tail = {new_tail_name, [], nil}
    [outer_head, {:|, [], [inner_head, new_tail]}]
  end

  defp fresh_name(base, taken) do
    if MapSet.member?(taken, base) do
      Enum.find_value(1..1000, fn i ->
        candidate = String.to_atom("#{base}#{i}")
        if MapSet.member?(taken, candidate), do: nil, else: candidate
      end)
    else
      base
    end
  end

  defp remove_top_level_binding({:__block__, meta, statements}, binding_node)
       when is_list(statements) do
    {:__block__, meta, Enum.reject(statements, &(&1 == binding_node))}
  end

  defp remove_top_level_binding(body, binding_node) do
    if body == binding_node, do: {:__block__, [], []}, else: body
  end

  # --- head / guard plumbing ---

  defp split_head({:when, _wmeta, [call, guard]} = _head), do: {:ok, call, {:guard, guard}}
  defp split_head(call), do: {:ok, call, :no_guard}

  defp rebuild_head(new_call, :no_guard), do: new_call
  defp rebuild_head(new_call, {:guard, guard}), do: {:when, [], [new_call, guard]}

  defp guard_uses?(:no_guard, _var), do: false
  defp guard_uses?({:guard, guard}, var), do: var_used?(guard, var)

  # --- var helpers ---

  defp var_used?(ast, var) do
    {name, _, _} = var

    {_ast, found?} =
      Macro.prewalk(ast, false, fn
        {^name, _, ctx} = node, _acc when is_atom(ctx) -> {node, true}
        node, acc -> {node, acc}
      end)

    found?
  end

  defp collect_var_names(ast) do
    {_ast, names} =
      Macro.prewalk(ast, MapSet.new(), fn
        {name, _, ctx} = node, acc when is_atom(name) and is_atom(ctx) and name != :_ ->
          {node, MapSet.put(acc, name)}

        node, acc ->
          {node, acc}
      end)

    names
  end

  # --- issue ---

  defp build_issue(_outer_head, tail_var, binding_node) do
    {tail_name, _, _} = tail_var

    line =
      case binding_node do
        {_, meta, _} when is_list(meta) -> Keyword.get(meta, :line)
        _ -> nil
      end

    %Issue{
      rule: :prefer_head_pattern_over_tail_destructure,
      message:
        "`#{tail_name}` is immediately destructured as `[head | _] = #{tail_name}`. " <>
          "Fold the destructured element into the function clause head pattern instead.",
      meta: %{line: line}
    }
  end
end
