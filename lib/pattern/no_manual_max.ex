defmodule Credence.Pattern.NoManualMax do
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
  use Credence.Pattern.Rule
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
    |> Sourceror.parse_string!()
    |> Macro.postwalk(fn
      {:if, _meta, [condition, branches]} = node ->
        case try_fix_max(condition, branches) do
          {:ok, max_call} -> max_call
          :error -> node
        end

      node ->
        node
    end)
    |> Sourceror.to_string()
  end

  defp try_fix_max(condition, branches) do
    with {:ok, do_branch} <- fetch_branch(branches, :do),
         {:ok, else_branch} <- fetch_branch(branches, :else),
         {:ok, op} <- get_comparison_op(condition),
         {left, right} <- extract_operands(condition),
         true <- max_pattern?(op, left, right, do_branch, else_branch) do
      # do_branch is always the "greater" value — use it as max's first arg
      {:ok, max_call(do_branch, else_branch)}
    else
      _ -> :error
    end
  end

  defp get_comparison_op({op, _, [_, _]}) when op in [:>, :>=, :<, :<=],
    do: {:ok, op}

  defp get_comparison_op(_), do: :error

  defp extract_operands({_, _, [left, right]}), do: {left, right}

  defp max_call(a, b) do
    {:max, [], [a, b]}
  end

  defp check_node({:if, meta, [condition, branches]}) do
    with {:ok, do_branch} <- fetch_branch(branches, :do),
         {:ok, else_branch} <- fetch_branch(branches, :else),
         true <- max_pattern?(condition, do_branch, else_branch) do
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

  defp max_pattern?(condition, do_branch, else_branch) do
    case get_comparison_op(condition) do
      {:ok, op} ->
        {left, right} = extract_operands(condition)
        max_pattern?(op, left, right, do_branch, else_branch)

      :error ->
        false
    end
  end

  defp max_pattern?(op, left, right, do_branch, else_branch)
       when op in [:>, :>=] do
    ast_equal?(do_branch, left) and ast_equal?(else_branch, right)
  end

  defp max_pattern?(op, left, right, do_branch, else_branch)
       when op in [:<, :<=] do
    ast_equal?(do_branch, right) and ast_equal?(else_branch, left)
  end

  defp max_pattern?(_, _, _, _, _), do: false

  defp fetch_branch(branches, key) when is_list(branches) do
    case Keyword.fetch(branches, key) do
      {:ok, _} = ok ->
        ok

      :error ->
        # Sourceror wraps do/else keys as {:__block__, meta, [:do]}
        Enum.find_value(branches, :error, fn
          {{:__block__, _, [^key]}, val} -> {:ok, val}
          _ -> nil
        end)
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

  defp build_message do
    """
    Manual `if` comparison used instead of `max/2`.
    Replace with `Kernel.max/2` for clarity:
        max(a, b)
    """
  end
end
