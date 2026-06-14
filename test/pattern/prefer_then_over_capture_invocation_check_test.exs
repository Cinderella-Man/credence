defmodule Credence.Pattern.PreferThenOverCaptureInvocationCheckTest do
  use Credence.RuleCase, async: true

  alias Credence.Issue
  alias Credence.Pattern.PreferThenOverCaptureInvocation

  describe "does not flag" do
    test "code already using then/2" do
      assert clean?(PreferThenOverCaptureInvocation, """
             defmodule Good do
               def palindrome?(number) do
                 number
                 |> Integer.to_string()
                 |> then(&(&1 == String.reverse(&1)))
               end
             end
             """)
    end

    test "normal function calls in pipes" do
      assert clean?(PreferThenOverCaptureInvocation, """
             defmodule Good do
               def process(list) do
                 list
                 |> Enum.sort()
                 |> Enum.reverse()
               end
             end
             """)
    end

    test "capture with explicit args in .()" do
      assert clean?(PreferThenOverCaptureInvocation, "x |> (&(&1 + &2)).(y)")
    end

    test "capture with arity > 1 invoked with no args" do
      # This would raise an error, but we leave it alone because
      # then/2 would raise a different error (FunctionClauseError vs ArityError)
      assert clean?(PreferThenOverCaptureInvocation, "x |> (&(&1 + &2)).()")
    end

    test "capture without &1 placeholder" do
      # &String.reverse/1 is a function reference, not a capture with placeholders
      assert clean?(PreferThenOverCaptureInvocation, "x |> (&String.reverse/1).()")
    end
  end

  describe "flags" do
    test "immediately-invoked capture in pipe" do
      issues =
        check(PreferThenOverCaptureInvocation, """
        defmodule Bad do
          def palindrome?(number) do
            number
            |> Integer.to_string()
            |> (&(&1 == String.reverse(&1))).()
          end
        end
        """)

      assert length(issues) == 1
      issue = hd(issues)
      assert %Issue{} = issue
      assert issue.rule == :prefer_then_over_capture_invocation
      assert issue.message =~ "then/2"
      assert issue.meta.line != nil
    end

    test "simple capture with &1" do
      issues =
        check(PreferThenOverCaptureInvocation, "x |> (&(&1 + 1)).()")

      assert length(issues) == 1
    end

    test "capture using &1 directly" do
      issues =
        check(PreferThenOverCaptureInvocation, "x |> (& &1).()")

      assert length(issues) == 1
    end
  end
end
