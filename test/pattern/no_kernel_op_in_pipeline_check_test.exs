defmodule Credence.Pattern.NoKernelOpInPipelineCheckTest do
  use ExUnit.Case

  alias Credence.Pattern.NoKernelOpInPipeline

  defp check(code) do
    ast = Sourceror.parse_string!(code)
    NoKernelOpInPipeline.check(ast, [])
  end

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
end
