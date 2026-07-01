defmodule Credence.Pattern.RedundantListGuard do
  @moduledoc """
  Detects `is_list/1` guards on a cons-pattern tail variable
  (`[head | tail] when is_list(tail)`) that are redundant **under the
  `proper_lists` promise**.

  ## Why this matters

  The pattern `[head | tail]` destructures a cons cell, but it does **not**
  guarantee `tail` is a list: it also matches *improper* lists like `[1 | 2]`,
  where `tail` is a non-list. So `is_list(tail)` is doing real work — it filters
  those out. The guard is only redundant when no improper list can reach the
  clause, i.e. when the caller promises proper lists.

  This rule therefore declares the `proper_lists` assumption and runs only while
  that switch is on (the default). Under `:strict` it does not fire, because
  removing the guard would change behaviour on `[1 | 2]` (the guarded clause
  rejects it and falls through; the unguarded clause matches it).

  ## Flagged patterns

  | Pattern                                              | Fix                                   |
  | ---------------------------------------------------- | ------------------------------------- |
  | `def f([h \\| t]) when is_list(t)`                   | `def f([h \\| t])`                    |
  | `def f([h \\| t]) when is_list(t) and is_atom(h)`    | `def f([h \\| t]) when is_atom(h)`    |
  | `def f([_ \\| a], [_ \\| b]) when is_list(a) and …` | Remove each redundant `is_list` call  |

  ## Bad

      def max_subarray_sum([first | rest]) when is_list(rest) do
        rest
      end

      def merge([h1 | t1], [h2 | t2]) when is_list(t1) and is_list(t2) do
        {t1, t2}
      end

  ## Good

      def max_subarray_sum([first | rest]) do
        rest
      end

      def merge([h1 | t1], [h2 | t2]) do
        {t1, t2}
      end
  """
  use Credence.Pattern.Rule
  alias Credence.Issue

  @impl true
  def assumptions, do: [:proper_lists]

  @impl true
  def check(ast, _opts) do
    cons_index = cons_indices_by_sig(ast)

    {_ast, issues} =
      Macro.prewalk(ast, [], fn node, issues ->
        case check_node(node, cons_index) do
          {:ok, new_issues} -> {node, new_issues ++ issues}
          :error -> {node, issues}
        end
      end)

    Enum.reverse(issues)
  end

  @impl true
  def fix_patches(ast, _opts) do
    cons_index = cons_indices_by_sig(ast)

    Credence.RuleHelpers.patches_from_postwalk(ast, fn
      {def_type, meta, [{:when, when_meta, [fun_head, guard]}, body]} = node
      when def_type in [:def, :defp] ->
        args = extract_args(fun_head)
        cons_tail_vars = collect_cons_tails(args)
        redundant_vars = find_redundant_is_list(guard, cons_tail_vars)

        if redundant_vars != [] and
             guard_load_bearing?(fun_head, meta, args, redundant_vars, cons_index) do
          node
        else
          fix_guarded_clause(
            node,
            def_type,
            meta,
            when_meta,
            fun_head,
            guard,
            body,
            cons_tail_vars
          )
        end

      node ->
        node
    end)
  end

  defp fix_guarded_clause(node, def_type, meta, when_meta, fun_head, guard, body, cons_tail_vars) do
    case find_redundant_is_list(guard, cons_tail_vars) do
      [] ->
        node

      redundant_vars ->
        case simplify_guard(guard, redundant_vars) do
          :always_true ->
            # Entire guard is redundant — remove the `when` clause
            {def_type, meta, [fun_head, body]}

          {:ok, simplified_guard} ->
            # Only some sub-expressions were redundant
            {def_type, meta, [{:when, when_meta, [fun_head, simplified_guard]}, body]}
        end
    end
  end

  # GUARD SIMPLIFICATION
  #
  # Recursively walk a guard expression, removing every
  # `is_list(v)` where `v` is a cons-tail variable.
  #
  # Returns:
  #   :always_true        — the whole expression is trivially true
  #   {:ok, simplified}   — a (possibly smaller) guard expression
  defp simplify_guard(guard, redundant_vars) do
    case guard do
      # is_list(v) where v comes from a cons tail → always true
      {:is_list, _, [{name, _, ctx}]} when is_atom(name) and is_atom(ctx) ->
        if name in redundant_vars, do: :always_true, else: {:ok, guard}

      # A and B
      {:and, meta, [left, right]} ->
        case {simplify_guard(left, redundant_vars), simplify_guard(right, redundant_vars)} do
          {:always_true, :always_true} -> :always_true
          {:always_true, {:ok, r}} -> {:ok, r}
          {{:ok, l}, :always_true} -> {:ok, l}
          {{:ok, l}, {:ok, r}} -> {:ok, {:and, meta, [l, r]}}
        end

      # A or B — if either side is always true, the whole or is true
      {:or, meta, [left, right]} ->
        case {simplify_guard(left, redundant_vars), simplify_guard(right, redundant_vars)} do
          {:always_true, _} -> :always_true
          {_, :always_true} -> :always_true
          {{:ok, l}, {:ok, r}} -> {:ok, {:or, meta, [l, r]}}
        end

      # Anything else: leave unchanged
      other ->
        {:ok, other}
    end
  end

  # Match def/defp with a `when` guard.
  defp check_node({def_type, meta, [{:when, when_meta, [fun_head, guard]}, _body]}, cons_index)
       when def_type in [:def, :defp] do
    args = extract_args(fun_head)
    cons_tail_vars = collect_cons_tails(args)
    redundant_vars = find_redundant_is_list(guard, cons_tail_vars)

    cond do
      redundant_vars == [] ->
        :error

      # Removing the guard widens this clause to also match improper-tail inputs
      # it currently rejects. That is safe under `proper_lists` UNLESS another
      # clause of the same name/arity has a *cons* pattern at the same argument
      # position — a clause written specifically to destructure an improper
      # tail. Then the guard is load-bearing (it routes the improper case to
      # that sibling), the `proper_lists` promise is locally false, and removing
      # it would steal that input. A bare catch-all (`f(_)`) sibling is not such
      # a signal, so the rule still fires there (per the assumption's intent).
      guard_load_bearing?(fun_head, meta, args, redundant_vars, cons_index) ->
        :error

      true ->
        issues =
          Enum.map(redundant_vars, fn var ->
            %Issue{
              rule: :redundant_list_guard,
              message: build_message(var),
              meta: %{line: Keyword.get(when_meta, :line)}
            }
          end)

        {:ok, issues}
    end
  end

  defp check_node(_, _), do: :error

  # `%{{name, arity} => [{line, MapSet(cons_arg_index)}]}` — for every def/defp
  # clause, which argument positions hold a cons (`[_ | _]`) pattern. Lets a
  # candidate clause ask whether a *sibling* clause destructures a cons at the
  # same position (see `guard_load_bearing?/5`). Bodiless heads are 1-element
  # and excluded; they generate no clause.
  defp cons_indices_by_sig(ast) do
    {_ast, map} =
      Macro.prewalk(ast, %{}, fn
        {dt, meta, [head, _body]} = node, acc when dt in [:def, :defp] ->
          case head_sig(head) do
            {name, arity, args} ->
              entry = {Keyword.get(meta, :line) || 0, cons_arg_indices(args)}
              {node, Map.update(acc, {name, arity}, [entry], &[entry | &1])}

            nil ->
              {node, acc}
          end

        node, acc ->
          {node, acc}
      end)

    map
  end

  defp head_sig({:when, _, [{name, _, args} | _guard]}) when is_atom(name) and is_list(args),
    do: {name, length(args), args}

  defp head_sig({name, _, args}) when is_atom(name) and is_list(args),
    do: {name, length(args), args}

  defp head_sig(_), do: nil

  # Top-level argument indices whose pattern contains a cons (`[_ | _]`).
  defp cons_arg_indices(args) do
    args
    |> Enum.with_index()
    |> Enum.filter(fn {arg, _i} -> contains_cons?(arg) end)
    |> Enum.map(fn {_arg, i} -> i end)
    |> MapSet.new()
  end

  defp contains_cons?(arg) do
    {_node, found?} =
      Macro.prewalk(arg, false, fn
        {:|, _, _} = node, _acc -> {node, true}
        node, acc -> {node, acc}
      end)

    found?
  end

  # True when removing the redundant guard is unsafe because a *sibling* clause
  # (same name/arity, different source line) has a cons pattern at one of the
  # argument positions this clause guards with `is_list` — i.e. a clause that
  # can match the improper tail the guard currently filters out.
  defp guard_load_bearing?(fun_head, meta, args, redundant_vars, cons_index) do
    case head_sig(fun_head) do
      {name, arity, _args} ->
        line = Keyword.get(meta, :line) || 0
        guarded = guarded_cons_indices(args, redundant_vars)

        sibling_cons =
          cons_index
          |> Map.get({name, arity}, [])
          |> Enum.reject(fn {l, _idxs} -> l == line end)
          |> Enum.reduce(MapSet.new(), fn {_l, idxs}, acc -> MapSet.union(acc, idxs) end)

        not MapSet.disjoint?(guarded, sibling_cons)

      nil ->
        false
    end
  end

  # Argument indices whose cons tail is one of the redundant (guarded) vars.
  defp guarded_cons_indices(args, redundant_vars) do
    args
    |> Enum.with_index()
    |> Enum.filter(fn {arg, _i} -> cons_tail_in?(arg, redundant_vars) end)
    |> Enum.map(fn {_arg, i} -> i end)
    |> MapSet.new()
  end

  defp cons_tail_in?(arg, redundant_vars) do
    {_node, found?} =
      Macro.prewalk(arg, false, fn
        {:|, _, [_h, {name, _, ctx}]} = node, acc when is_atom(name) and is_atom(ctx) ->
          {node, acc or name in redundant_vars}

        node, acc ->
          {node, acc}
      end)

    found?
  end

  defp extract_args({_fun_name, _, args}) when is_list(args), do: args
  defp extract_args(_), do: []
  # CONS-TAIL COLLECTION
  #
  # Recursively walk function arguments to find every variable
  # sitting in the tail position of a cons pattern `[_ | var]`.
  defp collect_cons_tails(args) do
    {_, vars} =
      Macro.prewalk(args, [], fn
        {:|, _, [_head, {name, _, ctx}]} = node, acc
        when is_atom(name) and is_atom(ctx) ->
          {node, [name | acc]}

        node, acc ->
          {node, acc}
      end)

    Enum.uniq(vars)
  end

  # GUARD INSPECTION
  #
  # Walk the guard expression (which may be compound via `and` /
  # `or`) and collect every `is_list(var)` where `var` appears in
  # the set of known cons-tail variables.
  defp find_redundant_is_list(guard, cons_tail_vars) do
    {_, found} =
      Macro.prewalk(guard, [], fn
        {:is_list, _, [{name, _, ctx}]} = node, acc
        when is_atom(name) and is_atom(ctx) ->
          if name in cons_tail_vars, do: {node, [name | acc]}, else: {node, acc}

        node, acc ->
          {node, acc}
      end)

    Enum.uniq(found)
  end

  defp build_message(var) do
    """
    Redundant `when is_list(#{var})` guard (under the `proper_lists` promise).
    With proper lists, the tail `#{var}` of `[_ | #{var}]` is always a list, so
    the guard never changes which clause matches. Remove it to reduce noise.
    """
  end
end
