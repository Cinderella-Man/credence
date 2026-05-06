defmodule Credence.Pattern.NoIntegerToStringDigits do
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

  use Credence.Rule
  alias Credence.Issue

  @impl true
  def fixable?, do: true

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
  def fix(source, _opts) do
    source
    |> Sourceror.parse_string!()
    |> Macro.postwalk(fn
      # Nested: String.to_charlist(Integer.to_string(n, base))
      {{:., _, [{:__aliases__, _, [:String]}, :to_charlist]}, _,
       [{{:., _, [{:__aliases__, _, [:Integer]}, :to_string]}, _, int_args}]} ->
        integer_digits_call(int_args)

      # Piped 2-step: Integer.to_string(n, base) |> String.to_charlist()
      {:|>, _,
       [
         {{:., _, [{:__aliases__, _, [:Integer]}, :to_string]}, _, int_args},
         {{:., _, [{:__aliases__, _, [:String]}, :to_charlist]}, _, _}
       ]} ->
        integer_digits_call(int_args)

      # Piped 3-step: n |> Integer.to_string(base) |> String.to_charlist()
      {:|>, _,
       [
         {:|>, _, [n, {{:., _, [{:__aliases__, _, [:Integer]}, :to_string]}, _, pipe_args}]},
         {{:., _, [{:__aliases__, _, [:String]}, :to_charlist]}, _, _}
       ]} ->
        integer_digits_call([n | pipe_args])

      node ->
        node
    end)
    |> Sourceror.to_string()
  end

  defp integer_digits_call(args) do
    {{:., [], [{:__aliases__, [], [:Integer]}, :digits]}, [], args}
  end

  # Nested: String.to_charlist(Integer.to_string(n, base))
  defp flagged?(
         {{:., _, [{:__aliases__, _, [:String]}, :to_charlist]}, _,
          [{{:., _, [{:__aliases__, _, [:Integer]}, :to_string]}, _, _args}]}
       ),
       do: true

  # Piped 2-step: Integer.to_string(n, base) |> String.to_charlist()
  defp flagged?(
         {:|>, _,
          [
            {{:., _, [{:__aliases__, _, [:Integer]}, :to_string]}, _, _args},
            {{:., _, [{:__aliases__, _, [:String]}, :to_charlist]}, _, _}
          ]}
       ),
       do: true

  # Piped 3-step: n |> Integer.to_string(base) |> String.to_charlist()
  defp flagged?(
         {:|>, _,
          [
            {:|>, _, [_, {{:., _, [{:__aliases__, _, [:Integer]}, :to_string]}, _, _}]},
            {{:., _, [{:__aliases__, _, [:String]}, :to_charlist]}, _, _}
          ]}
       ),
       do: true

  defp flagged?(_), do: false

  defp extract_meta({{:., _, _}, meta, _}), do: meta
  defp extract_meta({:|>, meta, _}), do: meta
  defp extract_meta(_), do: []

  defp build_issue(meta) do
    %Issue{
      rule: :no_integer_to_string_digits,
      message:
        "Avoid `Integer.to_string/2 |> String.to_charlist/1` to extract digits. " <>
          "Use `Integer.digits/2` instead — it produces the digit list directly without intermediate string allocation.",
      meta: %{line: Keyword.get(meta, :line)}
    }
  end
end
