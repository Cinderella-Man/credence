defmodule Credence.Pattern.NoExplicitMinReduce do
  @moduledoc "Flags explicit min-reduction patterns inside Enum.reduce/3."

  use Credence.Rule
  alias Credence.Issue

  @impl true
  def fixable?, do: true

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

  @impl true
  def fix(source, _opts) do
    source
    |> Sourceror.parse_string!()
    |> Macro.postwalk(fn
      {{:., _, _}, _, args} = node ->
        if reduce_call?(node) and min_reduce_body?(args) do
          [enum | _] = args
          enum_min_call(enum)
        else
          node
        end

      node ->
        node
    end)
    |> Sourceror.to_string()
  end

  defp enum_min_call(enum) do
    {{:., [], [{:__aliases__, [], [:Enum]}, :min]}, [], [enum]}
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
