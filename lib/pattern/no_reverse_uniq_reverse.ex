defmodule Credence.Pattern.NoReverseUniqReverse do
  @moduledoc """
  Detects the pattern of wrapping `Enum.uniq/1` or `Enum.uniq_by/2` between
  two `Enum.reverse/1` calls.

  This pattern keeps the **last** occurrence of each element instead of the
  default first-occurrence behaviour of `Enum.uniq/1`. It is almost always
  unintentional — use `Enum.uniq/1` directly for first-occurrence dedup.

  ## Bad

      list |> Enum.reverse() |> Enum.uniq() |> Enum.reverse()
      list |> Enum.reverse() |> Enum.uniq_by(&elem(&1, 0)) |> Enum.reverse()

  ## Good

      Enum.uniq(list)
  """

  use Credence.Pattern.Rule
  alias Credence.Issue

  @impl true
  def check(ast, _opts) do
    {_ast, issues} =
      Macro.prewalk(ast, [], fn
        # Pipeline: ... |> Enum.reverse() |> Enum.uniq() |> Enum.reverse()
        {:|>, meta, [left, right]} = node, issues ->
          if remote_call?(right, :Enum, :reverse) do
            case left do
              {:|>, _, [inner_left, uniq_node]} ->
                if uniq_call?(uniq_node) and
                     remote_call?(rightmost(inner_left), :Enum, :reverse) do
                  {node, [build_issue(meta) | issues]}
                else
                  {node, issues}
                end

              _ ->
                {node, issues}
            end
          else
            {node, issues}
          end

        # Nested: Enum.reverse(Enum.uniq(Enum.reverse(list)))
        {{:., _, [{:__aliases__, _, [:Enum]}, :reverse]}, meta,
         [{{:., _, [{:__aliases__, _, [:Enum]}, uniq_func]}, _, uniq_args}]} = node,
        issues
        when uniq_func in [:uniq, :uniq_by] and is_list(uniq_args) and uniq_args != [] ->
          if remote_call?(hd(uniq_args), :Enum, :reverse) do
            {node, [build_issue(meta) | issues]}
          else
            {node, issues}
          end

        node, issues ->
          {node, issues}
      end)

    Enum.reverse(issues)
  end

  @impl true
  def fix_patches(_ast, _opts), do: []

  defp uniq_call?(node) do
    remote_call?(node, :Enum, :uniq) or remote_call?(node, :Enum, :uniq_by)
  end

  defp remote_call?(node, mod, func) do
    match?({{:., _, [{:__aliases__, _, [^mod]}, ^func]}, _, _}, node)
  end

  defp rightmost({:|>, _, [_, right]}), do: right
  defp rightmost(other), do: other

  defp build_issue(meta) do
    %Issue{
      rule: :no_reverse_uniq_reverse,
      message:
        "`Enum.reverse/1` + `Enum.uniq/1` + `Enum.reverse/1` keeps the last occurrence " <>
          "of each element. Use `Enum.uniq/1` directly for first-occurrence dedup.",
      meta: %{line: Keyword.get(meta, :line)}
    }
  end
end
