defmodule Credence.Rule.NoAnonFnApplicationInPipeTest do
  use ExUnit.Case
  alias Credence.Issue

  defp check(code) do
    {:ok, ast} = Code.string_to_quoted(code)
    Credence.Rule.NoAnonFnApplicationInPipe.check(ast, [])
  end

  describe "NoAnonFnApplicationInPipe" do
    test "passes code using then/2" do
      code = """
      defmodule GoodThen do
        def process(list) do
          list
          |> Enum.sort()
          |> then(fn s -> [1 | s] end)
        end
      end
      """

      assert check(code) == []
    end

    test "passes normal function calls in pipes" do
      code = """
      defmodule GoodPipe do
        def process(list) do
          list
          |> Enum.sort()
          |> Enum.reverse()
          |> hd()
        end
      end
      """

      assert check(code) == []
    end

    test "passes anonymous function applied outside a pipe" do
      code = """
      defmodule SafeAnon do
        def process(x) do
          fun = fn y -> y * 2 end
          fun.(x)
        end
      end
      """

      assert check(code) == []
    end

    test "detects anonymous function application in pipe" do
      code = """
      defmodule BadPipe do
        def process(list) do
          list
          |> Enum.scan(1, &*/2)
          |> (fn s -> [1 | s] end).()
        end
      end
      """

      issues = check(code)

      assert length(issues) == 1
      issue = hd(issues)
      assert %Issue{} = issue
      assert issue.rule == :no_anon_fn_application_in_pipe

      assert issue.message =~ "then/2"
      assert issue.meta.line != nil
    end

    test "detects multiple anonymous function applications in a pipeline" do
      code = """
      defmodule MultipleBad do
        def process(x) do
          x
          |> (fn a -> a + 1 end).()
          |> (fn b -> b * 2 end).()
        end
      end
      """

      issues = check(code)

      assert length(issues) == 2
    end
  end
end
