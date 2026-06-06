defmodule Credence.Pattern.NoKernelOpInPipelineFixTest do
  use ExUnit.Case

  alias Credence.Pattern.NoKernelOpInPipeline

  defp fix(code) do
    Credence.RuleHelpers.apply_rule_fix(NoKernelOpInPipeline, code, [])
    |> Code.format_string!()
    |> IO.iodata_to_binary()
    |> Kernel.<>("\n")
  end

  describe "fix/2 — single remaining step (inline)" do
    test "inlines: x |> f() |> Kernel.==(y) → f(x) == y" do
      input = """
      defmodule Example do
        def run(list), do: list |> Enum.sort() |> Kernel.==(list)
      end
      """

      expected = """
      defmodule Example do
        def run(list), do: Enum.sort(list) == list
      end
      """

      assert fix(input) == expected
    end

    test "inlines: a |> f() |> Kernel.!=(b) → f(a) != b" do
      input = """
      defmodule Example do
        def run(a, b), do: a |> String.downcase() |> Kernel.!=(b)
      end
      """

      expected = """
      defmodule Example do
        def run(a, b), do: String.downcase(a) != b
      end
      """

      assert fix(input) == expected
    end

    test "inlines: score |> calculate() |> Kernel.>=(threshold)" do
      input = """
      defmodule Example do
        def run(score, threshold), do: score |> calculate() |> Kernel.>=(threshold)
      end
      """

      expected = """
      defmodule Example do
        def run(score, threshold), do: calculate(score) >= threshold
      end
      """

      assert fix(input) == expected
    end

    test "inlines: n |> abs() |> Kernel.<(10)" do
      input = """
      defmodule Example do
        def run(n), do: n |> abs() |> Kernel.<(10)
      end
      """

      expected = """
      defmodule Example do
        def run(n), do: abs(n) < 10
      end
      """

      assert fix(input) == expected
    end

    test "inlines: val |> process() |> Kernel.===(:ok)" do
      input = """
      defmodule Example do
        def run(val), do: val |> process() |> Kernel.===(:ok)
      end
      """

      expected = """
      defmodule Example do
        def run(val), do: process(val) === :ok
      end
      """

      assert fix(input) == expected
    end

    test "inlines: a |> valid?() |> Kernel.and(b)" do
      input = """
      defmodule Example do
        def run(a, b), do: a |> valid?() |> Kernel.and(b)
      end
      """

      expected = """
      defmodule Example do
        def run(a, b), do: valid?(a) and b
      end
      """

      assert fix(input) == expected
    end

    test "inlines: a |> check() |> Kernel.or(b)" do
      input = """
      defmodule Example do
        def run(a, b), do: a |> check() |> Kernel.or(b)
      end
      """

      expected = """
      defmodule Example do
        def run(a, b), do: check(a) or b
      end
      """

      assert fix(input) == expected
    end
  end

  describe "fix/2 — zero remaining steps (direct)" do
    test "direct: x |> Kernel.==(y) → x == y" do
      input = """
      defmodule Example do
        def run(a, b), do: a |> Kernel.==(b)
      end
      """

      expected = """
      defmodule Example do
        def run(a, b), do: a == b
      end
      """

      assert fix(input) == expected
    end
  end

  describe "fix/2 — multiple remaining steps" do
    test "wraps: x |> f() |> g() |> Kernel.==(y) → x |> f() |> g() == y" do
      input = """
      defmodule Example do
        def run(list) do
          list |> Enum.uniq() |> Enum.sort() |> Kernel.==(list)
        end
      end
      """

      expected = """
      defmodule Example do
        def run(list) do
          list |> Enum.uniq() |> Enum.sort() == list
        end
      end
      """

      assert fix(input) == expected
    end

    test "multi-line pipeline" do
      input = """
      defmodule Example do
        def run(list) do
          list
          |> Enum.uniq()
          |> Enum.sort()
          |> Kernel.==(list)
        end
      end
      """

      expected = """
      defmodule Example do
        def run(list) do
          list
          |> Enum.uniq()
          |> Enum.sort() == list
        end
      end
      """

      assert fix(input) == expected
    end
  end

  describe "fix/2 — edge cases" do
    test "fixes chained Kernel ops" do
      input = """
      defmodule Example do
        def run(list) do
          list
          |> Enum.uniq()
          |> Enum.sort()
          |> Kernel.==(list)
          |> Kernel.or(false)
        end
      end
      """

      expected = """
      defmodule Example do
        def run(list) do
          list
          |> Enum.uniq()
          |> Enum.sort() == list or false
        end
      end
      """

      assert fix(input) == expected
    end

    test "does not touch arithmetic Kernel ops" do
      code = """
      defmodule Example do
        def run(n), do: n |> Kernel.+(5)
      end
      """

      assert fix(code) == code
    end

    test "returns source unchanged when nothing to fix" do
      code = """
      defmodule Example do
        def run(list), do: Enum.sort(list) == list
      end
      """

      assert fix(code) == code
    end

    test "preserves surrounding functions" do
      input = """
      defmodule Example do
        def a(x), do: x + 1

        def b(list) do
          list |> Enum.sort() |> Kernel.==(list)
        end

        def c(y), do: y * 2
      end
      """

      expected = """
      defmodule Example do
        def a(x), do: x + 1

        def b(list) do
          Enum.sort(list) == list
        end

        def c(y), do: y * 2
      end
      """

      assert fix(input) == expected
    end
  end
end
