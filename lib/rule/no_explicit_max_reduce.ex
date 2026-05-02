defmodule Credence.Rule.NoExplicitMaxReduce do
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

  use Credence.Rule
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

  # ----------------------------
  # Detect Enum.reduce safely
  # ----------------------------

  defp reduce_call?({{:., _, [{:__aliases__, _, [:Enum]}, :reduce]}, _, _}), do: true
  defp reduce_call?({{:., _, [:Enum, :reduce]}, _, _}), do: true
  defp reduce_call?(_), do: false

  # ----------------------------
  # Extract fn body safely
  # ----------------------------

  defp max_reduce_body?([
         _enum,
         _acc,
         {:fn, _, [{:->, _, [_args, body]}]}
       ]) do
    explicit_max?(body)
  end

  defp max_reduce_body?(_), do: false

  # ----------------------------
  # STRICT max detection only
  # ----------------------------

  # Safely unwrap single-expression blocks (added by formatter/parser occasionally)
  defp explicit_max?({:__block__, _, [body]}), do: explicit_max?(body)

  # Match unqualified Kernel.max/2 calls
  defp explicit_max?({:max, _, [_, _]}), do: true

  # Match `if >` (ignoring strict keyword list length to account for AST metadata)
  defp explicit_max?({:if, _, [{:>, _, [_, _]}, _opts]}), do: true

  # Match `if >=`
  defp explicit_max?({:if, _, [{:>=, _, [_, _]}, _opts]}), do: true

  # Fallback
  defp explicit_max?(_), do: false
end
