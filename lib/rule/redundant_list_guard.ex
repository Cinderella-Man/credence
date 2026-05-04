defmodule Credence.Rule.RedundantListGuard do
  @moduledoc """
  Detects redundant `is_list/1` guards on variables already bound by a
  cons pattern `[head | tail]`).

  ## Why this matters

  The pattern `[head | tail]` destructures a cons cell. While technically
  `tail` could be a non-list value (creating an improper list), in practice
  almost all Elixir code works with proper lists, making `is_list(tail)`
  guards on cons-tail variables redundant noise.

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
  use Credence.Rule
  alias Credence.Issue

  @impl true
  def fixable?, do: true

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

  @impl true
  def fix(source, _opts) do
    source
    |> Sourceror.parse_string!()
    |> Macro.postwalk(fn
      {def_type, meta, [{:when, when_meta, [fun_head, guard]}, body]} = node
      when def_type in [:def, :defp] ->
        args = extract_args(fun_head)
        cons_tail_vars = collect_cons_tails(args)

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

      node ->
        node
    end)
    |> Sourceror.to_string()
  end

  # ------------------------------------------------------------
  # GUARD SIMPLIFICATION
  #
  # Recursively walk a guard expression, removing every
  # `is_list(v)` where `v` is a cons-tail variable.
  #
  # Returns:
  #   :always_true        — the whole expression is trivially true
  #   {:ok, simplified}   — a (possibly smaller) guard expression
  # ------------------------------------------------------------
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

  defp build_message(var) do
    """
    Redundant `when is_list(#{var})` guard.
    The pattern `[_ | #{var}]` already guarantees that `#{var}` is a list.
    Remove the `is_list(#{var})` guard to reduce noise.
    """
  end
end
