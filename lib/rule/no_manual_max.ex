defmodule Credence.Rule.NoManualMax do
  @moduledoc """
  Detects `if` expressions that manually reimplement `Kernel.max/2`.

  ## Why this matters

  LLMs frequently expand `max(a, b)` into conditional form because they
  translate from languages where `max` is less ergonomic or unavailable
  as an infix/kernel function:

      # Flagged — manual reimplementation
      new_current = if(current_sum + num > num, do: current_sum + num, else: num)

      # Idiomatic — Kernel.max/2
      new_current = max(current_sum + num, num)

  `Kernel.max/2` is clearer, shorter, and communicates intent directly.

  ## Flagged patterns

  Any `if` expression where:

  - The condition is a comparison (`>`, `>=`, `<`, `<=`),
  - One branch returns the left operand and the other returns the right, and
  - The branch returning the "greater" operand is the `do` (true) branch.

  All four comparison operators are handled:

  | Pattern                          | Replacement    |
  | -------------------------------- | -------------- |
  | `if a > b, do: a, else: b`      | `max(a, b)`    |
  | `if a >= b, do: a, else: b`     | `max(a, b)`    |
  | `if b < a, do: a, else: b`      | `max(a, b)`    |
  | `if b <= a, do: a, else: b`     | `max(a, b)`    |
  """

  @behaviour Credence.Rule
  alias Credence.Issue

  @impl true
  def check(ast, _opts) do
    {_ast, issues} =
      Macro.prewalk(ast, [], fn node, issues ->
        case check_node(node) do
          {:ok, issue} -> {node, [issue | issues]}
          :error -> {node, issues}
        end
      end)

    Enum.reverse(issues)
  end

  # ------------------------------------------------------------
  # NODE MATCHING
  # ------------------------------------------------------------

  defp check_node({:if, meta, [condition, branches]}) do
    with {:ok, do_branch} <- fetch_branch(branches, :do),
         {:ok, else_branch} <- fetch_branch(branches, :else),
         true <- is_max_pattern?(condition, do_branch, else_branch) do
      {:ok,
       %Issue{
         rule: :no_manual_max,
         message: build_message(),
         meta: %{line: Keyword.get(meta, :line)}
       }}
    else
      _ -> :error
    end
  end

  defp check_node(_), do: :error

  # ------------------------------------------------------------
  # MAX PATTERN DETECTION
  #
  # For `>` and `>=`: do == left operand, else == right operand
  #   → "if a > b, do: a, else: b"  (return greater in true branch)
  #
  # For `<` and `<=`: do == right operand, else == left operand
  #   → "if b < a, do: a, else: b"  (return greater in true branch)
  # ------------------------------------------------------------

  defp is_max_pattern?({op, _, [left, right]}, do_branch, else_branch)
       when op in [:>, :>=] do
    ast_equal?(do_branch, left) and ast_equal?(else_branch, right)
  end

  defp is_max_pattern?({op, _, [left, right]}, do_branch, else_branch)
       when op in [:<, :<=] do
    ast_equal?(do_branch, right) and ast_equal?(else_branch, left)
  end

  defp is_max_pattern?(_, _, _), do: false

  # ------------------------------------------------------------
  # HELPERS
  # ------------------------------------------------------------

  defp fetch_branch(branches, key) when is_list(branches) do
    case Keyword.fetch(branches, key) do
      {:ok, val} -> {:ok, val}
      :error -> :error
    end
  end

  defp fetch_branch(_, _), do: :error

  defp ast_equal?(a, b), do: strip_meta(a) == strip_meta(b)

  defp strip_meta({form, _meta, args}) do
    {strip_meta(form), nil, strip_meta(args)}
  end

  defp strip_meta(list) when is_list(list), do: Enum.map(list, &strip_meta/1)
  defp strip_meta({a, b}), do: {strip_meta(a), strip_meta(b)}
  defp strip_meta(other), do: other

  # ------------------------------------------------------------
  # MESSAGE GENERATION
  # ------------------------------------------------------------

  defp build_message do
    """
    Manual `if` comparison used instead of `max/2`.

    Replace with `Kernel.max/2` for clarity:

        max(a, b)
    """
  end
end
