defmodule Credence.Rule.RedundantListGuard do
  @moduledoc """
  Detects redundant `is_list/1` guards on variables already bound by a
  cons pattern (`[head | tail]`).

  ## Why this matters

  The pattern `[head | tail]` destructures an Erlang cons cell, which
  guarantees that `tail` is a list.  Adding `when is_list(tail)` is
  therefore a no-op that clutters the function signature without providing
  any additional safety.

  ## Flagged patterns

  | Pattern                                              | Fix                                   |
  | ---------------------------------------------------- | ------------------------------------- |
  | `def f([h \\| t]) when is_list(t)`                   | `def f([h \\| t])`                    |
  | `def f([h \\| t]) when is_list(t) and is_atom(h)`    | `def f([h \\| t]) when is_atom(h)`    |
  | `def f([_ \\| a], [_ \\| b]) when is_list(a) and …` | Remove each redundant `is_list` call  |
  """

  @behaviour Credence.Rule
  alias Credence.Issue

  @impl true
  def check(ast, _opts) do
    {_ast, issues} =
      Macro.prewalk(ast, [], fn node, issues ->
        case check_node(node) do
          {:ok, new_issues} -> {node, new_issues ++ issues}
          :error -> {node, issues}
        end
      end)

    Enum.reverse(issues)
  end

  # ------------------------------------------------------------
  # NODE MATCHING
  # ------------------------------------------------------------

  # Match def/defp with a `when` guard.
  defp check_node({def_type, _meta, [{:when, when_meta, [fun_head, guard]}, _body]})
       when def_type in [:def, :defp] do
    args = extract_args(fun_head)
    cons_tail_vars = collect_cons_tails(args)
    redundant_vars = find_redundant_is_list(guard, cons_tail_vars)

    case redundant_vars do
      [] ->
        :error

      vars ->
        issues =
          Enum.map(vars, fn var ->
            %Issue{
              rule: :redundant_list_guard,
              message: build_message(var),
              meta: %{line: Keyword.get(when_meta, :line)}
            }
          end)

        {:ok, issues}
    end
  end

  defp check_node(_), do: :error

  # ------------------------------------------------------------
  # ARGUMENT EXTRACTION
  # ------------------------------------------------------------

  defp extract_args({_fun_name, _, args}) when is_list(args), do: args
  defp extract_args(_), do: []

  # ------------------------------------------------------------
  # CONS-TAIL COLLECTION
  #
  # Recursively walk function arguments to find every variable
  # sitting in the tail position of a cons pattern `[_ | var]`.
  # ------------------------------------------------------------

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

  # ------------------------------------------------------------
  # GUARD INSPECTION
  #
  # Walk the guard expression (which may be compound via `and` /
  # `or`) and collect every `is_list(var)` where `var` appears in
  # the set of known cons-tail variables.
  # ------------------------------------------------------------

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

  # ------------------------------------------------------------
  # MESSAGE GENERATION
  # ------------------------------------------------------------

  defp build_message(var) do
    """
    Redundant `when is_list(#{var})` guard.

    The pattern `[_ | #{var}]` already guarantees that `#{var}` is a list.
    Remove the `is_list(#{var})` guard to reduce noise.
    """
  end
end
