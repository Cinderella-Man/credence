defmodule Credence.Pattern.NoSingleUseBinding do
  @moduledoc """
  Detects a variable that is assigned and then used exactly once as an
  operand of a comparison or boolean operator in the immediately following
  expression.

  This is a common LLM verbosity pattern where the intermediate binding
  adds no value and can be inlined into the expression.

  ## Example

      # Bad
      gcd = Integer.gcd(a, b)
      gcd == 1

      # Good
      Integer.gcd(a, b) == 1

  ## Scope

  Only flags when:
  - The assignment is a simple `var = expr` (not a pattern match).
  - The variable appears exactly once in the next statement.
  - The next statement is a comparison (`==`, `!=`, `>`, `<`, etc.) or
    boolean (`and`, `or`, `&&`, `||`) operator expression.
  - The next statement is NOT just the variable itself (handled by
    `no_redundant_assignment`).
  - The next statement is NOT a control-flow expression (`if`, `case`,
    `cond`, `with`, `try`, `for`, `receive`).

  ## Auto-fix

  Replaces the variable with the bound expression (wrapped in parens
  for precedence safety) and removes the assignment. Handles multiple
  single-use bindings in the same block recursively.
  """

  use Credence.Pattern.Rule
  alias Credence.Issue

  @control_flow_heads ~w(if unless case cond with try for receive)a
  @comparison_ops ~w(== != === !== > < >= <=)a
  @boolean_ops ~w(and or && ||)a
  @flaggable_ops @comparison_ops ++ @boolean_ops

  @impl true
  def check(ast, _opts) do
    {_ast, issues} =
      Macro.prewalk(ast, [], fn
        {:__block__, _meta, statements} = node, acc when is_list(statements) ->
          issues = check_pairs(statements)
          {node, issues ++ acc}

        node, acc ->
          {node, acc}
      end)

    Enum.reverse(issues)
  end

  @impl true
  def fix_patches(ast, _opts) do
    Credence.RuleHelpers.patches_from_postwalk(ast, &maybe_rewrite_block/1)
  end

  # ── Check ──────────────────────────────────────────────────────────

  defp check_pairs([_first | rest] = statements) when rest != [] do
    statements
    |> Enum.chunk_every(2, 1, :discard)
    |> Enum.flat_map(&check_pair/1)
  end

  defp check_pairs(_), do: []

  defp check_pair([{:=, meta, [{name, _, ctx}, _rhs]}, next_stmt])
       when is_atom(name) and is_atom(ctx) and name != :_ do
    cond do
      variable_only?(next_stmt, name) ->
        []

      control_flow?(next_stmt) ->
        []

      not operator_expression?(next_stmt) ->
        []

      count_var(name, ctx, next_stmt) == 1 ->
        [
          %Issue{
            rule: :no_single_use_binding,
            message:
              "Variable `#{name}` is bound and used only once in the next expression. " <>
                "Consider inlining the expression directly.",
            meta: %{line: Keyword.get(meta, :line)}
          }
        ]

      true ->
        []
    end
  end

  defp check_pair(_), do: []

  # ── Fix ────────────────────────────────────────────────────────────

  defp maybe_rewrite_block({:__block__, meta, statements} = node)
       when is_list(statements) and length(statements) >= 2 do
    case rewrite_pairs(statements) do
      ^statements -> node
      new_statements -> {:__block__, meta, new_statements}
    end
  end

  defp maybe_rewrite_block(node), do: node

  # Recursively rewrite single-use bindings until none remain.
  defp rewrite_pairs(statements) do
    case find_and_rewrite_pair(statements) do
      {:ok, new_statements} when new_statements != statements ->
        rewrite_pairs(new_statements)

      _ ->
        statements
    end
  end

  defp find_and_rewrite_pair(statements) do
    statements
    |> Enum.chunk_every(2, 1, :discard)
    |> Enum.with_index()
    |> Enum.find_value(:no_match, fn
      {[{:=, _, [{name, _, ctx}, rhs]}, next_stmt], index}
      when is_atom(name) and is_atom(ctx) and name != :_ ->
        if not variable_only?(next_stmt, name) and
             not control_flow?(next_stmt) and
             operator_expression?(next_stmt) and
             count_var(name, ctx, next_stmt) == 1 do
          new_next = replace_var(name, ctx, rhs, next_stmt)
          {before_pair, [_assign, _ | rest]} = Enum.split(statements, index)
          {:ok, before_pair ++ [new_next | rest]}
        else
          nil
        end

      _ ->
        nil
    end)
  end

  # ── Helpers ────────────────────────────────────────────────────────

  defp variable_only?({name, _, _}, name), do: true
  defp variable_only?(_, _), do: false

  defp control_flow?({head, _, _}) when head in @control_flow_heads, do: true
  defp control_flow?(_), do: false

  defp operator_expression?({op, _, _}) when op in @flaggable_ops, do: true
  defp operator_expression?(_), do: false

  defp count_var(name, ctx, ast) do
    {_, count} =
      Macro.prewalk(ast, 0, fn
        {^name, _, ^ctx} = node, acc -> {node, acc + 1}
        node, acc -> {node, acc}
      end)

    count
  end

  # Replace every occurrence of {name, _, ctx} in `ast` with `rhs`
  # wrapped in a __block__ (adds parens for precedence safety).
  defp replace_var(name, ctx, rhs, ast) do
    parenthesized = {:__block__, [], [rhs]}

    Macro.prewalk(ast, fn
      {^name, _, ^ctx} -> parenthesized
      node -> node
    end)
  end
end
