defmodule Credence.Pattern.NoExplicitMaxReduce do
  @moduledoc """
  Strict semantic rule: Flags ONLY explicit max-reduction patterns inside `Enum.reduce/3`.

  This rule does NOT perform heuristic detection. It only matches cases where
  the reduce body clearly implements a max/argmax operation using:

  - `max(a, b)`
  - `if a > acc do ... else ...`
  - `if a >= acc do ... else ...`

  Any deviation (tuple state, maps, pipelines, multiple expressions, etc.)
  will NOT be flagged.
  """

  use Credence.Pattern.Rule
  alias Credence.Issue

  @impl true
  def check(ast, _opts) do
    {_ast, issues} =
      Macro.prewalk(ast, [], fn
        # MATCH ALL Enum.reduce variants safely
        {{:., _, _}, meta, args} = node, issues ->
          if reduce_call?(node) and max_reduce_body?(args) do
            issue = %Issue{
              rule: :no_explicit_max_reduce,
              message: "Explicit max-reduction detected. Prefer Enum.max/1 or Enum.max_by/2.",
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
  def fix_patches(ast, _opts) do
    Credence.RuleHelpers.patches_from_postwalk(ast, fn
      {{:., _, _}, _, args} = node ->
        if reduce_call?(node) and max_reduce_body?(args) do
          [enum | _] = args
          enum_max_call(enum)
        else
          node
        end

      node ->
        node
    end)
  end

  defp enum_max_call(enum) do
    {{:., [], [{:__aliases__, [], [:Enum]}, :max]}, [], [enum]}
  end

  defp reduce_call?({{:., _, [{:__aliases__, _, [:Enum]}, :reduce]}, _, _}), do: true
  defp reduce_call?({{:., _, [:Enum, :reduce]}, _, _}), do: true
  defp reduce_call?(_), do: false

  defp max_reduce_body?([
         _enum,
         _acc,
         {:fn, _, [{:->, _, [_args, body]}]}
       ]) do
    explicit_max?(body)
  end

  defp max_reduce_body?(_), do: false

  # Safely unwrap single-expression blocks (added by formatter/parser occasionally)
  defp explicit_max?({:__block__, _, [body]}), do: explicit_max?(body)

  # Match unqualified Kernel.max/2 calls — only when BOTH arguments are
  # simple variable references.  If either arg is a function call or other
  # expression (e.g. `max(acc, length(el))`), rewriting to `Enum.max(enum)`
  # would be semantically incorrect because it compares raw elements instead
  # of the transformed values.
  defp explicit_max?({:max, _, [left, right]}), do: simple_var?(left) and simple_var?(right)

  # Match `if >` (ignoring strict keyword list length to account for AST metadata)
  defp explicit_max?({:if, _, [{:>, _, [left, right]}, _opts]}),
    do: simple_var?(left) and simple_var?(right)

  # Match `if >=`
  defp explicit_max?({:if, _, [{:>=, _, [left, right]}, _opts]}),
    do: simple_var?(left) and simple_var?(right)

  # Fallback
  defp explicit_max?(_), do: false

  # A simple variable reference is an atom name with an atom context
  # (no function calls, field accesses, or other compound expressions).
  defp simple_var?({name, _, ctx}) when is_atom(name) and is_atom(ctx), do: true
  defp simple_var?(_), do: false
end
