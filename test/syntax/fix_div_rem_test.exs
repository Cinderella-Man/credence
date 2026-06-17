defmodule Credence.Syntax.FixDivRemTest do
  use ExUnit.Case

  import Credence.RuleCase, only: [confirm_fix: 2, valid_syntax?: 1]

  alias Credence.Syntax.FixDivRem

  describe "analyze/1" do
    test "detects infix div" do
      source = """
      defmodule Example do
        def half(n), do: n div 2
      end
      """

      issues = FixDivRem.analyze(source)
      assert length(issues) == 1
      assert hd(issues).rule == :infix_div
      assert hd(issues).message =~ "div"
    end

    test "detects infix rem" do
      source = """
      defmodule Example do
        def odd?(n), do: n rem 2 != 0
      end
      """

      issues = FixDivRem.analyze(source)
      assert length(issues) == 1
      assert hd(issues).rule == :infix_rem
    end

    test "detects div in complex expression" do
      source = """
      defmodule Example do
        def gauss(n) do
          n * (n + 1) div 2
        end
      end
      """

      issues = FixDivRem.analyze(source)
      assert length(issues) == 1
    end

    test "detects multiple infix operators" do
      source = """
      defmodule Example do
        def compute(a, b) do
          x = a div b
          y = a rem b
          {x, y}
        end
      end
      """

      issues = FixDivRem.analyze(source)
      assert length(issues) == 2
      rules = Enum.map(issues, & &1.rule) |> Enum.sort()
      assert rules == [:infix_div, :infix_rem]
    end

    test "no issues for valid function call syntax" do
      source = """
      defmodule Example do
        def half(n), do: div(n, 2)
        def remainder(n), do: rem(n, 2)
      end
      """

      assert FixDivRem.analyze(source) == []
    end

    test "no issues for pipe syntax" do
      source = """
      defmodule Example do
        def half(n), do: n |> div(2)
      end
      """

      assert FixDivRem.analyze(source) == []
    end

    test "detects infix rem inside capture" do
      source = """
      defmodule Example do
        def check(list) do
          Enum.map(list, &(&1 rem 2 == 0))
        end
      end
      """

      issues = FixDivRem.analyze(source)
      assert length(issues) == 1
      assert hd(issues).rule == :infix_rem
    end

    test "no issues for div in comments" do
      source = """
      defmodule Example do
        # use div to divide
        def half(n), do: div(n, 2)
      end
      """

      assert FixDivRem.analyze(source) == []
    end
  end

  describe "fix/1" do
    test "fixes simple infix div" do
      source = "x = a div b"

      expected = "x = div(a, b)"

      confirm_fix(FixDivRem.fix(source), expected)
    end

    test "fixes simple infix rem" do
      source = "x = a rem b"

      expected = "x = rem(a, b)"

      confirm_fix(FixDivRem.fix(source), expected)
    end

    test "fixes div with assignment" do
      source = """
      defmodule Example do
        def half(n) do
          result = n div 2
          result
        end
      end
      """

      expected = """
      defmodule Example do
        def half(n) do
          result = div(n, 2)
          result
        end
      end
      """

      confirm_fix(FixDivRem.fix(source), expected)
    end

    test "fixes complex left operand" do
      source = """
      defmodule Example do
        def gauss(n) do
          expected_sum = n * (n + 1) div 2
          expected_sum
        end
      end
      """

      expected = """
      defmodule Example do
        def gauss(n) do
          expected_sum = div(n * (n + 1), 2)
          expected_sum
        end
      end
      """

      confirm_fix(FixDivRem.fix(source), expected)
    end

    test "fixes both div and rem in same file" do
      source = """
      defmodule Example do
        def compute(a, b) do
          x = a div b
          y = a rem b
          {x, y}
        end
      end
      """

      expected = """
      defmodule Example do
        def compute(a, b) do
          x = div(a, b)
          y = rem(a, b)
          {x, y}
        end
      end
      """

      confirm_fix(FixDivRem.fix(source), expected)
    end

    test "does not modify valid function call syntax" do
      source = """
      defmodule Example do
        def half(n), do: div(n, 2)
      end
      """

      confirm_fix(FixDivRem.fix(source), source)
    end

    test "does not rewrite infix rem inside capture" do
      source = """
      defmodule Example do
        def check(list) do
          Enum.map(list, &(&1 rem 2 == 0))
        end
      end
      """

      confirm_fix(FixDivRem.fix(source), source)
    end

    test "does not modify pipe syntax" do
      source = """
      defmodule Example do
        def half(n), do: n |> div(2)
      end
      """

      confirm_fix(FixDivRem.fix(source), source)
    end

    test "fixed code produces valid Elixir" do
      source = """
      defmodule FixDivTest do
        def gauss(n) do
          n * (n + 1) div 2
        end
      end
      """

      fixed = FixDivRem.fix(source)
      assert valid_syntax?(fixed)
    end

    test "fix reaches a fixpoint — fixed output no longer flags" do
      source = "x = a div b"

      assert FixDivRem.analyze(FixDivRem.fix(source)) == []
    end

    test "fix output is well-formed (parses)" do
      assert valid_syntax?(
               FixDivRem.fix("""
               x = a div b
               """)
             )
    end

    test "does not mangle div inside function call arguments" do
      source = """
          moves_minus = do_minto1((n - 1) div 2, 0)
          moves_plus = do_minto1((n + 1) div 2, 0)
      """

      expected = """
          moves_minus = do_minto1(Kernel.div((n - 1), 2), 0)
          moves_plus = do_minto1(Kernel.div((n + 1), 2), 0)
      """

      confirm_fix(FixDivRem.fix(source), expected)
    end

    test "fixed code with function args produces valid Elixir" do
      source = """
      defmodule KernelDivTest do
        def minto1(n) do
          moves_minus = do_minto1((n - 1) div 2, 0)
          moves_plus = do_minto1((n + 1) div 2, 0)
          min(moves_minus, moves_plus)
        end

        defp do_minto1(1, moves), do: moves
        defp do_minto1(n, moves), do: do_minto1(div(n, 2), moves + 1)
      end
      """

      fixed = FixDivRem.fix(source)
      assert valid_syntax?(fixed)
    end
  end
end
