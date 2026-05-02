defmodule Credence.Rule.NoExplicitMinReduce do
  @moduledoc "Flags explicit min-reduction patterns inside Enum.reduce/3."
  @behaviour Credence.Rule
  alias Credence.Issue

  @impl true
  def check(ast, _opts) do
    {_ast, issues} =
      Macro.prewalk(ast, [], fn
        {{:., _, _}, meta, args} = node, issues ->
          if reduce_call?(node) and min_reduce_body?(args) do
            issue = %Issue{
              rule: :no_explicit_min_reduce,
              message: "Explicit min-reduction detected. Prefer Enum.min/1 or Enum.min_by/2.",
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

  defp reduce_call?({{:., _, [{:__aliases__, _, [:Enum]}, :reduce]}, _, _}), do: true
  defp reduce_call?({{:., _, [:Enum, :reduce]}, _, _}), do: true
  defp reduce_call?(_), do: false

  defp min_reduce_body?([_enum, _acc, {:fn, _, [{:->, _, [_args, body]}]}]) do
    explicit_min?(body)
  end

  defp min_reduce_body?(_), do: false

  defp explicit_min?({:__block__, _, [body]}), do: explicit_min?(body)
  defp explicit_min?({:min, _, [_, _]}), do: true
  defp explicit_min?({:if, _, [{:<, _, [_, _]}, _opts]}), do: true
  defp explicit_min?({:if, _, [{:<=, _, [_, _]}, _opts]}), do: true
  defp explicit_min?(_), do: false
end
