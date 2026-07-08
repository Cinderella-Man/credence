defmodule Credence.Semantic.FixNegationInGuardFixTest do
  use ExUnit.Case

  import Credence.RuleCase, only: [confirm_fix: 2, valid_syntax?: 1]

  alias Credence.Semantic.FixNegationInGuard

  @real_message "invalid expression in guard, ! is not allowed in guards. To learn more about guards, visit: https://hexdocs.pm/elixir/patterns-and-guards.html"

  defp fix(source, message \\ @real_message, line \\ 2) do
    FixNegationInGuard.fix(source, %{severity: :error, message: message, position: {line, 1}})
  end

  test "replaces ! with not in guard" do
    input = """
    defmodule ShipStockValidator do
      def validate(quantity, available) when !is_number(quantity) or quantity <= 0 do
        {:error, :invalid_quantity}
      end

      def validate(quantity, available) when quantity > available do
        {:error, :insufficient_stock}
      end

      def validate(_quantity, _available), do: :ok
    end
    """

    expected = """
    defmodule ShipStockValidator do
      def validate(quantity, available) when not is_number(quantity) or quantity <= 0 do
        {:error, :invalid_quantity}
      end

      def validate(quantity, available) when quantity > available do
        {:error, :insufficient_stock}
      end

      def validate(_quantity, _available), do: :ok
    end
    """

    confirm_fix(fix(input), expected)
  end

  test "fixed output is well-formed (parses)" do
    input = """
    defmodule ShipStockValidator do
      def validate(quantity, available) when !is_number(quantity) or quantity <= 0 do
        {:error, :invalid_quantity}
      end
    end
    """

    assert valid_syntax?(fix(input))
  end

  test "returns source unchanged when no ! in guard" do
    input = """
    defmodule CleanExample do
      def validate(quantity, available) when is_number(quantity), do: :ok
      def validate(_quantity, _available), do: :error
    end
    """

    confirm_fix(fix(input), input)
  end

  test "does not replace ! outside of guards" do
    input = """
    defmodule Example do
      def check(x) when !is_number(x), do: :error
      def negate(x), do: !x
    end
    """

    expected = """
    defmodule Example do
      def check(x) when not is_number(x), do: :error
      def negate(x), do: !x
    end
    """

    confirm_fix(fix(input), expected)
  end
end
