defmodule Credence.Pattern.NoManualMin do
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

  Only the **non-strict** comparison forms are flagged, because only they equal
  `min/2` for every input. `min/2` returns its first argument on a tie, so:

  | Pattern                      | Replacement | Flagged? |
  | ---------------------------- | ----------- | -------- |
  | `if a <= b, do: a, else: b` | `min(a, b)` | yes      |
  | `if b >= a, do: a, else: b` | `min(a, b)` | yes      |
  | `if a < b, do: a, else: b`  | —           | no       |
  | `if b > a, do: a, else: b`  | —           | no       |

  The strict forms (`<`, `>`) take the `else` branch on a tie, which differs from
  `min/2` when the operands are equal in value but different in type — e.g.
  `min(1, 1.0)` is `1`, but `if 1 < 1.0, do: 1, else: 1.0` yields `1.0`. So they
  are not rewritten.
  """

  use Credence.Pattern.Rule

  # DSL-unsafe: rewrites `if a <= b, do: a, else: b` to `min(a, b)`. `min/2` is not a
  # query operator (Ash won't translate it, Ecto forbids it) and is tensor-blind in
  # Nx.Defn where `<=` is element-wise.
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
        case extract_min_operands(condition, branches) do
          {:ok, operands} -> min_call(operands)
          :error -> node
        end

      node ->
        node
    end)
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
  # MIN PATTERN DETECTION
  #
  # For `<` and `<=`: do == left operand, else == right operand
  #   → "if a < b, do: a, else: b"  (return lesser in true branch)
  #
  # For `>` and `>=`: do == right operand, else == left operand
  #   → "if b > a, do: a, else: b"  (return lesser in true branch)
  # Only the NON-STRICT operators are behaviour-preserving. `min/2` uses `<=`,
  # so `if a <= b, do: a, else: b` matches it exactly. The strict `if a < b`
  # takes the ELSE branch on a tie, differing from `min` when the operands are
  # equal in value but different in type, e.g. `min(1, 1.0) == 1` but the manual
  # form yields `1.0`.
  defp min_pattern?({:<=, _, [left, right]}, do_branch, else_branch) do
    ast_equal?(do_branch, left) and ast_equal?(else_branch, right)
  end

  defp min_pattern?({:>=, _, [left, right]}, do_branch, else_branch) do
    ast_equal?(do_branch, right) and ast_equal?(else_branch, left)
  end

  defp min_pattern?(_, _, _), do: false

  defp extract_min_operands(condition, branches) do
    with {:ok, do_branch} <- fetch_branch(branches, :do),
         {:ok, else_branch} <- fetch_branch(branches, :else) do
      get_min_operands(condition, do_branch, else_branch)
    end
  end

  # For <=: do_branch == left (the lesser value) → min(left, right)
  defp get_min_operands({:<=, _, [left, right]}, do_branch, else_branch) do
    if ast_equal?(do_branch, left) and ast_equal?(else_branch, right) do
      {:ok, [left, right]}
    else
      :error
    end
  end

  # For >=: do_branch == right (the lesser value) → min(right, left)
  defp get_min_operands({:>=, _, [left, right]}, do_branch, else_branch) do
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
    Manual `if` comparison used instead of `min/2`.
    Replace with `Kernel.min/2` for clarity:
        min(a, b)
    """
  end
end
