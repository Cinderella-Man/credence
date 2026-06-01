defmodule Credence.Pattern.NoConditionalMaxInReduce do
  @moduledoc """
  Check-only rule: Detects conditional max-reduction patterns inside `Enum.reduce/3`.

  LLMs frequently write reduce callbacks that compute a conditional value
  and then call `max(acc, value)`:

      Enum.reduce(enum, 0, fn x, acc ->
        max(acc, if x > threshold, do: x, else: 0)
      end)

  This is equivalent to:

      enum |> Enum.filter(&( &1 > threshold)) |> Enum.max(fn -> 0 end)

  The pattern wastes work: every element is compared via `max` even when
  the conditional returns 0 and can never improve the accumulator.

  Two variants are detected:

  1. `max(acc, if cond do val else 0 end)` — max wrapping a conditional
  2. `if cond do max(acc, val) else acc end` — conditional wrapping max

  ## Auto-fix

  No auto-fix — the refactoring requires restructuring the reduce into
  filter + max, which depends on surrounding context.
  """

  use Credence.Pattern.Rule
  alias Credence.Issue

  @impl true
  def check(ast, _opts) do
    {_ast, issues} =
      Macro.prewalk(ast, [], fn
        {{:., _, _}, meta, args} = node, issues ->
          if reduce_call?(node) and conditional_max_body?(args) do
            issue = %Issue{
              rule: :no_conditional_max_in_reduce,
              message:
                "Conditional max inside reduce detected. " <>
                  "Prefer filter + Enum.max/1 over max(acc, if cond do val else 0 end).",
              meta: %{line: Keyword.get(meta, :line)}
            }

            {node, [issue | issues]}
          else
            {node, issues}
          end

        node, issues ->
          {node, issues}
      end)

    Enum.reverse(issues)
  end

  @impl true
  def fix_patches(_ast, _opts), do: []

  defp reduce_call?({{:., _, [{:__aliases__, _, [:Enum]}, :reduce]}, _, _}), do: true
  defp reduce_call?({{:., _, [:Enum, :reduce]}, _, _}), do: true
  defp reduce_call?(_), do: false

  defp conditional_max_body?([
         _enum,
         _acc,
         {:fn, _, [{:->, _, [_args, body]}]}
       ]) do
    conditional_max?(body)
  end

  defp conditional_max_body?(_), do: false

  # Safely unwrap single-expression blocks
  defp conditional_max?({:__block__, _, [body]}), do: conditional_max?(body)

  # Multi-statement block: check if the last statement is a max call that
  # references a variable assigned from a conditional with 0 default.
  defp conditional_max?({:__block__, _, statements}) when length(statements) > 1 do
    last = List.last(statements)
    assigns = Enum.drop(statements, -1)

    case last do
      {:max, _, [left, right]} ->
        (simple_var?(left) and assigned_from_conditional_zero?(left, assigns)) or
          (simple_var?(right) and assigned_from_conditional_zero?(right, assigns))

      _ ->
        conditional_max?(last)
    end
  end

  # Variant 1: max(acc, if cond do val else 0 end) — inline conditional
  defp conditional_max?({:max, _, [left, right]}) do
    (simple_var?(left) and conditional_with_zero_default?(right)) or
      (simple_var?(right) and conditional_with_zero_default?(left))
  end

  # Variant 2: if cond do max(acc, val) else acc end
  defp conditional_max?({:if, _, [_cond, opts]}) when is_list(opts) do
    do_body = extract_clause(opts, :do)
    else_body = extract_clause(opts, :else)

    case {do_body, else_body} do
      {{:max, _, [left, right]}, {name, _, ctx}}
      when is_atom(name) and is_atom(ctx) ->
        # else branch returns a simple variable (the acc)
        # do branch calls max with the acc variable and some value
        simple_var?(left) or simple_var?(right)

      _ ->
        false
    end
  end

  defp conditional_max?(_), do: false

  # Check if a variable was assigned from an `if cond do val else 0 end` expression
  defp assigned_from_conditional_zero?({var_name, _, _}, assigns) do
    Enum.any?(assigns, fn
      {:=, _, [{^var_name, _, _}, expr]} -> conditional_with_zero_default?(expr)
      _ -> false
    end)
  end

  # Check if an expression is `if cond do val else 0 end` (inline if with 0 default).
  # Only matches single-expression do-branch — multi-statement branches may have
  # side effects that would be lost if refactored to filter + max.
  defp conditional_with_zero_default?({:if, _, [_cond, opts]}) when is_list(opts) do
    do_body = extract_clause(opts, :do)
    else_body = extract_clause(opts, :else)
    single_expression?(do_body) and zero_literal?(else_body)
  end

  defp conditional_with_zero_default?(_), do: false

  defp zero_literal?(0), do: true
  defp zero_literal?({:__block__, _, [0]}), do: true
  defp zero_literal?(_), do: false

  # A single-expression body (not a multi-statement block)
  defp single_expression?({:__block__, _, [_]}), do: true
  defp single_expression?({:__block__, _, stmts}) when length(stmts) > 1, do: false
  defp single_expression?(_), do: true

  defp extract_clause(clauses, key) do
    Enum.find_value(clauses, fn
      {{:__block__, _, [^key]}, body} -> body
      {^key, body} -> body
      _ -> nil
    end)
  end

  defp simple_var?({name, _, ctx}) when is_atom(name) and is_atom(ctx), do: true
  defp simple_var?(_), do: false
end
