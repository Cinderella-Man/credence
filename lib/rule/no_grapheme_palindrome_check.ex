defmodule Credence.Rule.NoGraphemePalindromeCheck do
  @moduledoc """
  Readability & performance rule: Detects the pattern of decomposing a string
  into graphemes or a charlist, only to compare it with its own `Enum.reverse`.

  This pattern creates an unnecessary intermediate list. Use `String.reverse/1`
  and compare strings directly instead.

  ## Bad

      graphemes = String.graphemes(s)
      graphemes == Enum.reverse(graphemes)

      codepoints = String.to_charlist(s)
      codepoints == Enum.reverse(codepoints)

      normalized = s |> String.downcase() |> String.graphemes()
      normalized == Enum.reverse(normalized)

  ## Good

      cleaned = String.downcase(s)
      cleaned == String.reverse(cleaned)
  """
  @behaviour Credence.Rule
  alias Credence.Issue

  @impl true
  def check(ast, _opts) do
    # Pass 1: collect variables bound to an expression ending in
    # String.graphemes/1 or String.to_charlist/1
    {_ast, decompose_vars} =
      Macro.prewalk(ast, MapSet.new(), fn
        {:=, _, [{var_name, _, nil}, rhs]} = node, acc when is_atom(var_name) ->
          terminal = rightmost(rhs)

          if decomposition_call?(terminal) do
            {node, MapSet.put(acc, var_name)}
          else
            {node, acc}
          end

        node, acc ->
          {node, acc}
      end)

    if MapSet.size(decompose_vars) == 0 do
      []
    else
      # Pass 2: find `var == Enum.reverse(var)` where var is in decompose_vars
      {_ast, issues} =
        Macro.prewalk(ast, [], fn
          # var == Enum.reverse(var)
          {:==, meta,
           [
             {var_name, _, nil},
             {{:., _, [{:__aliases__, _, [:Enum]}, :reverse]}, _, [{var_name, _, nil}]}
           ]} = node,
          acc
          when is_atom(var_name) ->
            if MapSet.member?(decompose_vars, var_name) do
              {node, [build_issue(meta) | acc]}
            else
              {node, acc}
            end

          # Enum.reverse(var) == var (reversed comparison)
          {:==, meta,
           [
             {{:., _, [{:__aliases__, _, [:Enum]}, :reverse]}, _, [{var_name, _, nil}]},
             {var_name, _, nil}
           ]} = node,
          acc
          when is_atom(var_name) ->
            if MapSet.member?(decompose_vars, var_name) do
              {node, [build_issue(meta) | acc]}
            else
              {node, acc}
            end

          node, acc ->
            {node, acc}
        end)

      Enum.reverse(issues)
    end
  end

  # Returns the rightmost (terminal) call in a pipe chain.
  defp rightmost({:|>, _, [_, right]}), do: rightmost(right)
  defp rightmost(other), do: other

  defp decomposition_call?(node) do
    match?(
      {{:., _, [{:__aliases__, _, [:String]}, func]}, _, _}
      when func in [:graphemes, :to_charlist],
      node
    )
  end

  defp build_issue(meta) do
    %Issue{
      rule: :no_grapheme_palindrome_check,
      message:
        "Avoid decomposing a string into graphemes/charlist just to compare with `Enum.reverse/1`. " <>
          "Use `str == String.reverse(str)` instead — it is clearer and avoids creating an intermediate list.",
      meta: %{line: Keyword.get(meta, :line)}
    }
  end
end
