defmodule Credence.Semantic.FixStructTestInGuardCheckTest do
  use ExUnit.Case

  alias Credence.Semantic.FixStructTestInGuard

  @real_message "cannot invoke remote function Map.get/2 inside a guard"

  defp diagnostic(message \\ @real_message) do
    %{severity: :error, message: message, position: {2, 1}}
  end

  describe "match?/1" do
    test "the recorded diagnostic" do
      assert FixStructTestInGuard.match?(diagnostic())
    end

    # `match?/1` claims the whole family on purpose — nothing else does, measured for
    # docs/18 at 0 of 90 live semantic rules — and `should_report?/2` is what narrows it
    # to the shape this rule can actually repair.
    test "other members of the same family" do
      for function <- ["String.length/1", "MapSet.member?/2", "System.monotonic_time/1"] do
        assert FixStructTestInGuard.match?(
                 diagnostic("cannot invoke remote function #{function} inside a guard")
               )
      end
    end

    test "an Erlang-module remote call" do
      assert FixStructTestInGuard.match?(
               diagnostic("cannot invoke remote function :erlang.foo/1 inside a guard")
             )
    end

    test "declines a warning of the same wording" do
      refute FixStructTestInGuard.match?(%{
               severity: :warning,
               message: @real_message,
               position: {2, 1}
             })
    end

    test "declines the local-function diagnostic, which is a different rule's" do
      refute FixStructTestInGuard.match?(
               diagnostic("cannot find or invoke local is_range/1 inside a guard")
             )
    end

    test "declines an unrelated diagnostic" do
      refute FixStructTestInGuard.match?(diagnostic("undefined function foo/0"))
    end
  end

  # The gate that keeps a rule from reporting what it will not fix. Semantic dispatch is
  # first-match-wins, so a rule that matches broadly must decline out loud.
  describe "should_report?/2" do
    test "true for the repairable shape" do
      source = """
      defmodule G do
        def f(v) when Map.get(v, :__struct__) == Regex, do: {:regex, v}
        def f(v), do: {:plain, v}
      end
      """

      assert FixStructTestInGuard.should_report?(diagnostic(), source)
    end

    test "false when the parameter is already a pattern" do
      source = """
      defmodule G do
        def go(x, %{} = re) when Map.get(re, :__struct__) == Regex, do: {:regex_matched, x}
        def go(x, _other), do: {:plain, x}
      end
      """

      refute FixStructTestInGuard.should_report?(diagnostic(), source)
    end

    test "false for a shape whose only repair would be the body hoist" do
      source = """
      defmodule G do
        def f(n) when String.length(n) > 0, do: :ok
        def f(_n), do: :empty
      end
      """

      refute FixStructTestInGuard.should_report?(
               diagnostic("cannot invoke remote function String.length/1 inside a guard"),
               source
             )
    end

    test "false for an or guard" do
      source = """
      defmodule G do
        def f(v) when is_nil(v) or Map.get(v, :__struct__) == Regex, do: :r
        def f(_v), do: :o
      end
      """

      refute FixStructTestInGuard.should_report?(diagnostic(), source)
    end
  end

  describe "to_issue/1" do
    test "carries the rule name and the diagnostic's line" do
      issue = FixStructTestInGuard.to_issue(diagnostic())

      assert issue.rule == :fix_struct_test_in_guard
      assert issue.meta.line == 2
      assert issue.message =~ "%Struct{} = var"
    end
  end

  # End to end, through the public entry point rather than the callbacks.
  describe "the live pipeline" do
    test "analyze reports it, and fix repairs it" do
      source = """
      defmodule LiveDispatch do
        def f(v) when Map.get(v, :__struct__) == Regex, do: {:regex, v}
        def f(v), do: {:plain, v}
      end
      """

      analysis = Credence.analyze(source)

      assert Enum.map(analysis.issues, & &1.rule) == [:fix_struct_test_in_guard]
      refute analysis.valid

      result = Credence.fix(source)

      expected =
        """
        defmodule LiveDispatch do
          def f(%Regex{} = v), do: {:regex, v}
          def f(v), do: {:plain, v}
        end
        """
        |> String.trim_trailing()

      assert result.applied_rules == [{FixStructTestInGuard, 1}]
      assert result.code == expected
    end
  end
end
