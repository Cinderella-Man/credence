defmodule Credence.Pattern.PreferIntegerDigitsForFirstDigit do
  @moduledoc """
  Detects the anti-pattern of extracting the first digit of a number
  via string conversion, and rewrites it to use `Integer.digits/1` instead.

  ## Bad

      number
      |> abs()
      |> to_string()
      |> String.first()
      |> String.to_integer()

  ## Good

      number
      |> abs()
      |> Integer.digits()
      |> hd()

  The string-based approach is less efficient and less idiomatic than
  using `Integer.digits/1` which returns a list of digits directly.
  """
  use Credence.Pattern.Rule
  alias Credence.Issue

  @impl true
  def check(ast, _opts) do
    {_ast, issues} =
      Macro.prewalk(ast, [], fn node, issues ->
        case detect_pattern(node) do
          {:ok, meta} -> {node, [create_issue(meta) | issues]}
          :error -> {node, issues}
        end
      end)

    Enum.reverse(issues)
  end

  @impl true
  def fix_patches(ast, _opts) do
    Credence.RuleHelpers.patches_from_postwalk(ast, fn node ->
      case detect_pattern(node) do
        {:ok, _meta} ->
          rewrite_pipe(node)

        :error ->
          node
      end
    end)
  end

  # Detect the anti-pattern:
  # <base> |> abs() |> to_string() |> String.first() |> String.to_integer()
  #
  # The outermost pipe ends with String.to_integer(String.first(...))
  defp detect_pattern({:|>, meta, [inner, {{:., _, [{:__aliases__, _, [:String]}, :to_integer]}, _, []}]}) do
    case inner do
      {:|>, _, [_, {{:., _, [{:__aliases__, _, [:String]}, :first]}, _, []}]} ->
        # Check that the inner pipeline has to_string and abs
        case extract_pipe_chain(inner) do
          {:ok, chain} ->
            if has_to_string_and_abs?(chain) do
              {:ok, meta}
            else
              :error
            end

          :error ->
            :error
        end

      _ ->
        :error
    end
  end

  defp detect_pattern(_), do: :error

  # Extract the list of operations from a pipe chain
  defp extract_pipe_chain({:|>, _, [left, right]}) do
    case extract_pipe_chain(left) do
      {:ok, chain} -> {:ok, chain ++ [right]}
      :error -> {:ok, [left, right]}
    end
  end

  defp extract_pipe_chain(_), do: :error

  # Check if the chain contains to_string and abs operations
  defp has_to_string_and_abs?(chain) do
    ops = Enum.map(chain, &operation_name/1)
    :to_string in ops and :abs in ops
  end

  defp operation_name({:abs, _, []}), do: :abs
  defp operation_name({:to_string, _, []}), do: :to_string
  defp operation_name({{:., _, [{:__aliases__, _, [:String]}, :first]}, _, []}), do: :string_first
  defp operation_name({{:., _, [{:__aliases__, _, [:String]}, :to_integer]}, _, []}), do: :string_to_integer
  defp operation_name(_), do: :other

  # Extract the base expression (first element) from a pipe chain
  defp extract_base({:|>, _, [left, _right]}) do
    case extract_base(left) do
      {:ok, base} -> {:ok, base}
      :error -> {:ok, left}
    end
  end

  defp extract_base(_), do: :error

  # Rewrite the pipe chain to use Integer.digits() |> hd()
  defp rewrite_pipe({:|>, _, [inner, {{:., _, [{:__aliases__, _, [:String]}, :to_integer]}, _, []}]}) do
    case extract_base(inner) do
      {:ok, base} ->
        build_rewrite(base)

      :error ->
        # Shouldn't happen if detect_pattern passed, but fallback
        build_rewrite(inner)
    end
  end

  defp build_rewrite(base) do
    # Build: base |> abs() |> Integer.digits() |> hd()
    pipe1 = {:|>, [], [base, {:abs, [], []}]}
    pipe2 = {:|>, [], [pipe1, {{:., [], [{:__aliases__, [], [:Integer]}, :digits]}, [], []}]}
    {:|>, [], [pipe2, {:hd, [], []}]}
  end

  defp create_issue(meta) do
    %Issue{
      rule: :prefer_integer_digits_for_first_digit,
      message:
        "Pattern to avoid:\n" <>
          "  number |> abs() |> to_string() |> String.first() |> String.to_integer()\n\n" <>
          "Use instead:\n" <>
          "  number |> abs() |> Integer.digits() |> hd()\n\n" <>
          "Reason:\n" <>
          "- String conversion is less efficient for digit extraction.\n" <>
          "- Integer.digits/1 returns digits directly as a list.\n" <>
          "- Using hd/1 to get the first digit is more idiomatic.",
      meta: %{line: Keyword.get(meta, :line)}
    }
  end
end
