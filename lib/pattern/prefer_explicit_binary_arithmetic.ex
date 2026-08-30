defmodule Credence.Pattern.PreferExplicitBinaryArithmetic do
  @moduledoc """
  Readability rule: flags piping into binary arithmetic functions like `rem/2`
  or `div/2`. Piping obscures which argument is the dividend — prefer an
  explicit call for clarity.

  ## Bad

      String.length(input_string) |> rem(3)
      numerator |> div(denominator)

  ## Good

      rem(String.length(input_string), 3)
      div(numerator, denominator)
  """
  use Credence.Pattern.Rule
  # Safe in all three families: un-pipes `a |> rem(b)` into `rem(a, b)` — the
  # pipe operator's own expansion — so the identical `div`/`rem` call node with
  # the identical operand order results in plain Elixir and inside any DSL that
  # admits `|>`; no operator is introduced, removed or reordered (the same
  # argument the allowlist already accepts for `no_unless_else`). The source
  # scan flags this rule because the construct appears in it, but the matcher
  # cannot reach a DSL expression, so the deliberate answer is the empty list
  # rather than an allowlist entry — the fixture-level oracle does not flag it
  # at all.
  @impl true
  def unsafe_in_dsl, do: []
  alias Credence.Issue
  alias Credence.RuleHelpers

  # Kernel binary arithmetic functions that are clearer as explicit calls.
  @binary_arithmetic_fns ~w(rem div)a

  @impl true
  def check(ast, _opts) do
    chained = chained_arith_pipes(ast)

    {_ast, issues} =
      Macro.prewalk(ast, [], fn
        {:|>, pipe_meta, [left, {fun, fun_meta, [right]}]} = node, issues
        when fun in @binary_arithmetic_fns and is_list(fun_meta) and
               is_list(pipe_meta) and right != nil and left != nil ->
          if standalone?(node, left, chained) do
            line = Keyword.get(fun_meta, :line) || Keyword.get(pipe_meta, :line)

            {node,
             [
               %Issue{
                 rule: :prefer_explicit_binary_arithmetic,
                 message:
                   "Piping into `#{fun}/2` obscures which argument is the dividend. " <>
                     "Use `#{fun}(a, b)` for clarity.",
                 meta: %{line: line}
               }
               | issues
             ]}
          else
            {node, issues}
          end

        node, issues ->
          {node, issues}
      end)

    Enum.reverse(issues)
  end

  @impl true
  def fix_patches(ast, opts) do
    chained = chained_arith_pipes(ast)
    source = Keyword.get(opts, :source) || Sourceror.to_string(ast)

    RuleHelpers.patches_from_ast_transform(ast, source, fn tree ->
      Macro.prewalk(tree, fn
        {:|>, _pipe_meta, [left, {fun, _fun_meta, [right]}]} = node
        when fun in @binary_arithmetic_fns and right != nil and left != nil ->
          if standalone?(node, left, chained), do: {fun, [], [left, right]}, else: node

        node ->
          node
      end)
    end)
  end

  # Only a *single* pipe (`x |> div(n)`) is flagged — not a div/rem step inside a
  # longer chain, where the pipe form reads naturally
  # (`diff |> div(1000) |> Integer.to_string()`).
  defp standalone?(node, left, chained) do
    not match?({:|>, _, _}, left) and node not in chained
  end

  # div/rem pipes that are the left operand of an enclosing pipe — i.e. piped
  # onward into another step, so part of a chain rather than a single pipe.
  defp chained_arith_pipes(ast) do
    {_ast, acc} =
      Macro.prewalk(ast, [], fn
        {:|>, _, [{:|>, _, [_, {lfun, _, [_]}]} = inner, _right]} = node, acc
        when lfun in @binary_arithmetic_fns ->
          {node, [inner | acc]}

        node, acc ->
          {node, acc}
      end)

    acc
  end
end
