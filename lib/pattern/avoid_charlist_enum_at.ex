defmodule Credence.Pattern.AvoidCharlistEnumAt do
  @moduledoc """
  Readability rule: Detects `Enum.at/2` on a charlist obtained from
  `String.to_charlist/1`. Converting a string to a charlist just to use
  indexed character access creates an unnecessary intermediate list.

  Use `String.at/2` directly on the original string instead.

  ## Bad

      chars = String.to_charlist(string)
      Enum.at(chars, i) == Enum.at(chars, j)

      Enum.at(String.to_charlist(string), 0)

      chars = string |> String.to_charlist()
      chars |> Enum.at(i)

  ## Good

      String.at(string, i) == String.at(string, j)

      String.at(string, 0)
  """

  use Credence.Pattern.Rule
  alias Credence.Issue

  @impl true
  def check(ast, _opts) do
    charlist_vars = collect_charlist_vars(ast)

    {_ast, issues} =
      Macro.prewalk(ast, [], fn
        # Enum.at(var, idx) where var is a charlist variable
        {{:., _, [{:__aliases__, _, [:Enum]}, :at]}, meta, [{var_name, _, nil}, _idx]} = node,
        acc
        when is_atom(var_name) ->
          if MapSet.member?(charlist_vars, var_name) do
            {node, [build_issue(meta, var_name) | acc]}
          else
            {node, acc}
          end

        # Inline: Enum.at(String.to_charlist(x), idx)
        {{:., _, [{:__aliases__, _, [:Enum]}, :at]}, meta, [to_charlist, _idx]} = node, acc ->
          if to_charlist_call?(to_charlist) do
            {node, [build_inline_issue(meta) | acc]}
          else
            {node, acc}
          end

        # Pipe: var |> Enum.at(idx)
        {:|>, meta, [{var_name, _, nil}, {{:., _, [{:__aliases__, _, [:Enum]}, :at]}, _, _}]} =
            node,
        acc
        when is_atom(var_name) ->
          if MapSet.member?(charlist_vars, var_name) do
            {node, [build_issue(meta, var_name) | acc]}
          else
            {node, acc}
          end

        node, acc ->
          {node, acc}
      end)

    Enum.reverse(issues)
  end

  @impl true
  def fix_patches(_ast, _opts), do: []

  defp collect_charlist_vars(ast) do
    {_ast, vars} =
      Macro.prewalk(ast, MapSet.new(), fn
        {:=, _, [{var_name, _, nil}, rhs]} = node, acc when is_atom(var_name) ->
          terminal = rightmost(rhs)

          if to_charlist_call?(terminal) do
            {node, MapSet.put(acc, var_name)}
          else
            {node, acc}
          end

        node, acc ->
          {node, acc}
      end)

    vars
  end

  defp rightmost({:|>, _, [_, right]}), do: rightmost(right)
  defp rightmost(other), do: other

  defp to_charlist_call?({{:., _, [{:__aliases__, _, [:String]}, :to_charlist]}, _, args})
       when is_list(args),
       do: true

  defp to_charlist_call?(_), do: false

  defp build_issue(meta, var_name) do
    %Issue{
      rule: :avoid_charlist_enum_at,
      message:
        "`Enum.at/2` on `#{var_name}` (from `String.to_charlist/1`). " <>
          "Use `String.at/2` on the original string to avoid the intermediate charlist.",
      meta: %{line: Keyword.get(meta, :line)}
    }
  end

  defp build_inline_issue(meta) do
    %Issue{
      rule: :avoid_charlist_enum_at,
      message:
        "`Enum.at/2` on `String.to_charlist/1` result. " <>
          "Use `String.at/2` directly instead.",
      meta: %{line: Keyword.get(meta, :line)}
    }
  end
end
