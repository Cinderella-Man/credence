defmodule Credence.Pattern.NoRedundantLocalCaptureFixTest do
  use Credence.RuleCase, async: true

  alias Credence.Pattern.NoRedundantLocalCapture

  test "rewrites the anti-pattern" do
    input = """
    defmodule Example do
      def example(n) do
        factorial = &factorial/1
        div(factorial.(2 * n), div(factorial.(n) * factorial.(n + 1), 1))
      end

      defp factorial(0), do: 1
      defp factorial(n) when n > 0 do
        Enum.product(1..n)
      end
    end
    """

    expected = """
    defmodule Example do
      def example(n) do
        div(factorial(2 * n), div(factorial(n) * factorial(n + 1), 1))
      end

      defp factorial(0), do: 1
      defp factorial(n) when n > 0 do
        Enum.product(1..n)
      end
    end
    """

    assert fix(NoRedundantLocalCapture, input) == expected
  end

  test "rewrites capture into differently-named variable" do
    input = """
    defmodule Example do
      def example(x) do
        f = &double/1
        f.(x)
      end

      defp double(n), do: n * 2
    end
    """

    expected = """
    defmodule Example do
      def example(x) do
        double(x)
      end

      defp double(n), do: n * 2
    end
    """

    assert fix(NoRedundantLocalCapture, input) == expected
  end

  test "leaves direct function calls unchanged" do
    code = """
    defmodule Example do
      def example(n) do
        div(factorial(2 * n), div(factorial(n) * factorial(n + 1), 1))
      end

      defp factorial(0), do: 1
      defp factorial(n) when n > 0 do
        Enum.product(1..n)
      end
    end
    """

    assert fix(NoRedundantLocalCapture, code) == code
  end
end
