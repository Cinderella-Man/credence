defmodule Credence.Pattern.NoExplicitSumReduce do
  @moduledoc "Flags explicit sum-reduction patterns inside Enum.reduce/3."

  use Credence.Pattern.Rule
  alias Credence.Issue

  @impl true
  def fixable?, do: true

  @impl true
  def priority, do: 501

  @impl true
  def check(ast, _opts) do
    {_ast, issues} =
      Macro.prewalk(ast, [], fn
        {{:., _, _}, meta, args} = node, issues ->
          if reduce_call?(node) and sum_reduce_body?(args) do
            issue = %Issue{
              rule: :no_explicit_sum_reduce,
              message: "Explicit sum-reduction detected. Prefer Enum.sum/1.",
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
  def fix(source, _opts) do
    source
    |> Sourceror.parse_string!()
    |> Macro.postwalk(fn
      {{:., _, _}, _, args} = node ->
        if reduce_call?(node) and sum_reduce_body?(args) do
          [enum | _] = args
          enum_sum_call(enum)
        else
          node
        end

      node ->
        node
    end)
    |> Sourceror.to_string()
  end

  defp enum_sum_call(enum) do
    {{:., [], [{:__aliases__, [], [:Enum]}, :sum]}, [], [enum]}
  end

  defp reduce_call?({{:., _, [{:__aliases__, _, [:Enum]}, :reduce]}, _, _}), do: true
  defp reduce_call?({{:., _, [:Enum, :reduce]}, _, _}), do: true
  defp reduce_call?(_), do: false

  # Notice how we pattern match the two arguments (v1, v2) passed into the anonymous function
  defp sum_reduce_body?([
         _enum,
         _acc,
         {:fn, _, [{:->, _, [[{v1, _, _}, {v2, _, _}], body]}]}
       ])
       when is_atom(v1) and is_atom(v2) do
    explicit_sum?(body, v1, v2)
  end

  defp sum_reduce_body?(_), do: false

  defp explicit_sum?({:__block__, _, [body]}, v1, v2), do: explicit_sum?(body, v1, v2)

  # Ensure the variables being added are EXACTLY the variables passed into the fn args
  defp explicit_sum?({:+, _, [{op1, _, _}, {op2, _, _}]}, v1, v2) do
    Enum.sort([op1, op2]) == Enum.sort([v1, v2])
  end

  defp explicit_sum?(_, _, _), do: false
end
