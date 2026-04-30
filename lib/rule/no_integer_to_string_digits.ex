defmodule Credence.Rule.NoIntegerToStringDigits do
  @moduledoc """
  Performance rule: Detects converting an integer to a string representation
  in a given base and then to a charlist, when `Integer.digits/2` can extract
  the digits directly as a list of integers.

  The string conversion creates an intermediate binary and then a charlist,
  both of which are unnecessary allocations when you just need the digits.

  ## Bad

      String.to_charlist(Integer.to_string(number, 2))
      Integer.to_string(number, 2) |> String.to_charlist()

  ## Good

      Integer.digits(number, 2)
  """
  @behaviour Credence.Rule
  alias Credence.Issue

  @impl true
  def check(ast, _opts) do
    {_ast, issues} =
      Macro.prewalk(ast, [], fn
        # Nested: String.to_charlist(Integer.to_string(n, base))
        {{:., _, [{:__aliases__, _, [:String]}, :to_charlist]}, meta,
         [
           {{:., _, [{:__aliases__, _, [:Integer]}, :to_string]}, _, _args}
         ]} = node,
        issues ->
          {node, [build_issue(meta) | issues]}

        # Piped: Integer.to_string(n, base) |> String.to_charlist()
        {:|>, meta,
         [
           {{:., _, [{:__aliases__, _, [:Integer]}, :to_string]}, _, _args},
           {{:., _, [{:__aliases__, _, [:String]}, :to_charlist]}, _, _}
         ]} = node,
        issues ->
          {node, [build_issue(meta) | issues]}

        # Piped from var: n |> Integer.to_string(base) |> String.to_charlist()
        # The outer pipe has String.to_charlist on the right, and the
        # inner pipe has Integer.to_string on the right.
        {:|>, meta,
         [
           {:|>, _, [_, {{:., _, [{:__aliases__, _, [:Integer]}, :to_string]}, _, _}]},
           {{:., _, [{:__aliases__, _, [:String]}, :to_charlist]}, _, _}
         ]} = node,
        issues ->
          {node, [build_issue(meta) | issues]}

        node, issues ->
          {node, issues}
      end)

    Enum.reverse(issues)
  end

  defp build_issue(meta) do
    %Issue{
      rule: :no_integer_to_string_digits,
      severity: :warning,
      message:
        "Avoid `Integer.to_string/2 |> String.to_charlist/1` to extract digits. " <>
          "Use `Integer.digits/2` instead — it produces the digit list directly without intermediate string allocation.",
      meta: %{line: Keyword.get(meta, :line)}
    }
  end
end
