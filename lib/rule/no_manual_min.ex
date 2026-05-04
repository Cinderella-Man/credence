defmodule Credence.Rule.NoManualMin do
  @moduledoc """
  Detects `if` expressions that manually reimplement `Kernel.min/2`.

  ## Why this matters

  LLMs frequently expand `min(a, b)` into conditional form because they
  translate from languages where `min` is less ergonomic or unavailable
  as an infix/kernel function:

      # Flagged — manual reimplementation
      threshold = if(a < b, do: a, else: b)

      # Idiomatic — Kernel.min/2
      threshold = min(a, b)

  `Kernel.min/2` is clearer, shorter, and communicates intent directly.

  ## Flagged patterns

  Any `if` expression where:

  - The condition is a comparison (`>`, `>=`, `<`, `<=`),
  - One branch returns the left operand and the other returns the right, and
  - The branch returning the "lesser" operand is the `do` (true) branch.

  All four comparison operators are handled:

  | Pattern                          | Replacement    |
  | -------------------------------- | -------------- |
  | `if a < b, do: a, else: b`      | `min(a, b)`    |
  | `if a <= b, do: a, else: b`     | `min(a, b)`    |
  | `if b > a, do: a, else: b`      | `min(a, b)`    |
  | `if b >= a, do: a, else: b`     | `min(a, b)`    |
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
          {:ok, issue} -> {node, [issue | issues]}
          :error -> {node, issues}
        end
      end)

    Enum.reverse(issues)
  end

  @impl true
  def fix(source, _opts) do
    source
    |> Code.string_to_quoted!()
    |> Macro.postwalk(fn
      {:if, _meta, [condition, branches]} = node ->
        case extract_min_operands(condition, branches) do
          {:ok, operands} -> min_call(operands)
          :error -> node
        end

      node ->
        node
    end)
    |> Macro.to_string()
  end

  defp check_node({:if, meta, [condition, branches]}) do
    with {:ok, do_branch} <- fetch_branch(branches, :do),
         {:ok, else_branch} <- fetch_branch(branches, :else),
         true <- min_pattern?(condition, do_branch, else_branch) do
      {:ok,
       %Issue{
         rule: :no_manual_min,
         message: build_message(),
         meta: %{line: Keyword.get(meta, :line)}
       }}
    else
      _ -> :error
    end
  end

  defp check_node(_), do: :error

  # ------------------------------------------------------------
  # MIN PATTERN DETECTION
  #
  # For `<` and `<=`: do == left operand, else == right operand
  #   → "if a < b, do: a, else: b"  (return lesser in true branch)
  #
  # For `>` and `>=`: do == right operand, else == left operand
  #   → "if b > a, do: a, else: b"  (return lesser in true branch)
  # ------------------------------------------------------------

  defp min_pattern?({op, _, [left, right]}, do_branch, else_branch)
       when op in [:<, :<=] do
    ast_equal?(do_branch, left) and ast_equal?(else_branch, right)
  end

  defp min_pattern?({op, _, [left, right]}, do_branch, else_branch)
       when op in [:>, :>=] do
    ast_equal?(do_branch, right) and ast_equal?(else_branch, left)
  end

  defp min_pattern?(_, _, _), do: false

  defp extract_min_operands(condition, branches) do
    with {:ok, do_branch} <- fetch_branch(branches, :do),
         {:ok, else_branch} <- fetch_branch(branches, :else) do
      get_min_operands(condition, do_branch, else_branch)
    end
  end

  # For < and <=: do_branch == left (the lesser value)
  # Result: min(left, right)
  defp get_min_operands({op, _, [left, right]}, do_branch, else_branch)
       when op in [:<, :<=] do
    if ast_equal?(do_branch, left) and ast_equal?(else_branch, right) do
      {:ok, [left, right]}
    else
      :error
    end
  end

  # For > and >=: do_branch == right (the lesser value)
  # Result: min(right, left) — puts the lesser value first to match
  # the convention shown in the documentation
  defp get_min_operands({op, _, [left, right]}, do_branch, else_branch)
       when op in [:>, :>=] do
    if ast_equal?(do_branch, right) and ast_equal?(else_branch, left) do
      {:ok, [right, left]}
    else
      :error
    end
  end

  defp get_min_operands(_, _, _), do: :error

  defp min_call([left, right]) do
    {:min, [], [left, right]}
  end

  defp fetch_branch(branches, key) when is_list(branches) do
    Keyword.fetch(branches, key)
  end

  defp fetch_branch(_, _), do: :error

  defp ast_equal?(a, b), do: strip_meta(a) == strip_meta(b)

  defp strip_meta({form, _meta, args}) do
    {strip_meta(form), nil, strip_meta(args)}
  end

  defp strip_meta(list) when is_list(list), do: Enum.map(list, &strip_meta/1)
  defp strip_meta({a, b}), do: {strip_meta(a), strip_meta(b)}
  defp strip_meta(other), do: other

  defp build_message do
    """
    Manual `if` comparison used instead of `min/2`.
    Replace with `Kernel.min/2` for clarity:
        min(a, b)
    """
  end
end
