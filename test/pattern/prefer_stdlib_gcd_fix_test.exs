defmodule Credence.Pattern.PreferStdlibGcdFixTest do
  use Credence.RuleCase, async: true

  alias Credence.Pattern.PreferStdlibGcd

  test "replaces hand-rolled gcd with Integer.gcd and removes defp clauses" do
    input = """
    defmodule Solution do
      def smallest_common_mult(first, second) do
        div(first * second, gcd(first, second))
      end

      defp gcd(a, 0), do: a
      defp gcd(a, b), do: gcd(b, rem(a, b))
    end
    """

    expected = """
    defmodule Solution do
      def smallest_common_mult(first, second) do
        div(first * second, Integer.gcd(first, second))
      end
    end
    """

    confirm_fix(fix(PreferStdlibGcd, input), expected)
  end

  test "does not modify code that already uses Integer.gcd/2" do
    code = """
    defmodule Solution do
      def smallest_common_mult(first, second) do
        div(first * second, Integer.gcd(first, second))
      end
    end
    """

    confirm_fix(fix(PreferStdlibGcd, code), code)
  end

  test "round-trip: fixed code produces no issues" do
    input = """
    defmodule Solution do
      def smallest_common_mult(first, second) do
        div(first * second, gcd(first, second))
      end

      defp gcd(a, 0), do: a
      defp gcd(a, b), do: gcd(b, rem(a, b))
    end
    """

    assert check(PreferStdlibGcd, fix(PreferStdlibGcd, input)) == []
  end
end
