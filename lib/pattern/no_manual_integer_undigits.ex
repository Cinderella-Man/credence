defmodule Credence.Pattern.NoManualIntegerUndigits do
  @moduledoc """
  Detects manual base-to-decimal conversion via `Enum.reduce` that can be
  replaced with `Integer.undigits/2`.

  `Integer.undigits(digits, base)` converts a list of digits in the given
  base to its decimal equivalent. When code manually reduces a digit list
  with `acc * base + digit`, `Integer.undigits/2` is clearer and more
  idiomatic.

  ## Bad

      Enum.reduce(digits, 0, fn digit, acc -> acc * 2 + digit end)
      Enum.reduce(digits, 0, fn digit, acc -> digit + acc * 10 end)

  ## Good

      Integer.undigits(digits, 2)
      Integer.undigits(digits, 10)
  """
  use Credence.Pattern.Rule
  alias Credence.Issue

  @impl true
  def priority, do: 501

  @impl true
  def check(ast, _opts) do
    {_ast, issues} =
      Macro.prewalk(ast, [], fn
        # Direct call: Enum.reduce(digits, 0, fn digit, acc -> acc * base + digit end)
        {{:., _, [{:__aliases__, _, [:Enum]}, :reduce]}, meta, [_digits, zero, lambda]} = node,
        issues ->
          case undigits_body?(zero, lambda) do
            {:ok, _base} -> {node, [build_issue(meta) | issues]}
            :error -> {node, issues}
          end

        # Pipeline: digits |> Enum.reduce(0, fn digit, acc -> acc * base + digit end)
        {:|>, _,
         [
           _digits,
           {{:., _, [{:__aliases__, _, [:Enum]}, :reduce]}, meta, [zero, lambda]}
         ]} = node,
        issues ->
          case undigits_body?(zero, lambda) do
            {:ok, _base} -> {node, [build_issue(meta) | issues]}
            :error -> {node, issues}
          end

        node, issues ->
          {node, issues}
      end)

    Enum.reverse(issues)
  end

  @impl true
  def fix_patches(ast, _opts) do
    Credence.RuleHelpers.patches_from_postwalk(ast, fn
      # Direct call form
      {{:., _, [{:__aliases__, _, [:Enum]}, :reduce]}, _, [digits, zero, lambda]} = node ->
        case undigits_body?(zero, lambda) do
          {:ok, base} -> integer_undigits_call(digits, base)
          :error -> node
        end

      # Pipeline form
      {:|>, pipe_meta,
       [
         digits,
         {{:., _, [{:__aliases__, _, [:Enum]}, :reduce]}, _, [zero, lambda]}
       ]} = node ->
        case undigits_body?(zero, lambda) do
          {:ok, base} -> {:|>, pipe_meta, [digits, integer_undigits_pipe_call(base)]}
          :error -> node
        end

      node ->
        node
    end)
  end

  # Matches the lambda body: acc * base + digit (and commutative variants)
  # Returns {:ok, base} or :error
  defp undigits_body?(zero, {:fn, _, [{:->, _, [[{d1, _, _}, {a1, _, _}], body]}]})
       when is_atom(d1) and is_atom(a1) do
    with true <- zero_literal?(zero),
         {:ok, base} <- extract_undigits_expr(body, d1, a1) do
      {:ok, base}
    else
      _ -> :error
    end
  end

  defp undigits_body?(_, _), do: :error

  defp zero_literal?(0), do: true
  defp zero_literal?({:__block__, _, [0]}), do: true
  defp zero_literal?(_), do: false

  # acc * base + digit
  defp extract_undigits_expr({:+, _, [mult, {d, _, _}]}, d, a)
       when is_atom(d) do
    case mult do
      {:*, _, [{a2, _, _}, base]} when is_atom(a2) and a2 == a -> literal_positive_int(base)
      {:*, _, [base, {a2, _, _}]} when is_atom(a2) and a2 == a -> literal_positive_int(base)
      _ -> :error
    end
  end

  # digit + acc * base
  defp extract_undigits_expr({:+, _, [{d, _, _}, mult]}, d, a)
       when is_atom(d) do
    case mult do
      {:*, _, [{a2, _, _}, base]} when is_atom(a2) and a2 == a -> literal_positive_int(base)
      {:*, _, [base, {a2, _, _}]} when is_atom(a2) and a2 == a -> literal_positive_int(base)
      _ -> :error
    end
  end

  defp extract_undigits_expr(_, _, _), do: :error

  defp literal_positive_int(n) when is_integer(n) and n > 1, do: {:ok, n}
  defp literal_positive_int({:__block__, _, [n]}) when is_integer(n) and n > 1, do: {:ok, n}
  defp literal_positive_int(_), do: :error

  defp integer_undigits_call(digits, base) do
    {{:., [], [{:__aliases__, [], [:Integer]}, :undigits]}, [],
     [digits, base]}
  end

  defp integer_undigits_pipe_call(base) do
    {{:., [], [{:__aliases__, [], [:Integer]}, :undigits]}, [], [base]}
  end

  defp build_issue(meta) do
    %Issue{
      rule: :no_manual_integer_undigits,
      message:
        "Manual digit-list-to-integer conversion via `Enum.reduce` detected. " <>
          "Prefer `Integer.undigits/2` which is clearer and purpose-built for this.",
      meta: %{line: Keyword.get(meta, :line)}
    }
  end
end
