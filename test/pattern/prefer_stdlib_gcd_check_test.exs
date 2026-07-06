defmodule Credence.Pattern.PreferStdlibGcdCheckTest do
  use Credence.RuleCase, async: true

  alias Credence.Pattern.PreferStdlibGcd

  test "flags a module with hand-rolled Euclidean GCD" do
    code = """
    defmodule Solution do
      def smallest_common_mult(first, second) do
        div(first * second, gcd(first, second))
      end

      defp gcd(a, 0), do: a
      defp gcd(a, b), do: gcd(b, rem(a, b))
    end
    """

    assert flagged?(PreferStdlibGcd, code)
  end

  test "leaves code that already uses Integer.gcd/2 alone" do
    code = """
    defmodule Solution do
      def smallest_common_mult(first, second) do
        div(first * second, Integer.gcd(first, second))
      end
    end
    """

    assert clean?(PreferStdlibGcd, code)
  end

  test "leaves code without any gcd function alone" do
    code = """
    defmodule Solution do
      def add(a, b), do: a + b
    end
    """

    assert clean?(PreferStdlibGcd, code)
  end

  test "does not flag a single-clause gcd (not Euclidean pattern)" do
    code = """
    defmodule Solution do
      def compute(a, b) do
        gcd(a, b)
      end

      defp gcd(a, b), do: a + b
    end
    """

    assert clean?(PreferStdlibGcd, code)
  end
end
