defmodule Credence.Pattern.NoListConcatWithRecursiveResult do
  @moduledoc """
  Detects a **list-literal prefix** concatenated onto a recursive call with
  `++` in the return expression of a recursive function, and rewrites the
  `++` to a cons:

      [a, b] ++ recursive_call(...)   ==>   [a, b | recursive_call(...)]

  `[a, b] ++ X` is, by the definition of `++`, exactly `[a, b | X]` for
  *every* `X` (proper list, improper tail, or non-list — `++` never
  constrains its right operand). The rewrite is byte-for-byte
  behaviour-preserving: same elements, same evaluation order, each operand
  evaluated exactly once. It drops the intermediate list construction and
  the `++` traversal of the prefix.

  ## Scope (and what is deliberately *not* flagged)

  This rule fires **only** when the left operand is a non-empty list literal
  whose last element is not itself a cons. The genuinely O(n²) shapes the
  prefix-cons rewrite *cannot* safely repair are left alone, because their
  only fix is a non-local accumulator restructuring that changes arity and
  call sites:

    * `computed_var ++ recursive_result` — the left list is an arbitrary
      bound value, not a literal; there is no local cons form.
    * `recursive_result ++ [x]` — recursion on the *left*; cons only
      prepends, so there is no equivalent.

  Those are the province of `no_list_append_in_recursion` (accumulator in a
  tail call) or a manual rewrite.

  ## Bad

      def build([]), do: []
      def build([h | t]), do: [h] ++ build(t)

  ## Good

      def build([]), do: []
      def build([h | t]), do: [h | build(t)]
  """
  use Credence.Pattern.Rule
  alias Credence.Issue
  alias Credence.RuleHelpers

  @impl true
  def check(ast, _opts) do
    {_ast, issues} =
      Macro.prewalk(ast, [], fn
        {kind, meta, [{:when, _, [{name, _, params}, _guard]}, body_kw]} = node, issues
        when kind in [:def, :defp] and is_atom(name) and is_list(params) ->
          body = extract_body(body_kw)
          {node, check_clause(body, name, meta, issues)}

        {kind, meta, [{name, _, params}, body_kw]} = node, issues
        when kind in [:def, :defp] and is_atom(name) and is_list(params) ->
          body = extract_body(body_kw)
          {node, check_clause(body, name, meta, issues)}

        node, issues ->
          {node, issues}
      end)

    Enum.reverse(issues)
  end

  @impl true
  def fix_patches(ast, _opts) do
    RuleHelpers.patches_from_postwalk(ast, &apply_fix/1)
  end

  defp check_clause(body, name, meta, issues) do
    case fixable_concat(body, name) do
      {:ok, concat_meta, _new_node} ->
        line = Keyword.get(concat_meta, :line) || Keyword.get(meta, :line)

        [
          %Issue{
            rule: :no_list_concat_with_recursive_result,
            message:
              "`[...] ++ recursive_call(...)` in a recursive return builds and " <>
                "copies the prefix list on every level. Use a cons " <>
                "`[... | recursive_call(...)]` instead — it is exactly equal and " <>
                "avoids the copy.",
            meta: %{line: line}
          }
          | issues
        ]

      :error ->
        issues
    end
  end

  # The fixable shape: the clause's last expression is `[a, b, ...] ++ rhs`
  # where the left operand is a non-empty list literal whose last element is
  # not itself a cons, and `rhs` is (or is bound to) a recursive call. Returns
  # `{:ok, concat_meta, cons_node}` so check and fix share one definition.
  defp fixable_concat(body, name) do
    bindings = collect_self_call_bindings(body, name)

    case last_expression(body) do
      {:++, meta, [lhs, rhs]} ->
        case literal_prefix(lhs) do
          {:ok, elements, wrapper} ->
            if recursive_operand?(rhs, name, bindings) do
              {:ok, meta, build_cons(wrapper, elements, rhs)}
            else
              :error
            end

          :error ->
            :error
        end

      _ ->
        :error
    end
  end

  # A non-empty list literal whose final element is not a cons cell. A cons
  # last element means the literal is improper (e.g. `[a | b]`), which `++`
  # would reject at runtime and which has no `[... | rhs]` rendering.
  defp literal_prefix(lhs) do
    case RuleHelpers.unwrap_list(lhs) do
      {:ok, [_ | _] = elements, wrapper} ->
        if cons_cell?(List.last(elements)), do: :error, else: {:ok, elements, wrapper}

      _ ->
        :error
    end
  end

  # `[a, b, c] ++ rhs` -> `[a, b, c | rhs]`: replace the last element with a
  # cons of (last element, rhs), reusing the original list wrapper's meta.
  defp build_cons(wrapper, elements, rhs) do
    {init, [last]} = Enum.split(elements, -1)
    RuleHelpers.rewrap_list(wrapper, init ++ [{:|, [], [last, rhs]}])
  end

  defp apply_fix(
         {kind, meta, [{:when, _, [{name, _, params}, _guard]} = head, body_kw]} = node
       )
       when kind in [:def, :defp] and is_atom(name) and is_list(params) do
    fix_clause(node, kind, meta, head, body_kw, name)
  end

  defp apply_fix({kind, meta, [{name, _, params} = head, body_kw]} = node)
       when kind in [:def, :defp] and is_atom(name) and is_list(params) do
    fix_clause(node, kind, meta, head, body_kw, name)
  end

  defp apply_fix(node), do: node

  defp fix_clause(node, kind, meta, head, body_kw, name) do
    body = extract_body(body_kw)

    case fixable_concat(body, name) do
      {:ok, _concat_meta, cons_node} ->
        new_body = replace_last_expression(body, cons_node)
        {kind, meta, [head, put_body(body_kw, new_body)]}

      :error ->
        node
    end
  end

  defp collect_self_call_bindings(body, name) do
    {_, bindings} =
      Macro.prewalk(body, %{}, fn
        {:=, _, [{var_name, _, ctx}, {^name, _, args}]} = node, acc
        when is_atom(var_name) and (is_nil(ctx) or is_atom(ctx)) and is_list(args) ->
          {node, Map.put(acc, var_name, true)}

        node, acc ->
          {node, acc}
      end)

    bindings
  end

  defp recursive_operand?({callee, _, args}, name, _bindings)
       when is_atom(callee) and is_list(args) and callee == name,
       do: true

  defp recursive_operand?({var_name, _, ctx}, _name, bindings)
       when is_atom(var_name) and (is_nil(ctx) or is_atom(ctx)) do
    Map.has_key?(bindings, var_name)
  end

  defp recursive_operand?(_, _, _), do: false

  defp cons_cell?({:|, _, _}), do: true
  defp cons_cell?(_), do: false

  defp extract_body(body_kw) when is_list(body_kw) do
    Enum.find_value(body_kw, fn
      {{:__block__, _, [:do]}, body} -> body
      _ -> nil
    end)
  end

  defp extract_body(body), do: body

  defp put_body(body_kw, new_body) when is_list(body_kw) do
    Enum.map(body_kw, fn
      {{:__block__, m, [:do]}, _old} -> {{:__block__, m, [:do]}, new_body}
      other -> other
    end)
  end

  defp put_body(_body, new_body), do: new_body

  defp last_expression({:__block__, _, exprs}) when is_list(exprs), do: List.last(exprs)
  defp last_expression(expr), do: expr

  defp replace_last_expression({:__block__, meta, exprs}, new_last) do
    {:__block__, meta, List.replace_at(exprs, -1, new_last)}
  end

  defp replace_last_expression(_single, new_last), do: new_last
end
