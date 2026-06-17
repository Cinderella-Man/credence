defmodule Credence.Pattern.NoAnonFnApplicationInPipeCheckTest do
  use Credence.RuleCase, async: true

  alias Credence.Issue
  alias Credence.Pattern.NoAnonFnApplicationInPipe

  describe "does not flag" do
    test "code using then/2" do
      assert clean?(NoAnonFnApplicationInPipe, """
             defmodule GoodThen do
               def process(list) do
                 list
                 |> Enum.sort()
                 |> then(fn s -> [1 | s] end)
               end
             end
             """)
    end

    test "normal function calls in pipes" do
      assert clean?(NoAnonFnApplicationInPipe, """
             defmodule GoodPipe do
               def process(list) do
                 list
                 |> Enum.sort()
                 |> Enum.reverse()
                 |> hd()
               end
             end
             """)
    end

    test "anonymous function applied outside a pipe" do
      assert clean?(NoAnonFnApplicationInPipe, """
             defmodule SafeAnon do
               def process(x) do
                 fun = fn y -> y * 2 end
                 fun.(x)
               end
             end
             """)
    end

    test ".(extra) — then/2 cannot carry extra args" do
      assert clean?(NoAnonFnApplicationInPipe, "x |> (fn a, b -> a + b end).(y)")
    end
  end

  describe "flags" do
    test "anonymous function application in pipe" do
      issues =
        check(NoAnonFnApplicationInPipe, """
        defmodule BadPipe do
          def process(list) do
            list
            |> Enum.scan(1, &*/2)
            |> (fn s -> [1 | s] end).()
          end
        end
        """)

      assert length(issues) == 1
      issue = hd(issues)
      assert %Issue{} = issue
      assert issue.rule == :no_anon_fn_application_in_pipe
      assert issue.message =~ "then/2"
      assert issue.meta.line != nil
    end

    test "multiple anonymous function applications in a pipeline" do
      issues =
        check(NoAnonFnApplicationInPipe, """
        defmodule MultipleBad do
          def process(x) do
            x
            |> (fn a -> a + 1 end).()
            |> (fn b -> b * 2 end).()
          end
        end
        """)

      assert length(issues) == 2
    end
  end
end
