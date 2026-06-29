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

  Only the **non-strict** comparison forms are flagged, because only they equal
  `max/2` for every input. `max/2` returns its first argument on a tie, so:

  | Pattern                      | Replacement | Flagged? |
  | ---------------------------- | ----------- | -------- |
  | `if a >= b, do: a, else: b` | `max(a, b)` | yes      |
  | `if b <= a, do: a, else: b` | `max(a, b)` | yes      |
  | `if a > b, do: a, else: b`  | —           | no       |
  | `if b < a, do: a, else: b`  | —           | no       |

  The strict forms (`>`, `<`) take the `else` branch on a tie, which differs from
  `max/2` when the operands are equal in value but different in type — e.g.
  `max(1, 1.0)` is `1`, but `if 1 > 1.0, do: 1, else: 1.0` yields `1.0`. So they
  are not rewritten.
  """
  use Credence.Pattern.Rule

  # DSL-unsafe: rewrites `if a >= b, do: a, else: b` to `max(a, b)`. `max/2` is not a
  # query operator (Ash won't translate it, Ecto forbids it) and is tensor-blind in
  # Nx.Defn where `>=` is element-wise.
  @impl true
  def unsafe_in_dsl, do: :all
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

  @impl true
  def fix_patches(ast, _opts) do
    Credence.RuleHelpers.patches_from_postwalk(ast, fn
      {:if, _meta, [condition, branches]} = node ->
        case try_fix_max(condition, branches) do
          {:ok, max_call} -> max_call
          :error -> node
        end

      node ->
        node
    end)
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

  # Only the NON-STRICT operators are behaviour-preserving. `max/2` uses `>=`
  # (returns the first arg on a tie), so `if a >= b, do: a, else: b` matches it
  # exactly. The strict `if a > b, do: a, else: b` returns the ELSE branch on a
  # tie — which differs from `max` when the operands are equal in value but
  # different in type, e.g. `max(1, 1.0) == 1` but the manual form yields `1.0`.
  defp max_pattern?(:>=, left, right, do_branch, else_branch) do
    ast_equal?(do_branch, left) and ast_equal?(else_branch, right)
  end

  defp max_pattern?(:<=, left, right, do_branch, else_branch) do
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
