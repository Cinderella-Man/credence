defmodule Credence.Pattern.NoIfTrueFalse do
  @moduledoc """
  Detects redundant `if/else` wrappers around boolean expressions.

  LLMs frequently emit this redundant boolean wrapper when the condition
  already evaluates to a boolean. An `if` whose `do` branch returns `true`
  and whose `else` branch returns `false` (or a wildcard default) is
  semantically identical to the condition itself.

  Also catches the generalised forms where both branches are boolean
  expressions or literals.

  ## Detected patterns

      if condition do true else false end           → condition
      if condition do bool_expr else false end       → condition and bool_expr
      if condition do false else true end            → not condition
      if condition do false else bool_expr end       → not condition and bool_expr
      if condition do true else bool_expr end        → condition or bool_expr
      if condition do bool_expr else true end        → not condition or bool_expr

  ## Bad

      if match?([_, _, _, _], parts) and Enum.all?(parts, &valid?/1) do
        true
      else
        false
      end

      if x > 0 do
        y == 1
      else
        false
      end

      if rem(year, 100) == 0 do
        rem(year, 400) == 0
      else
        true
      end

  ## Good

      match?([_, _, _, _], parts) and Enum.all?(parts, &valid?/1)

      x > 0 and y == 1

      rem(year, 100) != 0 or rem(year, 400) == 0

  ## Auto-fix

  - `if cond do true else false end` → `cond`
  - `if cond do expr else false end` → `cond and expr`
  - `if cond do false else true end` → `not cond`
  - `if cond do false else expr end` → `not cond and expr`
  - `if cond do true else expr end` → `cond or expr`
  - `if cond do expr else true end` → `not cond or expr`
  """

  use Credence.Pattern.Rule
  alias Credence.Issue

  @impl true
  def check(ast, _opts) do
    {_ast, issues} =
      Macro.prewalk(ast, [], fn
        {:if, meta, [_condition, clauses]} = node, acc when is_list(clauses) ->
          if redundant_boolean_if?(clauses) do
            {node, [build_issue(meta) | acc]}
          else
            {node, acc}
          end

        node, acc ->
          {node, acc}
      end)

    Enum.reverse(issues)
  end

  @impl true
  def fix_patches(ast, _opts) do
    Credence.RuleHelpers.patches_from_postwalk(ast, &maybe_rewrite/1)
  end

  # Classifies an if's clause list:
  #   :true_false — do: true, else: false  (replace with condition)
  #   :expr_false — do: <bool-expr>, else: false  (replace with condition and expr)
  #   :false_true — do: false, else: true  (replace with not condition)
  #   :false_expr — do: false, else: <bool-expr>  (replace with not condition and expr)
  #   :true_expr  — do: true, else: <bool-expr>  (replace with condition or expr)
  #   :expr_true  — do: <bool-expr>, else: true  (replace with not condition or expr)
  #   :other      — not a redundant boolean if
  defp classify_if(clauses) when is_list(clauses) do
    do_body = extract_clause(clauses, :do)
    else_body = extract_clause(clauses, :else)

    cond do
      normalize_bool(do_body) == true and normalize_bool(else_body) == false ->
        :true_false

      normalize_bool(else_body) == false and boolean_expr?(do_body) ->
        :expr_false

      normalize_bool(do_body) == false and normalize_bool(else_body) == true ->
        :false_true

      normalize_bool(do_body) == false and boolean_expr?(else_body) ->
        :false_expr

      normalize_bool(do_body) == true and boolean_expr?(else_body) ->
        :true_expr

      normalize_bool(else_body) == true and boolean_expr?(do_body) ->
        :expr_true

      true ->
        :other
    end
  end

  defp classify_if(_), do: :other

  defp redundant_boolean_if?(clauses), do: classify_if(clauses) != :other

  # Extracts the body for a given clause key (:do or :else).
  defp extract_clause(clauses, key) do
    Enum.find_value(clauses, fn
      {{:__block__, _, [^key]}, body} -> body
      _ -> nil
    end)
  end

  # Normalizes AST representations of boolean literals.
  defp normalize_bool(true), do: true
  defp normalize_bool(false), do: false
  defp normalize_bool({:__block__, _, [true]}), do: true
  defp normalize_bool({:__block__, _, [false]}), do: false
  defp normalize_bool(_), do: :other

  # Rewrites redundant boolean ifs to their collapsed form.
  defp maybe_rewrite({:if, _meta, [condition, clauses]} = node) when is_list(clauses) do
    case classify_if(clauses) do
      :true_false ->
        condition

      :expr_false ->
        do_body = extract_clause(clauses, :do)
        {:and, [], [condition, do_body]}

      :false_true ->
        negate(condition)

      :false_expr ->
        else_body = extract_clause(clauses, :else)
        {:and, [], [negate(condition), else_body]}

      :true_expr ->
        else_body = extract_clause(clauses, :else)
        {:or, [], [condition, else_body]}

      :expr_true ->
        do_body = extract_clause(clauses, :do)
        {:or, [], [negate(condition), do_body]}

      :other ->
        node
    end
  end

  defp maybe_rewrite(node), do: node

  # Returns true when the expression is a comparison or boolean operator —
  # safe to use as a boolean in `cond and expr`.
  defp boolean_expr?({:__block__, _, [expr]}), do: boolean_expr?(expr)

  defp boolean_expr?({op, _, [_, _]})
       when op in [:==, :!=, :<, :>, :<=, :>=, :===, :!==, :and, :or, :match?],
       do: true

  defp boolean_expr?({:not, _, [_]}), do: true

  # Kernel type-check predicates (is_nil, is_list, etc.)
  defp boolean_expr?({:is_nil, _, [_]}), do: true

  # Boolean-returning Enum functions — always return true/false.
  defp boolean_expr?({{:., _, [{:__aliases__, _, [:Enum]}, fun]}, _, _})
       when fun in [:all?, :any?, :empty?],
       do: true

  # Piped form: value |> Enum.all?(...), etc.
  defp boolean_expr?({:|>, _, [_, {{:., _, [{:__aliases__, _, [:Enum]}, fun]}, _, _}]})
       when fun in [:all?, :any?, :empty?],
       do: true

  # An if/else with all-boolean branches is itself a boolean expression.
  defp boolean_expr?({:if, _, [_condition, clauses]}) when is_list(clauses) do
    classify_if(clauses) != :other
  end

  defp boolean_expr?(_), do: false

  # Negates a boolean condition in AST form.
  # Uses the complement operator for comparisons instead of wrapping with `not`,
  # e.g. `not (a == b)` → `a != b`, `not (a > b)` → `a <= 0`.
  defp negate({:not, _, [inner]}), do: inner
  defp negate({:==, meta, [a, b]}), do: {:!=, meta, [a, b]}
  defp negate({:!=, meta, [a, b]}), do: {:==, meta, [a, b]}
  defp negate({:===, meta, [a, b]}), do: {:!==, meta, [a, b]}
  defp negate({:!==, meta, [a, b]}), do: {:===, meta, [a, b]}
  defp negate({:<, meta, [a, b]}), do: {:>=, meta, [a, b]}
  defp negate({:>, meta, [a, b]}), do: {:<=, meta, [a, b]}
  defp negate({:<=, meta, [a, b]}), do: {:>, meta, [a, b]}
  defp negate({:>=, meta, [a, b]}), do: {:<, meta, [a, b]}
  defp negate(condition), do: {:not, [], [condition]}

  defp build_issue(meta) do
    %Issue{
      rule: :no_if_true_false,
      message:
        "`if/else` with boolean branches is redundant. " <>
          "Use a direct boolean expression instead.",
      meta: %{line: Keyword.get(meta, :line)}
    }
  end
end
