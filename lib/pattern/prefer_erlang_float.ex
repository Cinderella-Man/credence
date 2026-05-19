defmodule Credence.Pattern.PreferErlangFloat do
  @moduledoc """
  Replaces bare-variable float coercion tricks with explicit `:erlang.float/1`.

  LLMs (and developers) use `n * 1.0`, `n / 1.0`, `n + 0.0`, or `n - 0.0`
  to coerce an integer to a float. These are arithmetic tricks borrowed from
  Python — `:erlang.float/1` expresses the same intent explicitly and works
  whether the input is an integer (converts) or already a float (returns it).

  This rule only handles **bare-variable** operands. Compound expressions
  and function calls (`(a + b) * 1.0`, `Enum.sum(list) * 1.0`) are handled
  by `NoIdentityFloatCoercion`, which removes the identity outright — those
  are overwhelmingly Python-isms, not intentional coercion.

  ## Priority

  This rule runs at priority 501 (above the default 500) so it processes
  bare-variable sites **before** `NoIdentityFloatCoercion`. This matters
  when both kinds share a line — e.g. `{n * 1.0, Enum.sum(xs) * 1.0}`.
  Without the higher priority, `NoIdentityFloatCoercion`'s line-level regex
  would strip all `* 1.0` on the line, including the bare-variable site
  that should become `:erlang.float(n)`.

  ## Detected patterns

      var * 1.0      1.0 * var
      var / 1.0
      var + 0.0      0.0 + var
      var - 0.0

  Note: `0.0 - var` is NOT flagged — it negates, not coerces.

  ## Bad

      defp to_float(n) when is_integer(n), do: n * 1.0

      count = count + 0.0

  ## Good

      defp to_float(n) when is_integer(n), do: :erlang.float(n)

      count = :erlang.float(count)

  ## Auto-fix

  Replaces the identity arithmetic with `:erlang.float(var)`.
  """

  use Credence.Pattern.Rule
  alias Credence.Issue

  # Run before NoIdentityFloatCoercion (priority 500) so bare-variable
  # sites are rewritten to :erlang.float(var) before the sibling rule's
  # line-level regex strips all `* 1.0` indiscriminately.
  @impl true
  def priority, do: 499

  @impl true
  def check(ast, _opts) do
    {_ast, issues} =
      Macro.prewalk(ast, [], fn
        {op, meta, [left, right]} = node, acc when op in [:*, :/, :+, :-] ->
          cond do
            # bare_var OP identity (right-hand identity)
            identity_right?(op, unwrap_float(right)) and bare_var?(left) ->
              {node, [build_issue(meta) | acc]}

            # identity OP bare_var (left-hand identity, commutative ops only)
            op in [:*, :+] and identity_left?(op, unwrap_float(left)) and bare_var?(right) ->
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

  # Replace identity arithmetic on a bare variable with `:erlang.float(var)`.
  # AST patterns are precise enough that this rule and `NoIdentityFloatCoercion`
  # (priority 500) cleanly partition their targets — no line-level
  # coordination needed: this rule fires only on bare vars, the other
  # only on non-bare expressions.
  defp maybe_to_erlang_float({op, _meta, [left, right]} = node) when op in [:*, :/, :+, :-] do
    cond do
      identity_right?(op, unwrap_float(right)) and bare_var?(left) ->
        erlang_float(unwrap_var(left))

      op in [:*, :+] and identity_left?(op, unwrap_float(left)) and bare_var?(right) ->
        erlang_float(unwrap_var(right))

      true ->
        node
    end
  end

  defp maybe_to_erlang_float(node), do: node

  defp unwrap_var({:__block__, _, [inner]}), do: inner
  defp unwrap_var(node), do: node

  defp erlang_float(var_node) do
    {{:., [], [:erlang, :float]}, [], [var_node]}
  end

  # Sourceror wraps variables in {:__block__, _, [var_node]}.
  defp bare_var?({:__block__, _, [inner]}), do: bare_var?(inner)
  defp bare_var?({name, _meta, ctx}) when is_atom(name) and is_atom(ctx), do: true
  defp bare_var?(_), do: false

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
        "Use `:erlang.float(var)` for int → float coercion instead of " <>
          "arithmetic identity tricks (`* 1.0`, `/ 1.0`, `+ 0.0`, `- 0.0`).",
      meta: %{line: Keyword.get(meta, :line)}
    }
  end
end
