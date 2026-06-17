defmodule Credence.Pattern.PreferPatternMatchOverConditionalInRecursiveCount do
  @moduledoc """
  Readability rule: Detects recursive function clauses that use an `if`/`else`
  to conditionally count matches, when the same logic is more idiomatically
  expressed via multiple pattern-matching function clauses with a guard.

  The rewrite uses `when head == target` (not pattern-match `===`) to preserve
  the original `==` semantics, which matter for int/float value equality.

  ## Bad

      def count_until([head | tail], target, stop) do
        count = if head == target, do: 1, else: 0
        count + count_until(tail, target, stop)
      end

  ## Good

      def count_until([head | tail], target, stop) when head == target,
        do: 1 + count_until(tail, target, stop)

      def count_until([_ | tail], target, stop),
        do: count_until(tail, target, stop)
  """
  use Credence.Pattern.Rule
  alias Credence.Issue
  alias Credence.RuleHelpers

  @impl true
  def check(ast, _opts) do
    {_ast, issues} =
      Macro.prewalk(ast, [], fn node, acc ->
        case extract_fixable(node) do
          {:ok, info} -> {node, [build_issue(info) | acc]}
          :no -> {node, acc}
        end
      end)

    Enum.reverse(issues)
  end

  @impl true
  def fix_patches(ast, _opts) do
    {_ast, patches} =
      Macro.prewalk(ast, [], fn node, acc ->
        case extract_fixable(node) do
          {:ok, info} -> {node, [build_patch(node, info) | acc]}
          :no -> {node, acc}
        end
      end)

    Enum.reverse(patches)
  end

  # ── detection ───────────────────────────────────────────────────────────

  # Matches a `def` clause whose:
  #   - first parameter is `[head_var | tail_var]`
  #   - body has two expressions:
  #     1. `count = if head_var == other_var, do: 1, else: 0`
  #     2. `count + recursive_call(tail_var, ...)`
  # where `recursive_call` calls the same function with `tail_var` as first arg.
  defp extract_fixable({:def, meta, [{name, _, params} | rest]})
       when is_atom(name) and is_list(params) and length(params) >= 2 and is_list(rest) do
    [first_param | _] = params

    with {:ok, head_var, tail_var} <- unwrap_cons(first_param),
         {:ok, body_kw} <- extract_body_kw(rest),
         {:ok, body} <- extract_do_body(body_kw),
         {:ok, count_var, cond_var, op} <- extract_count_if(body, head_var),
         true <- safe_two_clause_recursion?(body, name, tail_var, count_var, params) do
      {:ok,
       %{
         line: Keyword.get(meta, :line),
         name: name,
         op: op,
         head_var: head_var,
         tail_var: tail_var,
         cond_var: cond_var,
         count_var: count_var,
         params: collect_params(body, name, tail_var, params)
       }}
    else
      _ -> :no
    end
  end

  defp extract_fixable(_), do: :no

  # Extract body_kw from the def node's children after the function head.
  defp extract_body_kw([body_kw]) when is_list(body_kw), do: {:ok, body_kw}
  defp extract_body_kw(_), do: :error

  # Unwrap `[h | t]` pattern (Sourceror wraps list in :__block__)
  defp unwrap_cons({:__block__, _, [[{:|, _, [{h, _, nil}, {t, _, nil}]}]]})
       when is_atom(h) and is_atom(t),
       do: {:ok, h, t}

  defp unwrap_cons(_), do: :error

  # Extract the `do:` body from a keyword body list
  defp extract_do_body(body_kw) when is_list(body_kw) do
    Enum.find_value(body_kw, :error, fn
      {{:__block__, _, [:do]}, body} -> {:ok, body}
      _ -> nil
    end)
  end

  # Extract `count = if head == other, do: 1, else: 0` from the body.
  # Returns {:ok, count_name, cond_name, op} or :error.
  defp extract_count_if({:__block__, _meta, stmts}, head_name) when is_list(stmts) do
    case stmts do
      [{:=, _, [{count_name, _, nil}, if_expr]} | _] ->
        case extract_if_eq_one_zero(if_expr, head_name) do
          {:ok, cond_name, op} -> {:ok, count_name, cond_name, op}
          :error -> :error
        end

      _ ->
        :error
    end
  end

  defp extract_count_if(_, _), do: :error

  # Matches `if head <op> other, do: 1, else: 0` where op is == or ===
  defp extract_if_eq_one_zero(
         {:if, _if_meta,
          [
            {op, _, [{h_name, _, nil}, {c_name, _, nil}]},
            [
              {{:__block__, _, [:do]}, {:__block__, _, [1]}},
              {{:__block__, _, [:else]}, {:__block__, _, [0]}}
            ]
          ]},
         head_name
       )
       when op in [:==, :===] and h_name == head_name and is_atom(c_name),
       do: {:ok, c_name, op}

  defp extract_if_eq_one_zero(_, _), do: :error

  # The detection is deliberately narrowed to the one shape we can rewrite with
  # an exact-same-answer guarantee:
  #
  #   * the body is EXACTLY two statements — the `count = if …` assignment and
  #     the `count + fn(tail, …)` tail call. Any extra statement in between (a
  #     side effect, another binding) would be silently dropped by the rewrite,
  #     so we refuse to fire.
  #   * the recursive call's arguments after `tail` are the SAME simple
  #     variables as the clause's parameters after the head. The replacement
  #     reuses those argument nodes both as the new clause heads and as the
  #     recursive calls, so when they differ (e.g. `fn(tail, acc + 1)`) the
  #     generated head `fn([h | t], acc + 1)` is not a valid pattern. Requiring
  #     equality keeps both roles correct.
  defp safe_two_clause_recursion?(body, name, tail_var, count_var, params) do
    with {:__block__, _, [_assign, last]} <- body,
         {:+, _,
          [
            {^count_var, _, nil},
            {^name, _, [{^tail_var, _, nil} | rest_args]}
          ]} <- last,
         {:ok, rest_names} <- simple_var_names(rest_args),
         {:ok, param_names} <- simple_var_names(tl(params)) do
      rest_names == param_names
    else
      _ -> false
    end
  end

  # Map a list of AST nodes to their variable names, but only when every node is
  # a plain unqualified variable (`{name, _, nil}`). Anything else (a literal,
  # an expression, a complex pattern) returns :error so the caller bails out.
  defp simple_var_names(nodes) do
    Enum.reduce_while(nodes, {:ok, []}, fn
      {n, _, nil}, {:ok, acc} when is_atom(n) -> {:cont, {:ok, [n | acc]}}
      _, _ -> {:halt, :error}
    end)
    |> case do
      {:ok, names} -> {:ok, Enum.reverse(names)}
      :error -> :error
    end
  end

  # Collect the full parameter list for the replacement clauses.
  defp collect_params(body, name, _tail_var, original_params) do
    last = last_expr(body)

    case last do
      {:+, _, [_, {^name, _, [_tail | rest_args]}]} ->
        [hd(original_params) | rest_args]

      _ ->
        original_params
    end
  end

  defp last_expr({:__block__, _, stmts}) when is_list(stmts), do: List.last(stmts)
  defp last_expr(single), do: single

  # ── issue ───────────────────────────────────────────────────────────────

  defp build_issue(%{line: line, name: name}) do
    %Issue{
      rule: :prefer_pattern_match_over_conditional_in_recursive_count,
      message:
        "Recursive count via `if #{name}` should use pattern-matching clauses " <>
          "instead of an `if` conditional.",
      meta: %{line: line}
    }
  end

  # ── rewrite ─────────────────────────────────────────────────────────────

  defp build_patch(original_node, info) do
    %{
      name: name,
      op: op,
      head_var: head_var,
      tail_var: tail_var,
      cond_var: cond_var,
      params: params
    } = info

    range = Sourceror.get_range(original_node)
    remaining = tl(params)

    # Clause 1: guarded match — [head | tail] when head == target
    # We keep the original head_var and add a guard `when head == target`
    # to preserve == semantics (pattern match would use === which diverges
    # for int/float: 1 == 1.0 is true but 1 === 1.0 is false).
    guard_head =
      {:__block__, [],
       [
         [
           {:|, [],
            [
              {head_var, [], nil},
              {tail_var, [], nil}
            ]}
         ]
       ]}

    guard_call = {name, [], [guard_head | remaining]}
    guard = {op, [], [{head_var, [], nil}, {cond_var, [], nil}]}
    when_clause = {:when, [], [guard_call, guard]}

    guard_body =
      {:+, [], [{:__block__, [token: "1"], [1]}, {name, [], [{tail_var, [], nil} | remaining]}]}

    guard_clause = {:def, [], [when_clause, [{{:__block__, [], [:do]}, guard_body}]]}

    # Clause 2: catch-all — [_ | tail], just recurse
    catch_head =
      {:__block__, [],
       [
         [
           {:|, [],
            [
              {:_, [], nil},
              {tail_var, [], nil}
            ]}
         ]
       ]}

    catch_call = {name, [], [catch_head | remaining]}
    catch_body = {name, [], [{tail_var, [], nil} | remaining]}
    catch_clause = {:def, [], [catch_call, [{{:__block__, [], [:do]}, catch_body}]]}

    change =
      RuleHelpers.render_replacement(guard_clause, range) <>
        "\n" <>
        RuleHelpers.render_replacement(catch_clause, range)

    %{range: range, change: change}
  end
end
