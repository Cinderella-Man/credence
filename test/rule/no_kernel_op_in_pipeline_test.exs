defmodule Credence.Rule.NoKernelOpInPipelineTest do
  use ExUnit.Case

  defp check(code) do
    {:ok, ast} = Code.string_to_quoted(code)
    Credence.Rule.NoKernelOpInPipeline.check(ast, [])
  end

  defp fix(code) do
    Credence.Rule.NoKernelOpInPipeline.fix(code, [])
  end

  describe "fixable?/0" do
    test "reports as fixable" do
      assert Credence.Rule.NoKernelOpInPipeline.fixable?() == true
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # CHECK TESTS
  # ═══════════════════════════════════════════════════════════════════

  describe "check/2 — positive cases" do
    test "flags |> Kernel.==(x)" do
      code = """
      defmodule Example do
        def run(list) do
          list |> Enum.sort() |> Kernel.==(list)
        end
      end
      """

      [issue] = check(code)
      assert issue.rule == :no_kernel_op_in_pipeline
      assert issue.message =~ "Kernel.=="
    end

    test "flags |> Kernel.!=(x)" do
      code = """
      defmodule Example do
        def run(a, b), do: a |> String.downcase() |> Kernel.!=(b)
      end
      """

      [issue] = check(code)
      assert issue.message =~ "Kernel.!="
    end

    test "flags |> Kernel.>=(x)" do
      code = """
      defmodule Example do
        def run(score, threshold), do: score |> calculate() |> Kernel.>=(threshold)
      end
      """

      [issue] = check(code)
      assert issue.message =~ "Kernel.>="
    end

    test "flags |> Kernel.<(x)" do
      code = """
      defmodule Example do
        def run(n), do: n |> abs() |> Kernel.<(10)
      end
      """

      [issue] = check(code)
      assert issue.message =~ "Kernel.<"
    end

    test "flags |> Kernel.===(x)" do
      code = """
      defmodule Example do
        def run(val), do: val |> process() |> Kernel.===(:ok)
      end
      """

      [issue] = check(code)
      assert issue.message =~ "Kernel.==="
    end

    test "flags |> Kernel.and(x)" do
      code = """
      defmodule Example do
        def run(a, b), do: a |> valid?() |> Kernel.and(b)
      end
      """

      [issue] = check(code)
      assert issue.message =~ "Kernel.and"
    end

    test "flags |> Kernel.or(x)" do
      code = """
      defmodule Example do
        def run(a, b), do: a |> check() |> Kernel.or(b)
      end
      """

      [issue] = check(code)
      assert issue.message =~ "Kernel.or"
    end

    test "flags multiple Kernel ops in one pipeline" do
      code = """
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

      issues = check(code)
      assert length(issues) == 2
    end

    test "flags Kernel op in multi-line pipeline" do
      code = """
      defmodule Example do
        def run(list) do
          list
          |> Enum.uniq()
          |> Enum.sort()
          |> Kernel.==(list)
        end
      end
      """

      [issue] = check(code)
      assert issue.rule == :no_kernel_op_in_pipeline
    end
  end

  describe "check/2 — negative cases" do
    test "does not flag Kernel.==(a, b) outside pipeline" do
      code = """
      defmodule Example do
        def run(a, b), do: Kernel.==(a, b)
      end
      """

      assert check(code) == []
    end

    test "does not flag normal operator usage" do
      code = """
      defmodule Example do
        def run(a, b), do: a == b
      end
      """

      assert check(code) == []
    end

    test "does not flag piped Enum/String calls" do
      code = """
      defmodule Example do
        def run(list), do: list |> Enum.sort() |> Enum.reverse()
      end
      """

      assert check(code) == []
    end

    test "does not flag Kernel arithmetic ops in pipeline" do
      code = """
      defmodule Example do
        def run(n), do: n |> Kernel.+(5) |> Kernel.*(2)
      end
      """

      assert check(code) == []
    end

    test "does not flag infix operator usage" do
      code = """
      defmodule Example do
        def run(list), do: Enum.sort(list) == list
      end
      """

      assert check(code) == []
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # FIX TESTS — 1 remaining pipe step (inline)
  # ═══════════════════════════════════════════════════════════════════

  describe "fix/2 — single remaining step (inline)" do
    test "inlines: x |> f() |> Kernel.==(y) → f(x) == y" do
      code = """
      defmodule Example do
        def run(list), do: list |> Enum.sort() |> Kernel.==(list)
      end
      """

      fixed = fix(code)
      assert fixed =~ "Enum.sort(list) == list"
      refute fixed =~ "Kernel"
      refute fixed =~ "|>"
    end

    test "inlines: a |> f() |> Kernel.!=(b) → f(a) != b" do
      code = """
      defmodule Example do
        def run(a, b), do: a |> String.downcase() |> Kernel.!=(b)
      end
      """

      fixed = fix(code)
      assert fixed =~ "String.downcase(a) != b"
      refute fixed =~ "Kernel"
    end

    test "inlines: score |> calculate() |> Kernel.>=(threshold)" do
      code = """
      defmodule Example do
        def run(score, threshold), do: score |> calculate() |> Kernel.>=(threshold)
      end
      """

      fixed = fix(code)
      assert fixed =~ "calculate(score) >= threshold"
      refute fixed =~ "Kernel"
    end

    test "inlines: n |> abs() |> Kernel.<(10)" do
      code = """
      defmodule Example do
        def run(n), do: n |> abs() |> Kernel.<(10)
      end
      """

      fixed = fix(code)
      assert fixed =~ "abs(n) < 10"
      refute fixed =~ "Kernel"
    end

    test "inlines: val |> process() |> Kernel.===(:ok)" do
      code = """
      defmodule Example do
        def run(val), do: val |> process() |> Kernel.===(:ok)
      end
      """

      fixed = fix(code)
      assert fixed =~ "process(val) === :ok"
      refute fixed =~ "Kernel"
    end

    test "inlines: a |> valid?() |> Kernel.and(b)" do
      code = """
      defmodule Example do
        def run(a, b), do: a |> valid?() |> Kernel.and(b)
      end
      """

      fixed = fix(code)
      assert fixed =~ "valid?(a) and b"
      refute fixed =~ "Kernel"
    end

    test "inlines: a |> check() |> Kernel.or(b)" do
      code = """
      defmodule Example do
        def run(a, b), do: a |> check() |> Kernel.or(b)
      end
      """

      fixed = fix(code)
      assert fixed =~ "check(a) or b"
      refute fixed =~ "Kernel"
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # FIX TESTS — 0 remaining pipe steps (direct)
  # ═══════════════════════════════════════════════════════════════════

  describe "fix/2 — zero remaining steps (direct)" do
    test "direct: x |> Kernel.==(y) → x == y" do
      code = """
      defmodule Example do
        def run(a, b), do: a |> Kernel.==(b)
      end
      """

      fixed = fix(code)
      assert fixed =~ "a == b"
      refute fixed =~ "Kernel"
      refute fixed =~ "|>"
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # FIX TESTS — 2+ remaining pipe steps (wrap)
  # ═══════════════════════════════════════════════════════════════════

  describe "fix/2 — multiple remaining steps" do
    test "wraps: x |> f() |> g() |> Kernel.==(y) → x |> f() |> g() == y" do
      code = """
      defmodule Example do
        def run(list) do
          list |> Enum.uniq() |> Enum.sort() |> Kernel.==(list)
        end
      end
      """

      fixed = fix(code)
      # Pipeline should remain, Kernel.== becomes infix ==
      assert fixed =~ "=="
      assert fixed =~ "|>"
      assert fixed =~ "Enum.uniq()"
      assert fixed =~ "Enum.sort()"
      refute fixed =~ "Kernel"
    end

    test "multi-line pipeline" do
      code = """
      defmodule Example do
        def run(list) do
          list
          |> Enum.uniq()
          |> Enum.sort()
          |> Kernel.==(list)
        end
      end
      """

      fixed = fix(code)
      assert fixed =~ "=="
      assert fixed =~ "Enum.uniq()"
      assert fixed =~ "Enum.sort()"
      refute fixed =~ "Kernel"
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # FIX TESTS — multiple ops, edge cases
  # ═══════════════════════════════════════════════════════════════════

  describe "fix/2 — edge cases" do
    test "fixes chained Kernel ops" do
      code = """
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

      fixed = fix(code)
      assert fixed =~ "=="
      assert fixed =~ "or"
      refute fixed =~ "Kernel."
    end

    test "does not touch arithmetic Kernel ops" do
      code = """
      defmodule Example do
        def run(n), do: n |> Kernel.+(5)
      end
      """

      fixed = fix(code)
      assert fixed =~ "Kernel.+"
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
      code = """
      defmodule Example do
        def a(x), do: x + 1

        def b(list) do
          list |> Enum.sort() |> Kernel.==(list)
        end

        def c(y), do: y * 2
      end
      """

      fixed = fix(code)
      assert fixed =~ "Enum.sort(list) == list"
      refute fixed =~ "Kernel."
    end
  end
end
