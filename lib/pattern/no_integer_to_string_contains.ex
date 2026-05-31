defmodule Credence.Pattern.NoIntegerToStringContains do
  @moduledoc """
  Check-only rule: Detects converting an integer to a string just to use
  `String.contains?/2` for checking digit presence, when `Integer.digits/1`
  combined with `Enum.any?/2` is more direct and idiomatic.

  ## Bad

      Integer.to_string(number) |> String.contains?(["4", "7"])
      String.contains?(Integer.to_string(number), ["4", "7"])
      number |> Integer.to_string() |> String.contains?(["4", "7"])

  ## Good

      Integer.digits(number) |> Enum.any?(&(&1 in [4, 7]))
      Enum.any?(Integer.digits(number), &(&1 in [4, 7]))
  """

  use Credence.Pattern.Rule
  alias Credence.Issue

  @impl true
  def check(ast, _opts) do
    {_ast, issues} =
      Macro.prewalk(ast, [], fn
        node, issues ->
          if flagged?(node) do
            meta = extract_meta(node)
            {node, [build_issue(meta) | issues]}
          else
            {node, issues}
          end
      end)

    Enum.reverse(issues)
  end

  @impl true
  def fix_patches(_ast, _opts), do: []

  # Nested: String.contains?(Integer.to_string(n), ["4", "7"])
  defp flagged?(
         {{:., _, [{:__aliases__, _, [:String]}, :contains?]}, _,
          [{{:., _, [{:__aliases__, _, [:Integer]}, :to_string]}, _, _int_args}, list_arg]}
       ),
       do: single_char_string_list?(list_arg)

  # Piped 2-step: Integer.to_string(n) |> String.contains?(["4", "7"])
  defp flagged?(
         {:|>, _,
          [
            {{:., _, [{:__aliases__, _, [:Integer]}, :to_string]}, _, _int_args},
            {{:., _, [{:__aliases__, _, [:String]}, :contains?]}, _, [list_arg]}
          ]}
       ),
       do: single_char_string_list?(list_arg)

  # Piped 3-step: n |> Integer.to_string() |> String.contains?(["4", "7"])
  defp flagged?(
         {:|>, _,
          [
            {:|>, _, [_, {{:., _, [{:__aliases__, _, [:Integer]}, :to_string]}, _, _}]},
            {{:., _, [{:__aliases__, _, [:String]}, :contains?]}, _, [list_arg]}
          ]}
       ),
       do: single_char_string_list?(list_arg)

  defp flagged?(_), do: false

  # Extract the list from AST (handles {:__block__, _, [[...]]} wrapper)
  # and verify all elements are single-character strings (digit checks)
  defp single_char_string_list?({:__block__, _, [list]}) when is_list(list) do
    Enum.all?(list, fn
      {:__block__, _, [s]} when is_binary(s) -> String.length(s) == 1
      _ -> false
    end)
  end

  defp single_char_string_list?(_), do: false

  defp extract_meta({{:., _, _}, meta, _}), do: meta
  defp extract_meta({:|>, meta, _}), do: meta
  defp extract_meta(_), do: []

  defp build_issue(meta) do
    %Issue{
      rule: :no_integer_to_string_contains,
      message:
        "Avoid `Integer.to_string/1 |> String.contains?/2` to check for digit presence. " <>
          "Use `Integer.digits/1 |> Enum.any?/2` instead — it works with digits directly without string conversion.",
      meta: %{line: Keyword.get(meta, :line)}
    }
  end
end
