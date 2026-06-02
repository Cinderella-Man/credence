defmodule Credence.Pattern.NoRemForParityCheck do
  @moduledoc """
  Detects manual parity checks via `rem/2` when `Integer.is_even/1` or
  `Integer.is_odd/1` exists (Elixir 1.14+).

  ## Examples

      # Bad
      rem(x, 2) == 0
      rem(x, 2) != 0
      rem(x, 2) == 1
      rem(x, 2) != 1

      # Good
      Integer.is_even(x)
      Integer.is_odd(x)
      Integer.is_odd(x)
      Integer.is_even(x)

  Works in any expression context including guards (since `Integer.is_even/1`
  and `Integer.is_odd/1` are guard-safe since Elixir 1.14).
  """

  use Credence.Pattern.Rule
  alias Credence.Issue

  @impl true
  def check(ast, _opts) do
    {_ast, issues} =
      Macro.prewalk(ast, [], fn
        node, acc ->
          case match_parity_check(node) do
            {:ok, _var, replacement} ->
              meta = elem(node, 1) || []
              issue = %Issue{
                rule: :no_rem_for_parity_check,
                message:
                  "Manual parity check via `rem/2`. Prefer `#{replacement}/1`.",
                meta: %{line: Keyword.get(meta, :line)}
              }

              {node, [issue | acc]}

            :error ->
              {node, acc}
          end
      end)

    Enum.reverse(issues)
  end

  @impl true
  def fix_patches(ast, _opts) do
    Credence.RuleHelpers.patches_from_postwalk(ast, fn node ->
      case match_parity_check(node) do
        {:ok, var_ast, replacement} ->
          {{:., [], [{:__aliases__, [], [:Integer]}, replacement]}, [], [var_ast]}

        :error ->
          node
      end
    end)
  end

  # Match: rem(x, 2) == 0  →  Integer.is_even(x)
  # Match: 0 == rem(x, 2)  →  Integer.is_even(x)
  # Match: rem(x, 2) != 0  →  Integer.is_odd(x)
  # Match: 0 != rem(x, 2)  →  Integer.is_odd(x)
  # Match: rem(x, 2) == 1  →  Integer.is_odd(x)
  # Match: 1 == rem(x, 2)  →  Integer.is_odd(x)
  # Match: rem(x, 2) != 1  →  Integer.is_even(x)
  # Match: 1 != rem(x, 2)  →  Integer.is_even(x)

  defp match_parity_check({:==, _, [left, right]}), do: match_eq(:eq, left, right)
  defp match_parity_check({:!=, _, [left, right]}), do: match_eq(:neq, left, right)
  defp match_parity_check(_), do: :error

  defp match_eq(op, left, right) do
    with {:ok, var_ast, val} <- extract_rem_and_val(left, right),
         replacement when replacement != nil <- replacement_for(op, val) do
      {:ok, var_ast, replacement}
    else
      _ ->
        with {:ok, var_ast, val} <- extract_rem_and_val(right, left),
             replacement when replacement != nil <- replacement_for(op, val) do
          {:ok, var_ast, replacement}
        else
          _ -> :error
        end
    end
  end

  defp extract_rem_and_val(rem_node, val_node) do
    with {:ok, var_ast} <- extract_rem_var(rem_node),
         {:ok, val} <- extract_int(val_node) do
      {:ok, var_ast, val}
    end
  end

  # rem(x, 2) — auto-imported Kernel.rem
  defp extract_rem_var({:rem, _, [var_ast, divisor]}) do
    case extract_int(divisor) do
      {:ok, 2} -> {:ok, var_ast}
      _ -> :error
    end
  end

  # Kernel.rem(x, 2) — explicit module call
  defp extract_rem_var({{:., _, [{:__aliases__, _, [:Kernel]}, :rem]}, _, [var_ast, divisor]}) do
    case extract_int(divisor) do
      {:ok, 2} -> {:ok, var_ast}
      _ -> :error
    end
  end

  defp extract_rem_var(_), do: :error

  defp extract_int({:__block__, _, [val]}) when is_integer(val), do: {:ok, val}
  defp extract_int(val) when is_integer(val), do: {:ok, val}
  defp extract_int(_), do: :error

  # op == :eq means ==, op == :neq means !=
  # val is 0 or 1
  defp replacement_for(:eq, 0), do: :is_even
  defp replacement_for(:eq, 1), do: :is_odd
  defp replacement_for(:neq, 0), do: :is_odd
  defp replacement_for(:neq, 1), do: :is_even
  defp replacement_for(_, _), do: nil
end
