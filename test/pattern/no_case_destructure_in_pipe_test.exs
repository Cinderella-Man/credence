defmodule Credence.Pattern.NoCaseDestructureInPipeTest do
  use ExUnit.Case

  alias Credence.Issue
  alias Credence.Pattern.NoCaseDestructureInPipe

  defp check(code) do
    ast = Sourceror.parse_string!(code)
    NoCaseDestructureInPipe.check(ast, [])
  end

  describe "NoCaseDestructureInPipe" do
    test "passes multi-clause case in pipe" do
      code = """
      defmodule GoodCase do
        def process(result) do
          result
          |> case do
            {:ok, value} -> value
            {:error, _} -> nil
          end
        end
      end
      """

      assert check(code) == []
    end

    test "passes case not in a pipe" do
      code = """
      defmodule GoodCase do
        def process(result) do
          case result do
            {a, b} -> a + b
          end
        end
      end
      """

      assert check(code) == []
    end

    test "passes then/1 in pipe" do
      code = """
      defmodule GoodThen do
        def process(list) do
          list
          |> Enum.reduce({0, 0}, fn x, {a, b} -> {a + x, b + 1} end)
          |> then(fn {sum, count} -> sum / count end)
        end
      end
      """

      assert check(code) == []
    end

    test "detects single-clause case with tuple pattern in pipe" do
      code = """
      defmodule BadCase do
        def process(list) do
          list
          |> Enum.reduce({0, 0}, fn x, {a, b} -> {a + x, b + 1} end)
          |> case do
            {sum, count} -> sum / count
          end
        end
      end
      """

      issues = check(code)

      assert length(issues) == 1
      issue = hd(issues)
      assert %Issue{} = issue
      assert issue.rule == :no_case_destructure_in_pipe
      assert issue.message =~ "then/1"
      assert issue.meta.line != nil
    end

    test "detects single-clause case with variable pattern in pipe" do
      code = """
      defmodule BadCase do
        def process(x) do
          x
          |> compute()
          |> case do
            value -> value + 1
          end
        end
      end
      """

      issues = check(code)

      assert length(issues) == 1
      issue = hd(issues)
      assert issue.rule == :no_case_destructure_in_pipe
    end

    test "detects single-clause case with literal pattern in pipe" do
      code = """
      defmodule BadCase do
        def process(x) do
          x
          |> fetch()
          |> case do
            {:ok, result} -> result
          end
        end
      end
      """

      issues = check(code)

      assert length(issues) == 1
      issue = hd(issues)
      assert issue.rule == :no_case_destructure_in_pipe
    end

    test "does not flag non-piped single-clause case" do
      code = """
      defmodule NeutralCase do
        def process(x) do
          case x do
            {a, b} -> a + b
          end
        end
      end
      """

      assert check(code) == []
    end

    test "does not flag multi-clause case even in pipe" do
      code = """
      defmodule GoodMultiCase do
        def process(x) do
          x
          |> compute()
          |> case do
            {:ok, val} -> val
            {:error, reason} -> raise reason
          end
        end
      end
      """

      assert check(code) == []
    end
  end
end
