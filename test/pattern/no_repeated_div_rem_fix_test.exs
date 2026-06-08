defmodule Credence.Pattern.NoRepeatedDivRemFixTest do
  use Credence.RuleCase, async: true

  alias Credence.Pattern.NoRepeatedDivRem

  describe "reuses the anchor binding" do
    test "rem bound then recomputed verbatim" do
      code = """
      defmodule Bad do
        defp check(x) do
          a = rem(x, 2)
          b = rem(x, 2)
          {a, b}
        end
      end
      """

      expected = """
      defmodule Bad do
        defp check(x) do
          a = rem(x, 2)
          b = a
          {a, b}
        end
      end
      """

      assert fix(NoRepeatedDivRem, code) == expected
    end

    test "div recomputed inside a later call" do
      code = """
      defmodule Bad do
        defp f(x) when x < 5, do: x

        defp f(x) do
          new_x = div(x, 5)
          f(div(x, 5) + new_x)
        end
      end
      """

      expected = """
      defmodule Bad do
        defp f(x) when x < 5, do: x

        defp f(x) do
          new_x = div(x, 5)
          f(new_x + new_x)
        end
      end
      """

      assert fix(NoRepeatedDivRem, code) == expected
    end

    test "anchor recomputed three times" do
      code = """
      defmodule Bad do
        defp f(x) do
          q = div(x, 5)
          a = div(x, 5)
          b = div(x, 5)
          {q, a, b}
        end
      end
      """

      expected = """
      defmodule Bad do
        defp f(x) do
          q = div(x, 5)
          a = q
          b = q
          {q, a, b}
        end
      end
      """

      assert fix(NoRepeatedDivRem, code) == expected
    end

    test "variable divisor recomputed" do
      code = """
      defmodule Bad do
        defp f(x, n) do
          q = div(x, n)
          q + div(x, n)
        end
      end
      """

      expected = """
      defmodule Bad do
        defp f(x, n) do
          q = div(x, n)
          q + q
        end
      end
      """

      assert fix(NoRepeatedDivRem, code) == expected
    end
  end

  describe "no-ops outside the safe core" do
    test "first occurrence is a sub-expression" do
      code = """
      defmodule Skip do
        defp loop(number, count) do
          new_count = count + div(number, 5)
          loop(div(number, 5), new_count)
        end
      end
      """

      assert fix(NoRepeatedDivRem, code) == code
    end

    test "single-expression body" do
      code = """
      defmodule Skip do
        defp f(x) do
          div(x, 5) + div(x, 5) + div(x, 5)
        end
      end
      """

      assert fix(NoRepeatedDivRem, code) == code
    end

    test "argument variable rebound" do
      code = """
      defmodule Skip do
        defp f(x) do
          q = div(x, 5)
          x = x + 1
          q + div(x, 5)
        end
      end
      """

      assert fix(NoRepeatedDivRem, code) == code
    end

    test "argument shadowed inside a closure occurrence" do
      code = """
      defmodule Skip do
        defp f(x) do
          q = div(x, 5)
          g = fn x -> div(x, 5) end
          q + g.(10)
        end
      end
      """

      assert fix(NoRepeatedDivRem, code) == code
    end

    test "side-effecting argument" do
      code = """
      defmodule Skip do
        defp f do
          q = div(side(), 5)
          q + div(side(), 5)
        end
      end
      """

      assert fix(NoRepeatedDivRem, code) == code
    end
  end

  describe "round-trip" do
    test "fixed code raises no further issues" do
      code = """
      defmodule Bad do
        defp f(x) do
          q = div(x, 5)
          a = div(x, 5)
          b = div(x, 5)
          {q, a, b}
        end
      end
      """

      assert check(NoRepeatedDivRem, fix(NoRepeatedDivRem, code)) == []
    end

    test "fixed code is valid Elixir" do
      code = """
      defmodule Bad do
        defp check(x) do
          a = rem(x, 2)
          b = rem(x, 2)
          {a, b}
        end
      end
      """

      assert valid_syntax?(fix(NoRepeatedDivRem, code))
    end
  end
end
