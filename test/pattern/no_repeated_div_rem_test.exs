defmodule Credence.Pattern.NoRepeatedDivRemTest do
  use ExUnit.Case

  alias Credence.Pattern.NoRepeatedDivRem

  defp check(code) do
    ast = Sourceror.parse_string!(code)
    NoRepeatedDivRem.check(ast, [])
  end

  describe "NoRepeatedDivRem" do
    test "detects div/2 called twice with same args in same clause" do
      code = """
      defmodule Bad do
        defp loop(number, count) do
          new_count = count + div(number, 5)
          loop(div(number, 5), new_count)
        end
      end
      """

      [issue] = check(code)
      assert issue.rule == :no_repeated_div_rem
      assert issue.message =~ "div(number, 5)"
      assert issue.message =~ "multiple times"
    end

    test "detects rem/2 called twice with same args" do
      code = """
      defmodule Bad do
        defp check(x) do
          a = rem(x, 2)
          b = rem(x, 2)
          {a, b}
        end
      end
      """

      [issue] = check(code)
      assert issue.rule == :no_repeated_div_rem
      assert issue.message =~ "rem(x, 2)"
    end

    test "detects div/2 called three times" do
      code = """
      defmodule Bad do
        defp f(x) do
          div(x, 5) + div(x, 5) + div(x, 5)
        end
      end
      """

      [issue] = check(code)
      assert issue.rule == :no_repeated_div_rem
    end

    test "detects repeated div in one clause but not another" do
      code = """
      defmodule Bad do
        defp f(x) when x < 5, do: x
        defp f(x) do
          new_x = div(x, 5)
          f(div(x, 5) + new_x)
        end
      end
      """

      issues = check(code)
      assert length(issues) == 1
    end

    # ---- Negative cases ----

    test "does not flag single div/2 call" do
      code = """
      defmodule Good do
        defp f(x) do
          div(x, 5)
        end
      end
      """

      assert check(code) == []
    end

    test "does not flag div/2 with different first arg" do
      code = """
      defmodule Good do
        defp f(x, y) do
          div(x, 5) + div(y, 5)
        end
      end
      """

      assert check(code) == []
    end

    test "does not flag div/2 with different second arg" do
      code = """
      defmodule Good do
        defp f(x) do
          div(x, 5) + div(x, 3)
        end
      end
      """

      assert check(code) == []
    end

    test "does not flag div/2 and rem/2 with same args" do
      code = """
      defmodule Good do
        defp f(x) do
          div(x, 5) + rem(x, 5)
        end
      end
      """

      assert check(code) == []
    end

    test "does not flag div/2 in different clauses" do
      code = """
      defmodule Good do
        defp f(x) when x > 0, do: div(x, 5)
        defp f(x), do: div(x, 5)
      end
      """

      assert check(code) == []
    end

    test "does not flag other repeated function calls" do
      code = """
      defmodule Good do
        defp f(x) do
          IO.puts(x)
          IO.puts(x)
        end
      end
      """

      assert check(code) == []
    end

    test "does not flag div in a non-def function" do
      code = """
      defmodule Good do
        def f(x) do
          g = fn y -> div(y, 5) end
          div(x, 5) + g.(x)
        end
      end
      """

      # div(x, 5) appears once in the outer scope; div(y, 5) in the lambda has different arg
      assert check(code) == []
    end
  end
end
