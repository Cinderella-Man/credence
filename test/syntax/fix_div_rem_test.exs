defmodule Credence.Syntax.FixDivRemTest do
  use ExUnit.Case

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
      source = "x = a div b\n"
      fixed = FixDivRem.fix(source)
      assert fixed =~ "div(a, b)"
      refute fixed =~ "a div b"
    end

    test "fixes simple infix rem" do
      source = "x = a rem b\n"
      fixed = FixDivRem.fix(source)
      assert fixed =~ "rem(a, b)"
      refute fixed =~ "a rem b"
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

      fixed = FixDivRem.fix(source)
      assert fixed =~ "div(n, 2)"
      refute fixed =~ "n div 2"
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

      fixed = FixDivRem.fix(source)
      assert fixed =~ "div(n * (n + 1), 2)"
      refute fixed =~ "div 2"
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

      fixed = FixDivRem.fix(source)
      assert fixed =~ "div(a, b)"
      assert fixed =~ "rem(a, b)"
    end

    test "does not modify valid function call syntax" do
      source = """
      defmodule Example do
        def half(n), do: div(n, 2)
      end
      """

      assert FixDivRem.fix(source) == source
    end

    test "does not rewrite infix rem inside capture" do
      source = """
      defmodule Example do
        def check(list) do
          Enum.map(list, &(&1 rem 2 == 0))
        end
      end
      """

      assert FixDivRem.fix(source) == source
    end

    test "does not modify pipe syntax" do
      source = """
      defmodule Example do
        def half(n), do: n |> div(2)
      end
      """

      assert FixDivRem.fix(source) == source
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
      assert {:ok, _} = Sourceror.parse_string(fixed)
    end
  end
end
