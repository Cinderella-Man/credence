defmodule Credence.Pattern.NoExplicitMaxReduce do
  @moduledoc """
  Strict semantic rule: Flags explicit max-reduction patterns inside `Enum.reduce/3`.

  This rule does NOT perform heuristic detection. It only matches cases where
  the reduce body clearly implements a max/argmax operation using:

  - `max(a, b)` → auto-fix to `Enum.max/1`
  - `if a > acc do a else acc end` → auto-fix to `Enum.max/1`
  - `if a >= acc do a else acc end` → auto-fix to `Enum.max/1`

  Also detects max-by patterns (check-only, no auto-fix):

  - `if f(a) > f(b) do a else b end` → flagged, use `Enum.max_by/2`
  - `if f(a) >= f(b) do a else b end` → flagged, use `Enum.max_by/2`

  where the same function `f` is applied to both sides of the comparison
  and the branches return the original elements.

  Any deviation (tuple state, maps, pipelines, multiple expressions, etc.)
  will NOT be flagged.
  """

  use Credence.Pattern.Rule
  alias Credence.Issue

  @impl true
  def check(ast, _opts) do
    {_ast, issues} =
      Macro.prewalk(ast, [], fn
        # MATCH ALL Enum.reduce variants safely
        {{:., _, _}, meta, args} = node, issues ->
          case reduce_call?(node) && reduce_body_type?(args) do
            :max ->
              issue = %Issue{
                rule: :no_explicit_max_reduce,
                message: "Explicit max-reduction detected. Prefer Enum.max/1 or Enum.max_by/2.",
                meta: %{line: Keyword.get(meta, :line)}
              }

              {node, [issue | issues]}

            :max_by ->
              issue = %Issue{
                rule: :no_explicit_max_reduce,
                message:
                  "Explicit max-by reduction detected. Prefer Enum.max_by/2 or Enum.max_by/3.",
                meta: %{line: Keyword.get(meta, :line)}
              }

              {node, [issue | issues]}

            _ ->
              {node, issues}
          end

        node, issues ->
          {node, issues}
      end)

    Enum.reverse(issues)
  end

  @impl true
  def fix_patches(ast, _opts) do
    Credence.RuleHelpers.patches_from_postwalk(ast, fn
      {{:., _, _}, _, args} = node ->
        if reduce_call?(node) and reduce_body_type?(args) == :max do
          [enum, acc | _] = args

          if simple_var?(acc) do
            # acc is a variable (e.g. `head` from a pattern match) —
            # include it: Enum.max([acc | enum])
            enum_max_with_acc_call(acc, enum)
          else
            # acc is a literal sentinel (e.g. 0) — Enum.max(enum) suffices
            enum_max_call(enum)
          end
        else
          node
        end

      node ->
        node
    end)
  end

  defp enum_max_call(enum) do
    {{:., [], [{:__aliases__, [], [:Enum]}, :max]}, [], [enum]}
  end

  defp enum_max_with_acc_call(acc, enum) do
    {{:., [], [{:__aliases__, [], [:Enum]}, :max]}, [], [[{:|, [], [acc, enum]}]]}
  end

  defp reduce_call?({{:., _, [{:__aliases__, _, [:Enum]}, :reduce]}, _, _}), do: true
  defp reduce_call?({{:., _, [:Enum, :reduce]}, _, _}), do: true
  defp reduce_call?(_), do: false

  defp reduce_body_type?([
         _enum,
         _acc,
         {:fn, _, [{:->, _, [_args, body]}]}
       ]) do
    cond do
      explicit_max?(body) -> :max
      explicit_max_by?(body) -> :max_by
      true -> false
    end
  end

  defp reduce_body_type?(_), do: false

  # Safely unwrap single-expression blocks (added by formatter/parser occasionally)
  defp explicit_max?({:__block__, _, [body]}), do: explicit_max?(body)

  # Match unqualified Kernel.max/2 calls — only when BOTH arguments are
  # simple variable references.  If either arg is a function call or other
  # expression (e.g. `max(acc, length(el))`), rewriting to `Enum.max(enum)`
  # would be semantically incorrect because it compares raw elements instead
  # of the transformed values.
  defp explicit_max?({:max, _, [left, right]}), do: simple_var?(left) and simple_var?(right)

  # Match `if a > b do a else b end` — the do/else branches must return
  # the same simple variables that are compared (otherwise it's not a max).
  defp explicit_max?({:if, _, [{:>, _, [left, right]}, opts]}) do
    simple_var?(left) and simple_var?(right) and
      returns_compared_vars?(opts, left, right)
  end

  # Match `if a >= b do a else b end`
  defp explicit_max?({:if, _, [{:>=, _, [left, right]}, opts]}) do
    simple_var?(left) and simple_var?(right) and
      returns_compared_vars?(opts, left, right)
  end

  # Fallback
  defp explicit_max?(_), do: false

  # --- max_by detection (check-only, no auto-fix) ---

  # Safely unwrap single-expression blocks
  defp explicit_max_by?({:__block__, _, [body]}), do: explicit_max_by?(body)

  # Match `if f(a) > f(b) do a else b end` where f is the same on both sides
  defp explicit_max_by?({:if, _, [{:>, _, [left, right]}, opts]}) do
    max_by_pattern?(left, right, opts)
  end

  # Match `if f(a) >= f(b) do a else b end`
  defp explicit_max_by?({:if, _, [{:>=, _, [left, right]}, opts]}) do
    max_by_pattern?(left, right, opts)
  end

  defp explicit_max_by?(_), do: false

  defp max_by_pattern?(left, right, opts) do
    function_call_with_simple_arg?(left) and
      function_call_with_simple_arg?(right) and
      same_function?(left, right) and
      returns_compared_vars?(opts, function_call_arg(left), function_call_arg(right))
  end

  # A function call with exactly one argument that is a simple variable.
  # Handles both qualified (String.length(x)) and unqualified (length(x)) calls.
  defp function_call_with_simple_arg?({{:., _, [{:__aliases__, _, _}, _]}, _, [arg]}),
    do: simple_var?(arg)

  defp function_call_with_simple_arg?({fun, _, [arg]}) when is_atom(fun),
    do: simple_var?(arg)

  defp function_call_with_simple_arg?(_), do: false

  # Check that two function calls invoke the same function.
  defp same_function?(
         {{:., _, [{:__aliases__, _, mod1}, fun1]}, _, _},
         {{:., _, [{:__aliases__, _, mod2}, fun2]}, _, _}
       ),
       do: mod1 == mod2 and fun1 == fun2

  defp same_function?({fun1, _, _}, {fun2, _, _})
       when is_atom(fun1) and is_atom(fun2),
       do: fun1 == fun2

  defp same_function?(_, _), do: false

  # Extract the argument from a function call node.
  defp function_call_arg({{:., _, _}, _, [arg]}), do: arg
  defp function_call_arg({_, _, [arg]}), do: arg

  # Verify the if-branches return the compared variables (not tuples, calls, etc.).
  # Sourceror represents if-clauses as [{{:__block__, _, [:do]}, body}, ...].
  defp returns_compared_vars?(clauses, left, right) when is_list(clauses) do
    then_expr = extract_if_clause(clauses, :do)
    else_expr = extract_if_clause(clauses, :else)
    var_names = compared_var_names(left, right)
    then_expr != nil and else_expr != nil and
      returns_simple_var?(then_expr, var_names) and
      returns_simple_var?(else_expr, var_names)
  end

  defp extract_if_clause(clauses, key) do
    # Sourceror format: [{{:__block__, _, [:do]}, body}, ...]
    Enum.find_value(clauses, fn
      {{:__block__, _, [^key]}, body} -> body
      _ -> nil
    end)
    # Fallback: keyword list format [do: body, ...]
    |> Kernel.||(Keyword.get(clauses, key))
  end

  defp returns_simple_var?({:__block__, _, [expr]} = _block, var_names),
    do: returns_simple_var?(expr, var_names)

  defp returns_simple_var?({name, _, ctx}, var_names)
       when is_atom(name) and is_atom(ctx),
       do: MapSet.member?(var_names, name)

  defp returns_simple_var?(_, _), do: false

  defp compared_var_names({left_name, _, _}, {right_name, _, _})
       when is_atom(left_name) and is_atom(right_name),
       do: MapSet.new([left_name, right_name])

  # A simple variable reference is an atom name with an atom context
  # (no function calls, field accesses, or other compound expressions).
  defp simple_var?({name, _, ctx}) when is_atom(name) and is_atom(ctx), do: true
  defp simple_var?(_), do: false
end
