defmodule Credence.Pattern.NoRepeatedDivRemCheckTest do
  use Credence.RuleCase, async: true

  alias Credence.Pattern.NoRepeatedDivRem

  describe "flags an anchored, recomputed div/rem" do
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

      [issue] = check(NoRepeatedDivRem, code)
      assert issue.rule == :no_repeated_div_rem

      assert issue.message ==
               "`rem(x, 2)` is already bound to `a` and recomputed " <>
                 "later in the same scope. Reuse `a` instead."
    end

    test "div bound then recomputed inside a later call" do
      code = """
      defmodule Bad do
        defp f(x) when x < 5, do: x

        defp f(x) do
          new_x = div(x, 5)
          f(div(x, 5) + new_x)
        end
      end
      """

      assert [%{rule: :no_repeated_div_rem}] = check(NoRepeatedDivRem, code)
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

      assert [%{rule: :no_repeated_div_rem}] = check(NoRepeatedDivRem, code)
    end

    test "literal divisor that is a variable is still anchored" do
      code = """
      defmodule Bad do
        defp f(x, n) do
          q = div(x, n)
          q + div(x, n)
        end
      end
      """

      assert [%{rule: :no_repeated_div_rem}] = check(NoRepeatedDivRem, code)
    end
  end

  describe "no issue — outside the safe core" do
    test "first occurrence is a sub-expression, not a clean binding" do
      # The canonical moduledoc 'Bad': the first occurrence is buried inside
      # `count + div(...)`, so there is no anchor to reuse safely.
      code = """
      defmodule Skip do
        defp loop(number, count) do
          new_count = count + div(number, 5)
          loop(div(number, 5), new_count)
        end
      end
      """

      assert check(NoRepeatedDivRem, code) == []
    end

    test "single-expression body with repeated call (no anchor binding)" do
      code = """
      defmodule Skip do
        defp f(x) do
          div(x, 5) + div(x, 5) + div(x, 5)
        end
      end
      """

      assert check(NoRepeatedDivRem, code) == []
    end

    test "argument variable is rebound in the body" do
      code = """
      defmodule Skip do
        defp f(x) do
          q = div(x, 5)
          x = x + 1
          q + div(x, 5)
        end
      end
      """

      assert check(NoRepeatedDivRem, code) == []
    end

    test "anchor variable is rebound later" do
      code = """
      defmodule Skip do
        defp f(x) do
          q = div(x, 5)
          q = q + 1
          q + div(x, 5)
        end
      end
      """

      assert check(NoRepeatedDivRem, code) == []
    end

    test "argument variable is shadowed inside a closure that holds an occurrence" do
      code = """
      defmodule Skip do
        defp f(x) do
          q = div(x, 5)
          g = fn x -> div(x, 5) end
          q + g.(10)
        end
      end
      """

      assert check(NoRepeatedDivRem, code) == []
    end

    test "non-trivial (side-effecting) argument" do
      code = """
      defmodule Skip do
        defp f do
          q = div(side(), 5)
          q + div(side(), 5)
        end
      end
      """

      assert check(NoRepeatedDivRem, code) == []
    end

    test "single div call" do
      code = """
      defmodule Skip do
        defp f(x) do
          y = div(x, 5)
          y + 1
        end
      end
      """

      assert check(NoRepeatedDivRem, code) == []
    end

    test "different second argument" do
      code = """
      defmodule Skip do
        defp f(x) do
          a = div(x, 5)
          a + div(x, 3)
        end
      end
      """

      assert check(NoRepeatedDivRem, code) == []
    end

    test "div and rem with same args are different calls" do
      code = """
      defmodule Skip do
        defp f(x) do
          a = div(x, 5)
          a + rem(x, 5)
        end
      end
      """

      assert check(NoRepeatedDivRem, code) == []
    end

    test "occurrences live in different clauses" do
      code = """
      defmodule Skip do
        defp f(x) when x > 0 do
          y = div(x, 5)
          y + 1
        end

        defp f(x) do
          y = div(x, 5)
          y + 2
        end
      end
      """

      assert check(NoRepeatedDivRem, code) == []
    end

    test "repeated non-arithmetic call is not flagged" do
      code = """
      defmodule Skip do
        defp f(x) do
          a = foo(x, 5)
          a + foo(x, 5)
        end
      end
      """

      assert check(NoRepeatedDivRem, code) == []
    end
  end
end
