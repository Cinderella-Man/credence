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

  # DSL-unsafe: collapses the `if` to bare boolean expressions (and/or/not, flipped
  # comparisons, `!==`) that Ash.Expr, Ecto.Query and Nx.Defn each reinterpret.
  @impl true
  def unsafe_in_dsl, do: :all
  alias Credence.Issue
  alias Credence.RuleHelpers

  @impl true
  def check(ast, _opts) do
    enum_shadowed? = enum_shadowed?(ast)

    {_ast, issues} =
      Macro.prewalk(ast, [], fn
        {:if, meta, [condition, clauses]} = node, acc when is_list(clauses) ->
          if rewritable_if?(condition, clauses, enum_shadowed?) do
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
    enum_shadowed? = enum_shadowed?(ast)
    Credence.RuleHelpers.patches_from_postwalk(ast, &maybe_rewrite(&1, enum_shadowed?))
  end

  # Classifies an if's clause list:
  #   :true_false — do: true, else: false  (replace with condition)
  #   :expr_false — do: <bool-expr>, else: false  (replace with condition and expr)
  #   :false_true — do: false, else: true  (replace with not condition)
  #   :false_expr — do: false, else: <bool-expr>  (replace with not condition and expr)
  #   :true_expr  — do: true, else: <bool-expr>  (replace with condition or expr)
  #   :expr_true  — do: <bool-expr>, else: true  (replace with not condition or expr)
  #   :other      — not a redundant boolean if
  defp classify_if(clauses, enum_shadowed?) when is_list(clauses) do
    do_body = extract_clause(clauses, :do)
    else_body = extract_clause(clauses, :else)

    cond do
      normalize_bool(do_body) == true and normalize_bool(else_body) == false ->
        :true_false

      normalize_bool(else_body) == false and boolean_expr?(do_body, enum_shadowed?) ->
        :expr_false

      normalize_bool(do_body) == false and normalize_bool(else_body) == true ->
        :false_true

      normalize_bool(do_body) == false and boolean_expr?(else_body, enum_shadowed?) ->
        :false_expr

      normalize_bool(do_body) == true and boolean_expr?(else_body, enum_shadowed?) ->
        :true_expr

      normalize_bool(else_body) == true and boolean_expr?(do_body, enum_shadowed?) ->
        :expr_true

      true ->
        :other
    end
  end

  defp classify_if(_, _enum_shadowed?), do: :other

  # A redundant boolean `if` is only safe to collapse when its CONDITION is
  # guaranteed to evaluate to an actual boolean. Otherwise the rewrites change
  # the answer: `if x do true else false end` returns `true` for a truthy
  # non-boolean `x` (e.g. `5`) while the collapsed form `x` returns `5`; and
  # `if x do expr else false end` returns `expr` while `x and expr` raises a
  # `BadBooleanError`. The branch shapes alone don't make the rewrite safe.
  defp rewritable_if?(condition, clauses, enum_shadowed?),
    do:
      boolean_condition?(condition, enum_shadowed?) and
        classify_if(clauses, enum_shadowed?) != :other

  defp boolean_condition?(condition, false), do: RuleHelpers.boolean_condition?(condition)

  defp boolean_condition?({:__block__, _, [expr]}, true), do: boolean_condition?(expr, true)

  defp boolean_condition?({op, _, [_, _]}, true)
       when op in [:==, :!=, :<, :>, :<=, :>=, :===, :!==, :match?],
       do: true

  defp boolean_condition?({op, _, [left, right]}, true) when op in [:and, :or],
    do: boolean_condition?(left, true) and boolean_condition?(right, true)

  defp boolean_condition?({:not, _, [inner]}, true), do: boolean_condition?(inner, true)
  defp boolean_condition?({:is_nil, _, [_]}, true), do: true
  defp boolean_condition?(_, true), do: false

  # Conditions whose result is always a boolean (or which raise identically to
  # the original `if`). Comparisons, `match?`, `is_nil`, `not`, and the
  # boolean-returning `Enum` predicates always return `true`/`false`. `and`/`or`
  # only do so when BOTH operands do — `true and 5` evaluates to `5`.

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
  defp maybe_rewrite({:if, _meta, [condition, clauses]} = node, enum_shadowed?)
       when is_list(clauses) do
    if boolean_condition?(condition, enum_shadowed?) do
      rewrite_if(condition, clauses, node, enum_shadowed?)
    else
      node
    end
  end

  defp maybe_rewrite(node, _enum_shadowed?), do: node

  defp rewrite_if(condition, clauses, node, enum_shadowed?) do
    case classify_if(clauses, enum_shadowed?) do
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

  # Returns true when the expression is a comparison or boolean operator —
  # safe to use as a boolean in `cond and expr`.
  defp boolean_expr?({:__block__, _, [expr]}, enum_shadowed?),
    do: boolean_expr?(expr, enum_shadowed?)

  defp boolean_expr?({op, _, [_, _]}, _enum_shadowed?)
       when op in [:==, :!=, :<, :>, :<=, :>=, :===, :!==, :and, :or, :match?],
       do: true

  defp boolean_expr?({:not, _, [_]}, _enum_shadowed?), do: true

  # Kernel type-check predicates (is_nil, is_list, etc.)
  defp boolean_expr?({:is_nil, _, [_]}, _enum_shadowed?), do: true

  # Boolean-returning Enum functions — always return true/false.
  defp boolean_expr?({{:., _, [{:__aliases__, _, [:Enum]}, fun]}, _, _}, false)
       when fun in [:all?, :any?, :empty?],
       do: true

  # Piped form: value |> Enum.all?(...), etc.
  defp boolean_expr?(
         {:|>, _, [_, {{:., _, [{:__aliases__, _, [:Enum]}, fun]}, _, _}]},
         false
       )
       when fun in [:all?, :any?, :empty?],
       do: true

  # An if/else with all-boolean branches is itself a boolean expression.
  defp boolean_expr?({:if, _, [_condition, clauses]}, enum_shadowed?) when is_list(clauses) do
    classify_if(clauses, enum_shadowed?) != :other
  end

  defp boolean_expr?(_, _enum_shadowed?), do: false

  defp enum_shadowed?(ast) do
    {_ast, shadowed?} =
      Macro.prewalk(ast, false, fn
        {:alias, _, [target, opts]} = node, acc when is_list(opts) ->
          {node, acc or aliases_as_enum?(target, opts)}

        node, acc ->
          {node, acc}
      end)

    shadowed?
  end

  defp aliases_as_enum?({:__aliases__, _, parts}, opts) do
    target_is_enum? = parts in [[:Enum], [:"Elixir", :Enum]]

    Enum.any?(opts, fn
      {{:__block__, _, [:as]}, {:__aliases__, _, [:Enum]}} -> not target_is_enum?
      _ -> false
    end)
  end

  defp aliases_as_enum?(_, _), do: false

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
