defmodule Credence.Pattern.PreferErlangFloat do
  @moduledoc """
  Replaces float-coercion arithmetic tricks with explicit `:erlang.float/1`.

  LLMs (and developers) use `x * 1.0`, `x / 1.0`, `x + 0.0`, or `x - 0.0` to
  coerce a number to a float. These are arithmetic idioms borrowed from Python;
  `:erlang.float/1` expresses the same intent explicitly and works whether the
  input is an integer (converts) or already a float (returns it unchanged).

  The rewrite **preserves the float result** — it does not delete the coercion.
  Deleting `* 1.0` (an earlier mistake of a now-merged sibling rule) would turn
  `6.0` back into `6`, a value-kind change; wrapping in `:erlang.float/1` keeps
  the value identical for every number.

  Applies to **any operand shape** — bare variables (`n * 1.0`) and compound
  expressions alike (`Enum.sum(list) * 1.0`, `(a + b) * 1.0`).

  ## Detected patterns

      x * 1.0      1.0 * x
      x / 1.0
      x + 0.0      0.0 + x
      x - 0.0

  Note: `0.0 - x` is NOT flagged — it negates, not coerces.

  ## Behaviour note

  For every numeric operand the rewrite is exact (same float value). A
  *non-number* operand raises in both forms — `x * 1.0` raises `ArithmeticError`
  while `:erlang.float(x)` raises `ArgumentError` — so the code crashes either
  way and only the exception module differs. (A non-number operand at a
  float-coercion site is already-broken code.)

  ## Bad

      defp to_float(n) when is_integer(n), do: n * 1.0
      avg = total / count * 1.0

  ## Good

      defp to_float(n) when is_integer(n), do: :erlang.float(n)
      avg = :erlang.float(total / count)
  """

  use Credence.Pattern.Rule
  alias Credence.Issue

  @impl true
  def check(ast, _opts) do
    {_ast, issues} =
      Macro.prewalk(ast, [], fn
        {op, meta, [left, right]} = node, acc when op in [:*, :/, :+, :-] ->
          cond do
            # operand OP identity (right-hand identity)
            identity_right?(op, unwrap_float(right)) ->
              {node, [build_issue(meta) | acc]}

            # identity OP operand (left-hand identity, commutative ops only)
            op in [:*, :+] and identity_left?(op, unwrap_float(left)) ->
              {node, [build_issue(meta) | acc]}

            true ->
              {node, acc}
          end

        node, acc ->
          {node, acc}
      end)

    Enum.reverse(issues)
  end

  @impl true
  def fix_patches(ast, _opts) do
    Credence.RuleHelpers.patches_from_postwalk(ast, &maybe_to_erlang_float/1)
  end

  # Replace identity-coercion arithmetic with `:erlang.float(operand)`, where the
  # operand is whichever side is not the `1.0` / `0.0` identity literal.
  defp maybe_to_erlang_float({op, _meta, [left, right]} = node) when op in [:*, :/, :+, :-] do
    cond do
      identity_right?(op, unwrap_float(right)) ->
        erlang_float(unwrap_block(left))

      op in [:*, :+] and identity_left?(op, unwrap_float(left)) ->
        erlang_float(unwrap_block(right))

      true ->
        node
    end
  end

  defp maybe_to_erlang_float(node), do: node

  # Strip a single Sourceror `{:__block__, _, [inner]}` wrapper (around a bare
  # variable or literal); leave compound expression nodes untouched.
  defp unwrap_block({:__block__, _, [inner]}), do: inner
  defp unwrap_block(node), do: node

  defp erlang_float(operand_node) do
    {{:., [], [:erlang, :float]}, [], [operand_node]}
  end

  defp identity_right?(:*, 1.0), do: true
  defp identity_right?(:/, 1.0), do: true
  defp identity_right?(:+, +0.0), do: true
  defp identity_right?(:-, +0.0), do: true
  defp identity_right?(_, _), do: false

  defp identity_left?(:*, 1.0), do: true
  defp identity_left?(:+, +0.0), do: true
  defp identity_left?(_, _), do: false

  # Sourceror wraps float literals in {:__block__, meta, [value]}.
  defp unwrap_float({:__block__, _, [val]}) when is_float(val), do: val
  defp unwrap_float(_), do: nil

  defp build_issue(meta) do
    %Issue{
      rule: :prefer_erlang_float,
      message:
        "Use `:erlang.float(x)` for number → float coercion instead of " <>
          "arithmetic identity tricks (`* 1.0`, `/ 1.0`, `+ 0.0`, `- 0.0`).",
      meta: %{line: Keyword.get(meta, :line)}
    }
  end
end
