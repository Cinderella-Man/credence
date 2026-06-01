defmodule Credence.Syntax.FixPythonFloorDivTest do
  use ExUnit.Case

  alias Credence.Syntax.FixPythonFloorDiv

  describe "analyze/1" do
    test "detects Kernel.// in pipe" do
      source = """
      defmodule Example do
        def step(acc, k) do
          acc
          |> Kernel.//(k)
          |> next()
        end
      end
      """

      issues = FixPythonFloorDiv.analyze(source)
      assert length(issues) == 1
      assert hd(issues).rule == :python_floor_div
      assert hd(issues).message =~ "div(a, b)"
    end

    test "detects Kernel.// standalone call" do
      source = """
      defmodule Example do
        def divide(a, b), do: Kernel.//(a, b)
      end
      """

      issues = FixPythonFloorDiv.analyze(source)
      assert length(issues) == 1
    end

    test "detects infix //" do
      source = """
      defmodule Example do
        def half(n), do: n // 2
      end
      """

      issues = FixPythonFloorDiv.analyze(source)
      assert length(issues) == 1
    end

    test "detects // with complex left operand" do
      source = """
      defmodule Example do
        def gauss(n) do
          result = n * (n + 1) // 2
          result
        end
      end
      """

      issues = FixPythonFloorDiv.analyze(source)
      assert length(issues) == 1
    end

    test "no issues for valid div function call" do
      source = """
      defmodule Example do
        def half(n), do: div(n, 2)
      end
      """

      assert FixPythonFloorDiv.analyze(source) == []
    end

    test "no issues for pipe into div" do
      source = """
      defmodule Example do
        def half(n), do: n |> div(2)
      end
      """

      assert FixPythonFloorDiv.analyze(source) == []
    end

    test "no issues for // in comments" do
      source = """
      defmodule Example do
        # use integer division (// in Python)
        def half(n), do: div(n, 2)
      end
      """

      assert FixPythonFloorDiv.analyze(source) == []
    end

    test "no issues for Kernel. / (float division)" do
      source = """
      defmodule Example do
        def half(n), do: Kernel./(n, 2)
      end
      """

      assert FixPythonFloorDiv.analyze(source) == []
    end

    test "no issues for Elixir range step syntax 0..-2//1" do
      source = """
      defmodule Example do
        def middle(list), do: Enum.slice(list, 0..-2//1)
      end
      """

      assert FixPythonFloorDiv.analyze(source) == []
    end

    test "no issues for Elixir range step syntax 1..10//2" do
      source = """
      defmodule Example do
        def evens(n), do: Enum.to_list(1..n//2)
      end
      """

      assert FixPythonFloorDiv.analyze(source) == []
    end

    test "no issues for Elixir range step syntax with variable upper bound n..m//-1" do
      source = """
      defmodule Example do
        def countdown(n, m), do: Enum.to_list(n..m//-1)
      end
      """

      assert FixPythonFloorDiv.analyze(source) == []
    end

    test "no issues for Elixir range step syntax with long variable names i..low_bound//-1" do
      source = """
      defmodule Example do
        def reverse(low_bound, i), do: Enum.reduce(i..low_bound//-1, 0, fn x, acc -> x + acc end)
      end
      """

      assert FixPythonFloorDiv.analyze(source) == []
    end
  end

  describe "fix/1" do
    test "fixes Kernel.// to div in pipe" do
      source = """
      defmodule Example do
        def step(acc, k) do
          acc
          |> Kernel.//(k)
          |> next()
        end
      end
      """

      fixed = FixPythonFloorDiv.fix(source)
      assert fixed =~ "|> div(k)"
      refute fixed =~ "Kernel.//"
    end

    test "fixes Kernel.// standalone call" do
      source = "result = Kernel.//(a, b)\n"
      fixed = FixPythonFloorDiv.fix(source)
      assert fixed =~ "div(a, b)"
      refute fixed =~ "Kernel.//"
    end

    test "fixes infix //" do
      source = "x = a // b\n"
      fixed = FixPythonFloorDiv.fix(source)
      assert fixed =~ "div(a, b)"
      refute fixed =~ "//"
    end

    test "fixes // with complex left operand" do
      source = """
      defmodule Example do
        def gauss(n) do
          result = n * (n + 1) // 2
          result
        end
      end
      """

      fixed = FixPythonFloorDiv.fix(source)
      assert fixed =~ "div(n * (n + 1), 2)"
      refute fixed =~ "//"
    end

    test "does not modify valid div function call" do
      source = """
      defmodule Example do
        def half(n), do: div(n, 2)
      end
      """

      assert FixPythonFloorDiv.fix(source) == source
    end

    test "does not modify pipe into div" do
      source = """
      defmodule Example do
        def half(n), do: n |> div(2)
      end
      """

      assert FixPythonFloorDiv.fix(source) == source
    end

    test "does not modify // in comments" do
      source = """
      defmodule Example do
        # integer division // for Python users
        def half(n), do: div(n, 2)
      end
      """

      assert FixPythonFloorDiv.fix(source) == source
    end

    test "fixes the exact pattern from the row log" do
      source = """
      defp do_combination(n, k, acc) do
        acc
        |> Kernel.*(n - k + 1)
        |> Kernel.//(k)
        |> do_combination(n, k - 1)
      end
      """

      fixed = FixPythonFloorDiv.fix(source)
      assert fixed =~ "|> div(k)"
      refute fixed =~ "Kernel.//"
      # Kernel.* should NOT be touched by this rule
      assert fixed =~ "Kernel.*(n - k + 1)"
    end

    test "does not modify Elixir range step syntax" do
      source = "middle = Enum.slice(list, 0..-2//1)\n"
      assert FixPythonFloorDiv.fix(source) == source
    end

    test "does not modify range step syntax with positive step" do
      source = "evens = Enum.to_list(1..10//2)\n"
      assert FixPythonFloorDiv.fix(source) == source
    end

    test "does not modify range step syntax with variable bounds" do
      source = "Enum.reduce(n..m//-1, 0, fn i, acc -> i + acc end)\n"
      assert FixPythonFloorDiv.fix(source) == source
    end

    test "does not modify range step syntax with long variable names" do
      source = "Enum.reduce(i..low_bound//-1, current_best, fn j, inner_best -> j end)\n"
      assert FixPythonFloorDiv.fix(source) == source
    end
  end
end
