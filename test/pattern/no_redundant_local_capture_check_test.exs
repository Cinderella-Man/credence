defmodule Credence.Pattern.NoRedundantLocalCaptureCheckTest do
  use Credence.RuleCase, async: true

  alias Credence.Pattern.NoRedundantLocalCapture

  describe "flags the anti-pattern" do
    test "detects redundant local function capture with call" do
      code = """
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

      assert flagged?(NoRedundantLocalCapture, code)
    end

    test "detects capture of local function into differently-named variable" do
      code = """
      defmodule Example do
        def example(x) do
          f = &double/1
          f.(x)
        end

        defp double(n), do: n * 2
      end
      """

      assert flagged?(NoRedundantLocalCapture, code)
    end
  end

  describe "leaves good code alone" do
    test "passes direct function calls without capture" do
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

      assert clean?(NoRedundantLocalCapture, code)
    end

    test "passes module function captures" do
      code = """
      defmodule Example do
        def example(list) do
          mapper = &Enum.map/2
          mapper.(list, &(&1 + 1))
        end
      end
      """

      assert clean?(NoRedundantLocalCapture, code)
    end

    test "passes anonymous function application" do
      code = """
      defmodule Example do
        def example(x) do
          fun = fn y -> y * 2 end
          fun.(x)
        end
      end
      """

      assert clean?(NoRedundantLocalCapture, code)
    end
  end
end
