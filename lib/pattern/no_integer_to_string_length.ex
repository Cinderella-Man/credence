defmodule Credence.Pattern.NoIntegerToStringLength do
  @moduledoc """
  Performance rule: Detects converting an integer to a string representation
  in a given base and then calling `String.length/1` to count its digits,
  when `Integer.digits/2 |> length/1` avoids the intermediate string allocation.

  ## Bad

      String.length(Integer.to_string(number, 2))
      Integer.to_string(number, 2) |> String.length()
      number |> Integer.to_string(2) |> String.length()

  ## Good

      Integer.digits(number, 2) |> length()
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
  def fix_patches(ast, _opts) do
    Credence.RuleHelpers.patches_from_postwalk(ast, fn
      # Nested: String.length(Integer.to_string(n, base))
      {{:., _, [{:__aliases__, _, [:String]}, :length]}, _,
       [{{:., _, [{:__aliases__, _, [:Integer]}, :to_string]}, _, int_args}]} ->
        kernel_length_call(integer_digits_call(int_args))

      # Piped 2-step: Integer.to_string(n, base) |> String.length()
      {:|>, _,
       [
         {{:., _, [{:__aliases__, _, [:Integer]}, :to_string]}, _, int_args},
         {{:., _, [{:__aliases__, _, [:String]}, :length]}, _, _}
       ]} ->
        piped_integer_digits_length(int_args)

      # Piped 3-step: n |> Integer.to_string(base) |> String.length()
      {:|>, _,
       [
         {:|>, _, [n, {{:., _, [{:__aliases__, _, [:Integer]}, :to_string]}, _, pipe_args}]},
         {{:., _, [{:__aliases__, _, [:String]}, :length]}, _, _}
       ]} ->
        piped_integer_digits_length([n | pipe_args])

      node ->
        node
    end)
  end

  defp integer_digits_call(args) do
    {{:., [], [{:__aliases__, [], [:Integer]}, :digits]}, [], args}
  end

  defp kernel_length_call(arg) do
    {:length, [], [arg]}
  end

  defp piped_integer_digits_length(args) do
    {:|>, [], [integer_digits_call(args), {:length, [], []}]}
  end

  # Nested: String.length(Integer.to_string(n, base))
  defp flagged?(
         {{:., _, [{:__aliases__, _, [:String]}, :length]}, _,
          [{{:., _, [{:__aliases__, _, [:Integer]}, :to_string]}, _, _args}]}
       ),
       do: true

  # Piped 2-step: Integer.to_string(n, base) |> String.length()
  defp flagged?(
         {:|>, _,
          [
            {{:., _, [{:__aliases__, _, [:Integer]}, :to_string]}, _, _args},
            {{:., _, [{:__aliases__, _, [:String]}, :length]}, _, _}
          ]}
       ),
       do: true

  # Piped 3-step: n |> Integer.to_string(base) |> String.length()
  defp flagged?(
         {:|>, _,
          [
            {:|>, _, [_, {{:., _, [{:__aliases__, _, [:Integer]}, :to_string]}, _, _}]},
            {{:., _, [{:__aliases__, _, [:String]}, :length]}, _, _}
          ]}
       ),
       do: true

  defp flagged?(_), do: false

  defp extract_meta({{:., _, _}, meta, _}), do: meta
  defp extract_meta({:|>, meta, _}), do: meta
  defp extract_meta(_), do: []

  defp build_issue(meta) do
    %Issue{
      rule: :no_integer_to_string_length,
      message:
        "Avoid `Integer.to_string/2 |> String.length/1` to count digits. " <>
          "Use `Integer.digits/2 |> length/1` instead — it avoids intermediate string allocation.",
      meta: %{line: Keyword.get(meta, :line)}
    }
  end
end
